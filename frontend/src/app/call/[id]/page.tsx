"use client";

import { useState, use, useEffect, useRef } from "react";
import { gql } from "@apollo/client";
import { useQuery, useMutation, useSubscription } from "@apollo/client/react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import {
  ArrowLeft,
  Send,
  Siren,
  MapPin,
  Activity,
  AlertCircle,
  PhoneOff,
  User,
  Phone,
  Clock,
  TrendingUp,
} from "lucide-react";
import clsx from "clsx";

/* ── GraphQL ──────────────────────────────────────────── */
const CALL_DETAIL = gql`
  query GetCallDetail($callId: ID!) {
    operatorCallDetail(callId: $callId) {
      id
      status
      emergencyType
      latitude
      longitude
      address
      peakUrgencyScore
      startedAt
      callerName
      callerPhone
      hasOperator
    }
    operatorCallFrames(callId: $callId) {
      id
      recognizedSigns
      urgencyScore
      emotionAngry
      emotionSad
      emotionNeutral
      emotionHappy
      emotionSurprise
      emotionAfraid
      emotionDisgust
      recordedAt
    }
    operatorMessages(callId: $callId) {
      id
      text
      sentAt
      sender
    }
  }
`;

const CALL_SUB = gql`
  subscription OnCallUpdate($callId: ID!) {
    emergencyCallUpdated(callId: $callId) {
      callId
      status
      peakUrgencyScore
      emergencyType
      updatedAt
    }
  }
`;

const MSG_SUB = gql`
  subscription OnMsg($callId: ID!) {
    operatorMessageReceived(callId: $callId) {
      messageId
      text
      sentAt
      sender
    }
  }
`;

const SEND_MSG = gql`
  mutation SendMsg($callId: ID!, $text: String!) {
    sendOperatorMessage(input: { callId: $callId, text: $text }) {
      id
      sentAt
    }
  }
`;

const DISPATCH = gql`
  mutation Dispatch($callId: ID!, $type: String!) {
    createDispatchEvent(input: { callId: $callId, dispatchType: $type }) {
      id
      dispatchType
    }
  }
`;

const END_CALL = gql`
  mutation EndCall($callId: ID!, $outcome: String!) {
    operatorEndCall(callId: $callId, outcome: $outcome) {
      id
      status
    }
  }
`;

/* ── Constants ────────────────────────────────────────── */
const EMOTIONS: { key: string; label: string; color: string }[] = [
  { key: "emotionAngry",    label: "Angry",    color: "#ef4444" },
  { key: "emotionAfraid",   label: "Afraid",   color: "#a855f7" },
  { key: "emotionSad",      label: "Sad",      color: "#3b82f6" },
  { key: "emotionDisgust",  label: "Disgust",  color: "#22c55e" },
  { key: "emotionSurprise", label: "Surprise", color: "#f59e0b" },
  { key: "emotionNeutral",  label: "Neutral",  color: "#6b7280" },
  { key: "emotionHappy",    label: "Happy",    color: "#10b981" },
];

const CRITICAL_SIGNS = new Set(["help", "pain", "doctor", "accident"]);

