"use client";

import { useEffect } from "react";
import { gql } from "@apollo/client";
import { useQuery, useMutation } from "@apollo/client/react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import { PhoneCall, AlertTriangle, Clock, MapPin, Eye, Activity, LogOut, Radio } from "lucide-react";
import clsx from "clsx";

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

function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function urgencyColor(score: number) {
  if (score >= 0.75) return "var(--critical)";
  if (score >= 0.5) return "var(--warning)";
  return "var(--brand)";
}

export default function DashboardPage() {
  const router = useRouter();
  const { token, setToken } = useAuth();

  // Auth guard
  useEffect(() => {
    if (token === null) router.push("/login");
  }, [token, router]);

  const { data, loading, error, refetch } = useQuery<any>(OPERATOR_CALLS, {
    pollInterval: 2000,
    skip: !token,
  });

  const [acceptCall, { loading: accepting }] = useMutation(ACCEPT_CALL, {
    onCompleted: (data: any) => {
      router.push(`/call/${data.acceptCall.id}`);
    },
  });

  if (token === null) return null;

  const calls: Record<string, any>[] = data?.operatorCalls || [];
  const criticalUnhandled = calls.filter(
    (c) => c.peakUrgencyScore >= 0.75 && !c.hasOperator
  ).length;
  const totalActive = calls.length;

  const handleAccept = (callId: string) => acceptCall({ variables: { callId } });
  const handleMonitor = (callId: string) => router.push(`/call/${callId}`);
  const handleLogout = () => {
    setToken(null);
    router.push("/login");
  };

  return (
    <div
      className="min-h-screen flex flex-col"
      style={{ background: "var(--bg)" }}
    >
      {/* ── Top nav ─────────────────────────────── */}
      <header
        className="glass sticky top-0 z-20 flex items-center justify-between px-8 py-4"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <div className="flex items-center gap-3">
          <div
            className="w-8 h-8 rounded-lg flex items-center justify-center"
            style={{ background: "var(--brand-dim)", border: "1px solid rgba(59,130,246,0.25)" }}
          >
            <PhoneCall size={15} style={{ color: "var(--brand)" }} />
          </div>
          <span className="font-bold text-base tracking-tight" style={{ color: "var(--text-primary)" }}>
            SignBridge Ops
          </span>
        </div>

        <div className="flex items-center gap-3">
          {/* Live indicator */}
          <span className="flex items-center gap-1.5 text-xs font-medium" style={{ color: "var(--text-secondary)" }}>
            <span
              className="relative inline-flex w-2 h-2 rounded-full ping-dot"
              style={{ background: "var(--success)" }}
            />
            Live
          </span>

          <button
            onClick={handleLogout}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors"
            style={{ color: "var(--text-secondary)", background: "transparent", border: "1px solid var(--border)" }}
            onMouseOver={(e) => {
              (e.currentTarget as HTMLButtonElement).style.background = "rgba(255,255,255,0.04)";
            }}
            onMouseOut={(e) => {
              (e.currentTarget as HTMLButtonElement).style.background = "transparent";
            }}
          >
            <LogOut size={13} />
            Sign out
          </button>
        </div>
      </header>

      <main className="flex-1 px-8 py-8 max-w-6xl w-full mx-auto">
        {/* ── Stats row ─────────────────────────── */}
        <div className="grid grid-cols-3 gap-4 mb-8 animate-fade-up delay-0">
          <StatCard
            label="Active calls"
            value={loading && !data ? "—" : String(totalActive)}
            icon={<Radio size={16} />}
            color="var(--brand)"
          />
          <StatCard
            label="Critical unhandled"
            value={loading && !data ? "—" : String(criticalUnhandled)}
            icon={<AlertTriangle size={16} />}
            color={criticalUnhandled > 0 ? "var(--critical)" : "var(--success)"}
            urgent={criticalUnhandled > 0}
          />
          <StatCard
            label="AI-handled"
            value={loading && !data ? "—" : String(calls.filter((c) => c.peakUrgencyScore < 0.75).length)}
            icon={<Activity size={16} />}
            color="var(--warning)"
          />
        </div>

        {/* ── Info banner ─────────────────────── */}
        <div
          className="rounded-xl px-5 py-3 mb-6 text-sm animate-fade-up delay-1"
          style={{
            background: "rgba(245,158,11,0.07)",
            border: "1px solid rgba(245,158,11,0.2)",
            color: "#fbbf24",
          }}
        >
          <span className="font-semibold">Note:</span> Calls with urgency below 75% are handled by the Gemini AI.
          Focus on <span className="font-semibold text-red-400">Critical</span> calls first.
        </div>

        {/* ── Call list ─────────────────────── */}
        {loading && !data ? (
          <SkeletonList />
        ) : error ? (
          <div
            className="rounded-2xl p-10 flex flex-col items-center gap-4 animate-fade-up"
            style={{ background: "var(--surface-1)", border: "1px solid var(--border)" }}
          >
            <p className="text-sm" style={{ color: "var(--critical)" }}>
              Error loading calls: {error.message}
            </p>
            <button
              onClick={() => refetch()}
              className="px-4 py-2 rounded-lg text-sm font-medium"
              style={{ background: "var(--brand-dim)", color: "var(--brand)", border: "1px solid rgba(59,130,246,0.25)" }}
            >
              Retry
            </button>
          </div>
        ) : calls.length === 0 ? (
          <div
            className="rounded-2xl p-16 flex flex-col items-center gap-3 animate-fade-up"
            style={{ background: "var(--surface-1)", border: "1px dashed var(--border-bright)" }}
          >
            <PhoneCall size={32} style={{ color: "var(--text-muted)" }} />
            <p className="text-sm" style={{ color: "var(--text-muted)" }}>
              No active emergency calls right now
            </p>
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {calls.map((call, idx) => {
              const isCritical = call.peakUrgencyScore >= 0.75;
              const callId = call.id as string;

              return (
                <div
                  key={callId}
                  className={clsx(
                    "rounded-2xl overflow-hidden transition-all animate-fade-up",
                    isCritical && !call.hasOperator && "border-pulse-red"
                  )}
                  style={{
                    background: "var(--surface-1)",
                    border: isCritical && !call.hasOperator
                      ? "1px solid rgba(239,68,68,0.35)"
                      : "1px solid var(--border)",
                    animationDelay: `${idx * 60}ms`,
                    boxShadow: isCritical && !call.hasOperator
                      ? "0 0 0 0 var(--critical-glow)"
                      : "none",
                  }}
                >
                  {/* Critical top bar */}
                  {isCritical && !call.hasOperator && (
                    <div
                      className="h-0.5 w-full"
                      style={{ background: "linear-gradient(90deg, var(--critical), transparent)" }}
                    />
                  )}

                  <div className="px-6 py-5 flex items-center gap-6">
                    {/* Urgency ring */}
                    <div
                      className={clsx(
                        "relative shrink-0 w-12 h-12 rounded-full flex items-center justify-center text-xs font-bold font-mono",
                        isCritical && !call.hasOperator && "pulse-red"
                      )}
                      style={{
                        background: isCritical ? "var(--critical-dim)" : "var(--brand-dim)",
                        border: `2px solid ${urgencyColor(call.peakUrgencyScore)}`,
                        color: urgencyColor(call.peakUrgencyScore),
                      }}
                    >
                      {Math.round(call.peakUrgencyScore * 100)}
                    </div>

                    {/* Info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1 flex-wrap">
                        {isCritical ? (
                          <span
                            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-bold uppercase tracking-wide"
                            style={{ background: "var(--critical-dim)", color: "var(--critical)" }}
                          >
                            <AlertTriangle size={10} />
                            Critical
                          </span>
                        ) : (
                          <span
                            className="px-2 py-0.5 rounded-md text-xs font-bold uppercase tracking-wide"
                            style={{ background: "rgba(245,158,11,0.1)", color: "var(--warning)" }}
                          >
                            AI Handled
                          </span>
                        )}
                        <span
                          className="text-xs font-semibold uppercase tracking-wider"
                          style={{ color: "var(--text-secondary)" }}
                        >
                          {call.emergencyType}
                        </span>
                        <span
                          className="px-2 py-0.5 rounded-md text-xs"
                          style={{
                            background: "rgba(255,255,255,0.04)",
                            color: "var(--text-secondary)",
                            border: "1px solid var(--border)",
                          }}
                        >
                          {call.status}
                        </span>
                      </div>

                      <h3 className="font-bold text-base truncate" style={{ color: "var(--text-primary)" }}>
                        {call.callerName}
                        <span
                          className="ml-2 font-normal text-sm"
                          style={{ color: "var(--text-secondary)" }}
                        >
                          {call.callerPhone}
                        </span>
                      </h3>

                      <div className="flex items-center gap-5 mt-1 text-xs" style={{ color: "var(--text-muted)" }}>
                        <span className="flex items-center gap-1">
                          <MapPin size={11} />
                          {call.address || "Location unavailable"}
                        </span>
                        <span className="flex items-center gap-1">
                          <Clock size={11} />
                          {formatTime(call.startedAt)}
                        </span>
                      </div>
                    </div>

                    {/* Action */}
                    <div className="shrink-0">
                      {call.hasOperator ? (
                        <div className="flex items-center gap-3">
                          <span
                            className="text-xs font-medium flex items-center gap-1.5"
                            style={{ color: "var(--success)" }}
                          >
                            <span
                              className="w-1.5 h-1.5 rounded-full"
                              style={{ background: "var(--success)" }}
                            />
                            Handled
                          </span>
                          <button
                            onClick={() => handleMonitor(callId)}
                            className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium transition-all"
                            style={{
                              background: "rgba(255,255,255,0.04)",
                              border: "1px solid var(--border-bright)",
                              color: "var(--text-primary)",
                            }}
                          >
                            <Eye size={14} />
                            View
                          </button>
                        </div>
                      ) : isCritical ? (
                        <button
                          onClick={() => handleAccept(callId)}
                          disabled={accepting}
                          className="px-6 py-2.5 rounded-xl text-sm font-bold transition-all"
                          style={{
                            background: accepting ? "rgba(239,68,68,0.5)" : "var(--critical)",
                            color: "#fff",
                            boxShadow: accepting ? "none" : "0 4px 20px rgba(239,68,68,0.4)",
                            cursor: accepting ? "not-allowed" : "pointer",
                          }}
                        >
                          Accept Call
                        </button>
                      ) : (
                        <button
                          onClick={() => handleMonitor(callId)}
                          className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium transition-all"
                          style={{
                            background: "transparent",
                            border: "1px solid var(--border-bright)",
                            color: "var(--text-secondary)",
                          }}
                        >
                          <Eye size={14} />
                          Monitor AI
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

function StatCard({
  label,
  value,
  icon,
  color,
  urgent = false,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  color: string;
  urgent?: boolean;
}) {
  return (
    <div
      className={clsx("rounded-2xl px-6 py-5", urgent && "pulse-red")}
      style={{
        background: "var(--surface-1)",
        border: urgent ? "1px solid rgba(239,68,68,0.3)" : "1px solid var(--border)",
      }}
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-xs font-semibold uppercase tracking-wider" style={{ color: "var(--text-muted)" }}>
          {label}
        </span>
        <span style={{ color }}>{icon}</span>
      </div>
      <p className="text-3xl font-bold font-mono" style={{ color }}>
        {value}
      </p>
    </div>
  );
}

function SkeletonList() {
  return (
    <div className="flex flex-col gap-3">
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className="skeleton rounded-2xl h-24"
          style={{ animationDelay: `${i * 80}ms` }}
        />
      ))}
    </div>
  );
}
