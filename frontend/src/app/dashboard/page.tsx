"use client";

import { useEffect, useState } from "react";
import { gql } from "@apollo/client";
import { useQuery, useMutation } from "@apollo/client/react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import {
  PhoneCall,
  AlertTriangle,
  Clock,
  MapPin,
  Eye,
  Activity,
  Radio,
  CheckCircle2,
  TrendingUp,
  Zap,
  User,
  RefreshCw,
} from "lucide-react";
import clsx from "clsx";

/* ── GraphQL ──────────────────────────────────────────────── */
const OPERATOR_CALLS = gql`
  query GetOperatorCalls {
    operatorCalls(includeEnded: false) {
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
  }
`;

const ACCEPT_CALL = gql`
  mutation AcceptCall($callId: ID!) {
    acceptCall(callId: $callId) {
      id
      status
      hasOperator
    }
  }
`;

/* ── Helpers ──────────────────────────────────────────────── */
function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}
function formatElapsed(iso: string) {
  const secs = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (secs < 60) return `${secs}s ago`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  return `${Math.floor(secs / 3600)}h ago`;
}
function urgencyLabel(score: number) {
  if (score >= 0.75) return { text: "CRITICAL", color: "var(--critical)", bg: "var(--critical-dim)", border: "rgba(239,68,68,0.3)" };
  if (score >= 0.5)  return { text: "ELEVATED", color: "var(--warning)",  bg: "rgba(245,158,11,0.1)", border: "rgba(245,158,11,0.25)" };
  return               { text: "MONITORED", color: "var(--brand)",    bg: "var(--brand-dim)",    border: "rgba(59,130,246,0.2)" };
}
function emergencyTypeColor(type: string) {
  const t = (type || "").toUpperCase();
  if (t.includes("FIRE"))   return "#f97316";
  if (t.includes("MEDICAL") || t.includes("AMBULANCE")) return "#a855f7";
  if (t.includes("POLICE") || t.includes("CRIME"))      return "#3b82f6";
  return "var(--text-secondary)";
}

