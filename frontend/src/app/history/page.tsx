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
  Radio,
  TrendingUp,
  Zap,
  Activity,
  CheckCircle2,
  RefreshCw,
} from "lucide-react";
import clsx from "clsx";

/* ── GraphQL ──────────────────────────────────────────── */
const ENDED_CALLS = gql`
  query GetEndedCalls {
    operatorCalls(includeEnded: true) {
      id
      status
      emergencyType
      latitude
      longitude
      address
      peakUrgencyScore
      startedAt
      endedAt
      outcome
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

/* ── Helpers ──────────────────────────────────────────── */
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

/* ── Page ─────────────────────────────────────────────── */
export default function HistoryPage() {
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

  const { data, loading, error, refetch } = useQuery<any>(ENDED_CALLS, {
    pollInterval: 5000, // less frequent for history
    skip: !token,
  });

  if (token === null) return null;

  const calls: Record<string, any>[] = data?.operatorCalls ?? [];
  // Filter to only ended calls (status ENDED)
  const endedCalls = calls.filter(call => call.status === "ENDED");

  // Sort by endedAt descending (most recent first)
  const sorted = [...endedCalls].sort((a, b) => {
    const aTime = a.endedAt ? new Date(a.endedAt).getTime() : 0;
    const bTime = b.endedAt ? new Date(b.endedAt).getTime() : 0;
    return bTime - aTime;
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
              Call History
            </h1>
            <p className="text-sm" style={{ color: "var(--text-muted)" }}>
              {new Date().toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}
              &nbsp;·&nbsp;
              {loading ? "Refreshing…" : `${endedCalls.length} ended call${endedCalls.length !== 1 ? "s" : ""}`}
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
          <StatCard icon={<Radio size={14} />} label="Total Ended" value={endedCalls.length} color="var(--brand)" />
          <StatCard icon={<AlertTriangle size={14} />} label="Critical" value={endedCalls.filter(c => c.peakUrgencyScore >= 0.75).length} color="var(--critical)" />
          <StatCard icon={<TrendingUp size={14} />} label="Elevated" value={endedCalls.filter(c => c.peakUrgencyScore >= 0.5 && c.peakUrgencyScore < 0.75).length} color="var(--warning)" />
          <StatCard icon={<Zap size={14} />} label="Monitored" value={endedCalls.filter(c => c.peakUrgencyScore < 0.5).length} color="#a855f7" />
        </div>

        {/* ── Call list ── */}
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
              const callId = call.id as string;
              const endedAt = call.endedAt ? new Date(call.endedAt).toLocaleString() : "Unknown";

              return (
                <div
                  key={callId}
                  className={clsx("rounded-2xl overflow-hidden card-hover animate-fade-up")}
                  style={{
                    background: "var(--surface-1)",
                    border: "1px solid var(--border)",
                    animationDelay: `${idx * 50}ms`,
                  }}
                >
                  {/* Top urgency accent bar */}
                  <div
                    className="h-0.5 w-full"
                    style={{
                      background: call.peakUrgencyScore >= 0.75
                        ? "linear-gradient(90deg,#ef4444,transparent)"
                        : call.peakUrgencyScore >= 0.5
                        ? "linear-gradient(90deg,#f59e0b,transparent)"
                        : "linear-gradient(90deg,#3b82f6,transparent)",
                    }}
                  />

                  <div className="px-5 py-4 flex items-center gap-4">
                    {/* Urgency ring */}
                    <div
                      className={clsx("relative shrink-0 w-14 h-14 rounded-2xl flex flex-col items-center justify-center")}
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
                          Started: {formatTime(call.startedAt)} · Ended: {endedAt}
                        </span>
                      </div>

                      {/* Outcome */}
                      {call.outcome && (
                        <div className="mt-2 p-3 rounded-xl" style={{ background: "rgba(255,255,255,0.03)", border: "1px solid var(--border)" }}>
                          <p className="text-sm font-medium" style={{ color: "var(--text-primary)" }}>Outcome:</p>
                          <p className="text-sm" style={{ color: "var(--text-muted)" }}>{call.outcome}</p>
                        </div>
                      )}
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
                          <Activity size={13} /> View
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}

      </main>
    </div>
  );
}

/* ── Sub-components ───────────────────────────────────── */
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
      <p className="text-sm font-semibold" style={{ color: "var(--text-secondary)" }}>No history</p>
      <p className="text-xs" style={{ color: "var(--text-muted)" }}>No ended calls yet</p>
    </div>
  );
}