/* ── Helpers ──────────────────────────────────────────── */
function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function formatElapsed(startedAt: string) {
  const diffMs = Date.now() - new Date(startedAt).getTime();
  const totalSec = Math.floor(diffMs / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}m ${s.toString().padStart(2, "0")}s`;
}

function isAiMessage(m: Record<string, any>): boolean {
  // Check sender field, or fall back to heuristic: starts with "AI:" prefix
  if (m.sender) return m.sender === "AI" || m.sender === "ai";
  return typeof m.text === "string" && m.text.startsWith("AI:");
}

/* ── Page ─────────────────────────────────────────────── */
export default function CallHandlingPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const router = useRouter();
  const { token } = useAuth();
  const { id } = use(params);
  const [msgText, setMsgText] = useState("");
  const [messages, setMessages] = useState<Record<string, any>[]>([]);
  const [dispatchedTypes, setDispatchedTypes] = useState<Set<string>>(new Set());
  const [elapsedTick, setElapsedTick] = useState(0);
  const chatBottomRef = useRef<HTMLDivElement>(null);

  // Auth guard
  useEffect(() => {
    if (token === null) router.push("/login");
  }, [token, router]);

  // Tick elapsed timer every second
  useEffect(() => {
    const t = setInterval(() => setElapsedTick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);

  const { data, loading } = useQuery<any>(CALL_DETAIL, {
    variables: { callId: id },
    pollInterval: 5000,
    skip: !token,
  });

  // Seed the messages list from the initial query result (only once).
  useEffect(() => {
    if (data?.operatorMessages && messages.length === 0) {
      setMessages(data.operatorMessages);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]);

  useSubscription(CALL_SUB, { variables: { callId: id }, skip: !token });

  useSubscription(MSG_SUB, {
    variables: { callId: id },
    skip: !token,
    onData: ({ data: subData }: { data: any }) => {
      const newMsg = subData.data?.operatorMessageReceived;
      if (newMsg) setMessages((prev) => [...prev, newMsg]);
    },
  });

  const [sendMsg, { loading: sending }] = useMutation(SEND_MSG);
  const [dispatchEvent] = useMutation(DISPATCH);
  const [endCall] = useMutation(END_CALL);

  // Auto-scroll chat
  useEffect(() => {
    chatBottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  if (token === null) return null;
  if (loading && !data) return <FullPageLoader />;
  if (!data?.operatorCallDetail) return <FullPageError onBack={() => router.push("/dashboard")} />;

  const call = data.operatorCallDetail;
  const frames: Record<string, any>[] = data.operatorCallFrames || [];
  const latestFrame = frames.length > 0 ? frames[frames.length - 1] : null;

  // All distinct signs from last 30 frames
  const allSigns: string[] = Array.from(
    new Set(frames.flatMap((f) => f.recognizedSigns as string[]).slice(-60))
  );
  const criticalSigns = allSigns.filter((s) => CRITICAL_SIGNS.has(s));
  const normalSigns = allSigns.filter((s) => !CRITICAL_SIGNS.has(s));

  // Timeline: last 20 urgency scores for sparkline
  const timelineScores = frames.slice(-20).map((f) => f.urgencyScore as number);

  const isCritical = call.peakUrgencyScore >= 0.75;
  const isElevated = call.peakUrgencyScore >= 0.5 && !isCritical;

  const statusColor = isCritical ? "var(--critical)" : isElevated ? "var(--warning)" : "var(--success)";
  const statusLabel = isCritical ? "CRITICAL" : isElevated ? "ELEVATED" : "MONITORED";

  const handleSend = (e: React.FormEvent) => {
    e.preventDefault();
    if (!msgText.trim()) return;
    sendMsg({ variables: { callId: id, text: msgText } });
    setMessages((prev) => [
      ...prev,
      { id: `opt-${Date.now()}`, text: msgText, sentAt: new Date().toISOString(), sender: "OPERATOR" },
    ]);
    setMsgText("");
  };

  const handleDispatch = (type: string) => {
    dispatchEvent({ variables: { callId: id, type } });
    setDispatchedTypes((prev) => new Set(prev).add(type));
  };

  const handleEndCall = () => {
    if (confirm("End this call and mark as RESOLVED?")) {
      endCall({ variables: { callId: id, outcome: "RESOLVED" } }).then(() => {
        router.push("/dashboard");
      });
    }
  };

  return (
    <div className="min-h-screen flex flex-col" style={{ background: "var(--bg)" }}>
      {/* ── Top bar ─────────────────────── */}
      <header
        className="glass sticky top-0 z-20 flex items-center justify-between px-6 py-3"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <div className="flex items-center gap-4">
          <button
            onClick={() => router.push("/dashboard")}
            className="p-2 rounded-lg transition-colors"
            style={{ color: "var(--text-secondary)", background: "transparent" }}
            onMouseOver={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "rgba(255,255,255,0.06)")}
            onMouseOut={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "transparent")}
          >
            <ArrowLeft size={18} />
          </button>

          <div>
            <div className="flex items-center gap-2">
              <h1 className="font-bold text-base" style={{ color: "var(--text-primary)" }}>
                {call.callerName}
              </h1>
              <span
                className="px-2 py-0.5 rounded-md text-xs font-bold uppercase tracking-wide"
                style={{
                  background: isCritical ? "var(--critical-dim)" : "var(--brand-dim)",
                  color: isCritical ? "var(--critical)" : "var(--brand)",
                }}
              >
                {call.emergencyType}
              </span>
              {isCritical && (
                <span
                  className="relative w-2 h-2 rounded-full ping-dot"
                  style={{ background: "var(--critical)", display: "inline-block" }}
                />
              )}
            </div>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              {call.callerPhone} · Started {formatTime(call.startedAt)} · {formatElapsed(call.startedAt)} elapsed
            </p>
          </div>
        </div>

        {/* Action buttons */}
        <div className="flex items-center gap-2">
          <DispatchButton
            label="Ambulance"
            dispatched={dispatchedTypes.has("AMBULANCE")}
            color="#f59e0b"
            dimColor="rgba(245,158,11,0.1)"
            onClick={() => handleDispatch("AMBULANCE")}
          />
          <DispatchButton
            label="Police"
            dispatched={dispatchedTypes.has("POLICE")}
            color="#3b82f6"
            dimColor="rgba(59,130,246,0.1)"
            onClick={() => handleDispatch("POLICE")}
          />
          <DispatchButton
            label="Fire"
            dispatched={dispatchedTypes.has("FIRE")}
            color="#ef4444"
            dimColor="rgba(239,68,68,0.1)"
            onClick={() => handleDispatch("FIRE")}
          />
          <button
            onClick={handleEndCall}
            className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-bold transition-all ml-2"
            style={{
              background: "var(--critical-dim)",
              border: "1px solid rgba(239,68,68,0.3)",
              color: "var(--critical)",
            }}
            onMouseOver={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "rgba(239,68,68,0.2)")}
            onMouseOut={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "var(--critical-dim)")}
          >
            <PhoneOff size={14} />
            End Call
          </button>
        </div>
      </header>

      {/* ── Body ─────────────────────────── */}
      <div className="flex-1 flex overflow-hidden" style={{ minHeight: 0 }}>
        {/* ── Left sidebar (wider, richer) ── */}
        <aside
          className="w-96 shrink-0 flex flex-col overflow-y-auto"
          style={{ background: "var(--surface-1)", borderRight: "1px solid var(--border)" }}
        >
          {/* Caller info card */}
          <div className="p-5 animate-slide-left delay-0">
            <SectionHeader icon={<User size={13} />} label="Caller" />
            <div
              className="mt-3 rounded-2xl p-4 space-y-3"
              style={{
                background: isCritical ? "rgba(239,68,68,0.06)" : "rgba(59,130,246,0.05)",
                border: `1px solid ${isCritical ? "rgba(239,68,68,0.18)" : "rgba(59,130,246,0.12)"}`,
              }}
            >
              {/* Status badge */}
              <div className="flex items-center justify-between">
                <span
                  className="px-2.5 py-1 rounded-lg text-xs font-bold uppercase tracking-wider"
                  style={{ background: `${statusColor}18`, color: statusColor }}
                >
                  {statusLabel}
                </span>
                <span
                  className="font-mono text-lg font-black"
                  style={{ color: statusColor }}
                >
                  {(call.peakUrgencyScore * 100).toFixed(0)}%
                </span>
              </div>

              {/* Caller details */}
              <div className="space-y-2">
                <InfoRow icon={<User size={12} />} value={call.callerName} />
                <InfoRow icon={<Phone size={12} />} value={call.callerPhone} />
                <InfoRow icon={<Clock size={12} />} value={`Started ${formatTime(call.startedAt)}`} />
                {call.address && (
                  <InfoRow icon={<MapPin size={12} />} value={call.address} />
                )}
              </div>

              {/* Emergency type */}
              <div
                className="flex items-center gap-2 py-2 px-3 rounded-xl text-xs font-semibold"
                style={{ background: "rgba(255,255,255,0.04)", color: "var(--text-secondary)" }}
              >
                <AlertCircle size={12} style={{ flexShrink: 0 }} />
                {call.emergencyType || "Unknown Emergency"}
              </div>
            </div>
          </div>

          <Divider />

          {/* Urgency timeline sparkline */}
          <div className="p-5 animate-slide-left delay-1">
            <SectionHeader icon={<TrendingUp size={13} />} label="Urgency Timeline" />
            <div className="mt-3">
              {timelineScores.length === 0 ? (
                <p className="text-xs py-3 text-center" style={{ color: "var(--text-muted)" }}>
                  Collecting data…
                </p>
              ) : (
                <div className="flex items-end gap-0.5 h-12">
                  {timelineScores.map((score, i) => {
                    const pct = Math.max(4, Math.round(score * 100));
                    const color =
                      score >= 0.75
                        ? "#ef4444"
                        : score >= 0.5
                        ? "#f59e0b"
                        : "#3b82f6";
                    return (
                      <div
                        key={i}
                        className="flex-1 rounded-sm transition-all"
                        style={{
                          height: `${pct}%`,
                          background: color,
                          opacity: 0.7 + (i / timelineScores.length) * 0.3,
                          minHeight: 2,
                        }}
                        title={`${pct}%`}
                      />
                    );
                  })}
                </div>
              )}
              <div className="flex justify-between text-xs mt-1" style={{ color: "var(--text-muted)" }}>
                <span>Earlier</span>
                <span>Now</span>
              </div>
            </div>
          </div>

          <Divider />

          {/* Emotion bars */}
          <div className="p-5 animate-slide-left delay-2">
            <SectionHeader icon={<AlertCircle size={13} />} label="Patient State" />
            <div className="mt-3 space-y-2">
              {EMOTIONS.map((em, i) => {
                const val: number = latestFrame?.[em.key] ?? 0;
                const pct = (val * 100).toFixed(0);
                return (
                  <div key={em.key} className={`animate-fade-up delay-${Math.min(i, 6)}`}>
                    <div className="flex items-center justify-between mb-1">
                      <div className="flex items-center gap-2">
                        <span
                          className="px-2 py-0.5 rounded-md text-xs font-semibold"
                          style={{
                            background: `${em.color}18`,
                            color: em.color,
                          }}
                        >
                          {em.label}
                        </span>
                      </div>
                      <span className="font-mono text-xs" style={{ color: em.color, opacity: 0.8 }}>
                        {pct}%
                      </span>
                    </div>
                    <div
                      className="h-1 rounded-full overflow-hidden"
                      style={{ background: "rgba(255,255,255,0.05)" }}
                    >
                      <div
                        className="h-full rounded-full animate-bar-fill"
                        style={{ width: `${val * 100}%`, background: em.color, opacity: 0.85 }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          <Divider />

          {/* Recognised signs — colour-coded pills */}
          <div className="p-5 flex-1 animate-slide-left delay-3">
            <SectionHeader icon={<Activity size={13} />} label="Recognised Signs" />
            <div className="mt-3 space-y-3">
              {allSigns.length === 0 ? (
                <p className="text-xs text-center py-4" style={{ color: "var(--text-muted)" }}>
                  No signs detected yet
                </p>
              ) : (
                <>
                  {criticalSigns.length > 0 && (
                    <div>
                      <p className="text-xs mb-2" style={{ color: "var(--text-muted)" }}>Critical</p>
                      <div className="flex flex-wrap gap-1.5">
                        {criticalSigns.map((sign) => (
                          <SignPill key={sign} sign={sign} critical />
                        ))}
                      </div>
                    </div>
                  )}
                  {normalSigns.length > 0 && (
                    <div>
                      <p className="text-xs mb-2" style={{ color: "var(--text-muted)" }}>Detected</p>
                      <div className="flex flex-wrap gap-1.5">
                        {normalSigns.map((sign) => (
                          <SignPill key={sign} sign={sign} critical={false} />
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        </aside>

        {/* ── Chat panel ── */}
        <div
          className="flex-1 flex flex-col"
          style={{ background: "var(--surface-2)", minWidth: 0 }}
        >
          {/* Messages */}
          <div className="flex-1 overflow-y-auto px-6 py-5 space-y-3">
            <div className="flex justify-center">
              <span
                className="px-3 py-1 rounded-full text-xs font-medium"
                style={{
                  background: "rgba(255,255,255,0.05)",
                  color: "var(--text-muted)",
                  border: "1px solid var(--border)",
                }}
              >
                Call started {formatTime(call.startedAt)}
              </span>
            </div>

            {messages.length === 0 && (
              <p className="text-center text-xs py-8" style={{ color: "var(--text-muted)" }}>
                No messages yet — type below to send a sign language prompt
              </p>
            )}

            {messages.map((m, i) => {
              const ai = isAiMessage(m);
              return (
                <div
                  key={m.id || i}
                  className={clsx(
                    "flex flex-col animate-msg-pop",
                    ai ? "items-start" : "items-end"
                  )}
                  style={{ animationDelay: `${i * 20}ms` }}
                >
                  {/* Sender label */}
                  <span
                    className="text-xs mb-1 px-1"
                    style={{ color: "var(--text-muted)" }}
                  >
                    {ai ? "AI Assistant" : "You (Operator)"}
                  </span>
                  <div
                    className="px-4 py-2.5 rounded-2xl max-w-[75%] text-sm"
                    style={
                      ai
                        ? {
                            background: "var(--surface-1)",
                            border: "1px solid var(--border)",
                            color: "var(--text-secondary)",
                            borderRadius: "16px 16px 16px 4px",
                          }
                        : {
                            background: "var(--brand)",
                            color: "#fff",
                            boxShadow: "0 2px 12px rgba(59,130,246,0.25)",
                            borderRadius: "16px 16px 4px 16px",
                          }
                    }
                  >
                    {/* Strip "AI:" prefix if present */}
                    {ai && typeof m.text === "string" && m.text.startsWith("AI:")
                      ? m.text.slice(3).trim()
                      : (m.text as string)}
                  </div>
                  <span className="text-xs mt-1 mx-1" style={{ color: "var(--text-muted)" }}>
                    {formatTime(m.sentAt as string)}
                  </span>
                </div>
              );
            })}

            <div ref={chatBottomRef} />
          </div>

          {/* Input bar */}
          <div
            className="px-6 py-4"
            style={{ borderTop: "1px solid var(--border)", background: "var(--surface-1)" }}
          >
            <form onSubmit={handleSend} className="flex gap-3 items-center">
              <input
                type="text"
                value={msgText}
                onChange={(e) => setMsgText(e.target.value)}
                placeholder="Type a message to display as sign language…"
                className="flex-1 rounded-2xl px-5 py-3 text-sm outline-none transition-all"
                style={{
                  background: "rgba(255,255,255,0.04)",
                  border: "1px solid var(--border-bright)",
                  color: "var(--text-primary)",
                }}
                onFocus={(e) => {
                  e.currentTarget.style.borderColor = "var(--brand)";
                  e.currentTarget.style.boxShadow = "0 0 0 3px var(--brand-dim)";
                }}
                onBlur={(e) => {
                  e.currentTarget.style.borderColor = "var(--border-bright)";
                  e.currentTarget.style.boxShadow = "none";
                }}
              />
              <button
                type="submit"
                disabled={sending || !msgText.trim()}
                className="w-11 h-11 rounded-2xl flex items-center justify-center transition-all shrink-0"
                style={{
                  background: sending || !msgText.trim() ? "rgba(59,130,246,0.3)" : "var(--brand)",
                  color: "#fff",
                  cursor: sending || !msgText.trim() ? "not-allowed" : "pointer",
                  boxShadow: sending || !msgText.trim() ? "none" : "0 4px 16px rgba(59,130,246,0.35)",
                }}
              >
                <Send size={16} style={{ marginLeft: 2 }} />
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ── Sub-components ─────────────────────────────────── */
function SectionHeader({ icon, label }: { icon: React.ReactNode; label: string }) {
  return (
    <div className="flex items-center gap-1.5">
      <span style={{ color: "var(--text-muted)" }}>{icon}</span>
      <span className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--text-muted)" }}>
        {label}
      </span>
    </div>
  );
}

function InfoRow({ icon, value }: { icon: React.ReactNode; value: string }) {
  return (
    <div className="flex items-start gap-2">
      <span className="mt-0.5 shrink-0" style={{ color: "var(--text-muted)" }}>{icon}</span>
      <span className="text-xs leading-relaxed" style={{ color: "var(--text-secondary)" }}>{value}</span>
    </div>
  );
}

function Divider() {
  return <div className="mx-5" style={{ height: 1, background: "var(--border)" }} />;
}

function SignPill({ sign, critical }: { sign: string; critical: boolean }) {
  return (
    <span
      className="px-2.5 py-1 rounded-lg text-xs font-semibold uppercase animate-scale-in"
      style={
        critical
          ? {
              background: "rgba(239,68,68,0.1)",
              border: "1px solid rgba(239,68,68,0.25)",
              color: "#ef4444",
            }
          : {
              background: "rgba(59,130,246,0.08)",
              border: "1px solid rgba(59,130,246,0.18)",
              color: "var(--brand)",
            }
      }
    >
      {sign}
    </span>
  );
}

function DispatchButton({
  label,
  dispatched,
  color,
  dimColor,
  onClick,
}: {
  label: string;
  dispatched: boolean;
  color: string;
  dimColor: string;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      disabled={dispatched}
      className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-bold transition-all"
      style={{
        background: dimColor,
        border: `1px solid ${dispatched ? color : "transparent"}`,
        color: dispatched ? color : "var(--text-secondary)",
        cursor: dispatched ? "default" : "pointer",
        opacity: dispatched ? 0.7 : 1,
      }}
    >
      <Siren size={12} />
      {dispatched ? `${label} ✓` : label}
    </button>
  );
}

function FullPageLoader() {
  return (
    <div className="min-h-screen flex items-center justify-center" style={{ background: "var(--bg)" }}>
      <div
        className="w-10 h-10 rounded-full border-2 border-t-transparent animate-spin"
        style={{ borderColor: "rgba(59,130,246,0.3)", borderTopColor: "var(--brand)" }}
      />
    </div>
  );
}

function FullPageError({ onBack }: { onBack: () => void }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4" style={{ background: "var(--bg)" }}>
      <p className="text-sm" style={{ color: "var(--critical)" }}>
        Call not found or access denied
      </p>
      <button
        onClick={onBack}
        className="px-4 py-2 rounded-xl text-sm font-medium"
        style={{ background: "var(--brand-dim)", color: "var(--brand)", border: "1px solid rgba(59,130,246,0.25)" }}
      >
        Back to Dashboard
      </button>
    </div>
  );
}