/* ── Page ─────────────────────────────────────────────────── */
export default function DashboardPage() {
  const router = useRouter();
  const { token } = useAuth();
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    if (token === null) router.push("/login");
  }, [token, router]);

  // Tick every 10s to refresh elapsed times
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 10_000);
    return () => clearInterval(id);
  }, []);

  const { data, loading, error, refetch } = useQuery<any>(OPERATOR_CALLS, {
    pollInterval: 2500,
    skip: !token,
  });

  const [acceptCall, { loading: accepting }] = useMutation(ACCEPT_CALL, {
    onCompleted: (d: any) => router.push(`/call/${d.acceptCall.id}`),
  });

  if (token === null) return null;

  const calls: Record<string, any>[] = data?.operatorCalls ?? [];
  const critical   = calls.filter((c) => c.peakUrgencyScore >= 0.75);
  const elevated   = calls.filter((c) => c.peakUrgencyScore >= 0.5 && c.peakUrgencyScore < 0.75);
  const unhandled  = calls.filter((c) => !c.hasOperator && c.peakUrgencyScore >= 0.75).length;
  const aiHandled  = calls.filter((c) => !c.hasOperator && c.peakUrgencyScore < 0.75).length;

  // Sort: unhandled critical first, then by urgency desc
  const sorted = [...calls].sort((a, b) => {
    const aScore = (!a.hasOperator && a.peakUrgencyScore >= 0.75) ? 1 : 0;
    const bScore = (!b.hasOperator && b.peakUrgencyScore >= 0.75) ? 1 : 0;
    if (aScore !== bScore) return bScore - aScore;
    return b.peakUrgencyScore - a.peakUrgencyScore;
  });

  return (
    <div className="min-h-screen" style={{ background: "var(--bg)" }}>
      {/* ── Page header ──────────────────────── */}
      <div
        className="px-8 py-6"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <div className="flex items-start justify-between max-w-5xl mx-auto">
          <div>
            <h1 className="text-xl font-bold mb-0.5" style={{ color: "var(--text-primary)" }}>
              Operations Centre
            </h1>
            <p className="text-sm" style={{ color: "var(--text-muted)" }}>
              {new Date().toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}
              &nbsp;·&nbsp;
              {loading ? "Refreshing…" : `${calls.length} active call${calls.length !== 1 ? "s" : ""}`}
            </p>
          </div>
          <button
            onClick={() => refetch()}
            className="flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-medium transition-all"
            style={{ color: "var(--text-muted)", border: "1px solid var(--border)", background: "transparent" }}
            onMouseOver={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "rgba(255,255,255,0.04)")}
            onMouseOut={(e)  => ((e.currentTarget as HTMLButtonElement).style.background = "transparent")}
          >
            <RefreshCw size={12} className={loading ? "animate-spin" : ""} />
            Refresh
          </button>
        </div>
      </div>

      <main className="px-8 py-7 max-w-5xl mx-auto">

        {/* ── Stats strip ─────────────────────── */}
        <div className="grid grid-cols-4 gap-3 mb-8 animate-fade-up">
          <StatCard icon={<Radio size={14} />}       label="Active Calls"       value={calls.length}   color="var(--brand)"    />
          <StatCard icon={<AlertTriangle size={14} />} label="Critical Unhandled" value={unhandled}    color="var(--critical)" urgent={unhandled > 0} />
          <StatCard icon={<TrendingUp size={14} />}  label="Elevated"           value={elevated.length} color="var(--warning)" />
          <StatCard icon={<Zap size={14} />}         label="AI-Handled"         value={aiHandled}      color="#a855f7" />
        </div>

        {/* ── Alert banner when critical unhandled ── */}
        {unhandled > 0 && (
          <div
            className="flex items-center gap-3 rounded-2xl px-5 py-3.5 mb-6 animate-fade-up border-pulse-red"
            style={{
              background: "var(--critical-dim)",
              border: "1px solid rgba(239,68,68,0.35)",
              color: "var(--critical)",
            }}
          >
            <AlertTriangle size={16} className="shrink-0" />
            <p className="text-sm font-semibold">
              {unhandled} critical call{unhandled > 1 ? "s" : ""} need{unhandled === 1 ? "s" : ""} an operator — accept immediately.
            </p>
          </div>
        )}

        {/* ── Two-column layout: call list + summary ── */}
        <div className="flex gap-6 items-start">

          {/* Call list */}
          <div className="flex-1 min-w-0">
            <p className="section-label mb-3">Live Queue</p>

            {loading && !data ? (
              <SkeletonList />
            ) : error ? (
              <ErrorState message={error.message} onRetry={() => refetch()} />
            ) : sorted.length === 0 ? (
              <EmptyState />
            ) : (
              <div className="flex flex-col gap-2.5">
                {sorted.map((call, idx) => {
                  const ul     = urgencyLabel(call.peakUrgencyScore);
                  const isCrit = call.peakUrgencyScore >= 0.75;
                  const needsOp = !call.hasOperator && isCrit;
                  const callId = call.id as string;

                  return (
                    <div
                      key={callId}
                      className={clsx("rounded-2xl overflow-hidden card-hover animate-fade-up", needsOp && "border-pulse-red")}
                      style={{
                        background: "var(--surface-1)",
                        border: needsOp ? "1px solid rgba(239,68,68,0.35)" : "1px solid var(--border)",
                        animationDelay: `${idx * 50}ms`,
                      }}
                    >
                      {/* Top urgency accent bar */}
                      <div
                        className="h-0.5 w-full"
                        style={{
                          background: isCrit
                            ? "linear-gradient(90deg,#ef4444,transparent)"
                            : call.peakUrgencyScore >= 0.5
                            ? "linear-gradient(90deg,#f59e0b,transparent)"
                            : "linear-gradient(90deg,#3b82f6,transparent)",
                        }}
                      />

                      <div className="px-5 py-4 flex items-center gap-4">
                        {/* Urgency ring */}
                        <div
                          className={clsx(
                            "relative shrink-0 w-14 h-14 rounded-2xl flex flex-col items-center justify-center",
                            needsOp && "pulse-red"
                          )}
                          style={{
                            background: ul.bg,
                            border: `1px solid ${ul.border}`,
                          }}
                        >
                          <span
                            className="text-lg font-black font-mono leading-none"
                            style={{ color: ul.color }}
                          >
                            {Math.round(call.peakUrgencyScore * 100)}
                          </span>
                          <span className="text-[9px] font-semibold mt-0.5" style={{ color: ul.color, opacity: 0.7 }}>
                            %
                          </span>
                        </div>

                        {/* Info block */}
                        <div className="flex-1 min-w-0">
                          {/* Badges row */}
                          <div className="flex items-center gap-1.5 flex-wrap mb-1.5">
                            <span
                              className="tag"
                              style={{ color: ul.color, background: ul.bg, borderColor: ul.border }}
                            >
                              {ul.text}
                            </span>
                            <span
                              className="tag"
                              style={{
                                color: emergencyTypeColor(call.emergencyType),
                                background: "rgba(255,255,255,0.04)",
                                borderColor: "var(--border)",
                              }}
                            >
                              {call.emergencyType || "UNKNOWN"}
                            </span>
                            {call.hasOperator && (
                              <span
                                className="tag"
                                style={{ color: "var(--success)", background: "rgba(34,197,94,0.08)", borderColor: "rgba(34,197,94,0.2)" }}
                              >
                                ✓ Handled
                              </span>
                            )}
                          </div>

                          {/* Name + phone */}
                          <div className="flex items-center gap-2 mb-1">
                            <User size={11} style={{ color: "var(--text-muted)", flexShrink: 0 }} />
                            <span className="font-bold text-sm truncate" style={{ color: "var(--text-primary)" }}>
                              {call.callerName}
                            </span>
                            <span className="text-xs font-mono" style={{ color: "var(--text-muted)" }}>
                              {call.callerPhone}
                            </span>
                          </div>

                          {/* Location + time */}
                          <div className="flex items-center gap-4 text-xs" style={{ color: "var(--text-muted)" }}>
                            <span className="flex items-center gap-1 truncate">
                              <MapPin size={10} />
                              {call.address || "Location pending…"}
                            </span>
                            <span className="flex items-center gap-1 shrink-0">
                              <Clock size={10} />
                              {formatTime(call.startedAt)} · {formatElapsed(call.startedAt)}
                            </span>
                          </div>
                        </div>

                        {/* Action button */}
                        <div className="shrink-0">
                          {call.hasOperator ? (
                            <button
                              onClick={() => router.push(`/call/${callId}`)}
                              className="flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold transition-all"
                              style={{
                                background: "rgba(255,255,255,0.04)",
                                border: "1px solid var(--border-bright)",
                                color: "var(--text-secondary)",
                              }}
                            >
                              <Eye size={13} /> View
                            </button>
                          ) : isCrit ? (
                            <button
                              onClick={() => acceptCall({ variables: { callId } })}
                              disabled={accepting}
                              className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-bold transition-all"
                              style={{
                                background: "var(--critical)",
                                color: "#fff",
                                boxShadow: "0 4px 20px rgba(239,68,68,0.4)",
                                opacity: accepting ? 0.7 : 1,
                              }}
                            >
                              <PhoneCall size={13} />
                              Accept
                            </button>
                          ) : (
                            <button
                              onClick={() => router.push(`/call/${callId}`)}
                              className="flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold transition-all"
                              style={{
                                background: "transparent",
                                border: "1px solid var(--border-bright)",
                                color: "var(--text-secondary)",
                              }}
                            >
                              <Activity size={13} /> Monitor
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Right summary panel */}
          <div className="w-64 shrink-0 flex flex-col gap-4 animate-slide-right">

            {/* Urgency breakdown */}
            <div
              className="rounded-2xl p-5"
              style={{ background: "var(--surface-1)", border: "1px solid var(--border)" }}
            >
              <p className="section-label mb-4">Urgency Breakdown</p>
              {[
                { label: "Critical ≥75%", count: critical.length,             color: "var(--critical)" },
                { label: "Elevated 50–75%", count: elevated.length,           color: "var(--warning)" },
                { label: "Monitored <50%", count: calls.length - critical.length - elevated.length, color: "var(--brand)" },
              ].map(({ label, count, color }) => (
                <div key={label} className="flex items-center justify-between mb-3 last:mb-0">
                  <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full shrink-0" style={{ background: color }} />
                    <span className="text-xs" style={{ color: "var(--text-secondary)" }}>{label}</span>
                  </div>
                  <span className="text-sm font-bold font-mono" style={{ color }}>{count}</span>
                </div>
              ))}
              {calls.length > 0 && (
                <div className="mt-4 h-2 rounded-full overflow-hidden flex" style={{ background: "rgba(255,255,255,0.05)" }}>
                  {critical.length > 0 && (
                    <div className="h-full" style={{ width: `${(critical.length / calls.length) * 100}%`, background: "var(--critical)" }} />
                  )}
                  {elevated.length > 0 && (
                    <div className="h-full" style={{ width: `${(elevated.length / calls.length) * 100}%`, background: "var(--warning)" }} />
                  )}
                </div>
              )}
            </div>

            {/* Recent activity */}
            <div
              className="rounded-2xl p-5"
              style={{ background: "var(--surface-1)", border: "1px solid var(--border)" }}
            >
              <p className="section-label mb-4">Recent Callers</p>
              {calls.length === 0 ? (
                <p className="text-xs text-center py-4" style={{ color: "var(--text-muted)" }}>No active calls</p>
              ) : (
                sorted.slice(0, 4).map((c) => (
                  <div
                    key={c.id}
                    className="flex items-center gap-3 mb-3 last:mb-0 cursor-pointer"
                    onClick={() => router.push(`/call/${c.id}`)}
                  >
                    <div
                      className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0 text-xs font-bold"
                      style={{
                        background: urgencyLabel(c.peakUrgencyScore).bg,
                        color: urgencyLabel(c.peakUrgencyScore).color,
                      }}
                    >
                      {c.callerName?.[0]?.toUpperCase() ?? "?"}
                    </div>
                    <div className="min-w-0">
                      <p className="text-xs font-semibold truncate" style={{ color: "var(--text-primary)" }}>
                        {c.callerName}
                      </p>
                      <p className="text-[10px]" style={{ color: "var(--text-muted)" }}>
                        {Math.round(c.peakUrgencyScore * 100)}% · {formatElapsed(c.startedAt)}
                      </p>
                    </div>
                  </div>
                ))
              )}
            </div>

            {/* Quick guide */}
            <div
              className="rounded-2xl p-5"
              style={{ background: "rgba(59,130,246,0.05)", border: "1px solid rgba(59,130,246,0.15)" }}
            >
              <p className="section-label mb-3" style={{ color: "rgba(59,130,246,0.6)" }}>Quick Guide</p>
              {[
                { icon: <AlertTriangle size={11} />, text: "≥75% — accept immediately", color: "var(--critical)" },
                { icon: <Activity size={11} />,      text: "50–75% — AI handles, monitor", color: "var(--warning)" },
                { icon: <CheckCircle2 size={11} />,  text: "<50% — Gemini auto-replies",  color: "var(--brand)" },
              ].map(({ icon, text, color }, i) => (
                <div key={i} className="flex items-start gap-2 mb-2 last:mb-0">
                  <span className="mt-0.5 shrink-0" style={{ color }}>{icon}</span>
                  <span className="text-xs" style={{ color: "var(--text-secondary)" }}>{text}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

/* ── Sub-components ───────────────────────────────────────── */
function StatCard({
  icon, label, value, color, urgent = false,
}: { icon: React.ReactNode; label: string; value: number; color: string; urgent?: boolean }) {
  return (
    <div
      className={clsx("rounded-2xl px-5 py-4", urgent && "pulse-red")}
      style={{
        background: "var(--surface-1)",
        border: urgent ? "1px solid rgba(239,68,68,0.3)" : "1px solid var(--border)",
      }}
    >
      <div className="flex items-center justify-between mb-2">
        <span className="section-label">{label}</span>
        <span style={{ color }}>{icon}</span>
      </div>
      <p className="text-2xl font-black font-mono" style={{ color }}>
        {value}
      </p>
    </div>
  );
}

function SkeletonList() {
  return (
    <div className="flex flex-col gap-2.5">
      {[0, 1, 2].map((i) => (
        <div key={i} className="skeleton rounded-2xl h-24" style={{ animationDelay: `${i * 80}ms` }} />
      ))}
    </div>
  );
}

function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="rounded-2xl p-10 flex flex-col items-center gap-4" style={{ background: "var(--surface-1)", border: "1px solid var(--border)" }}>
      <p className="text-sm" style={{ color: "var(--critical)" }}>Error: {message}</p>
      <button onClick={onRetry} className="px-4 py-2 rounded-xl text-sm font-medium"
        style={{ background: "var(--brand-dim)", color: "var(--brand)", border: "1px solid rgba(59,130,246,0.25)" }}>
        Retry
      </button>
    </div>
  );
}

function EmptyState() {
  return (
    <div className="rounded-2xl p-16 flex flex-col items-center gap-3"
      style={{ background: "var(--surface-1)", border: "1px dashed var(--border-bright)" }}>
      <div className="w-12 h-12 rounded-2xl flex items-center justify-center"
        style={{ background: "var(--brand-dim)" }}>
        <PhoneCall size={22} style={{ color: "var(--brand)" }} />
      </div>
      <p className="text-sm font-semibold" style={{ color: "var(--text-secondary)" }}>All clear</p>
      <p className="text-xs" style={{ color: "var(--text-muted)" }}>No active emergency calls right now</p>
    </div>
  );
}
