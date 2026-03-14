"use client";

import { useState, useEffect } from "react";
import { gql } from "@apollo/client";
import { useMutation } from "@apollo/client/react";
import { useAuth } from "@/lib/auth-context";
import { useRouter } from "next/navigation";

const LOGIN_MUTATION = gql`
  mutation Login($email: String!, $password: String!) {
    login(input: { email: $email, password: $password }) {
      token
      user {
        id
        email
        name
      }
    }
  }
`;

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [errorMsg, setErrorMsg] = useState("");
  const { setToken, token } = useAuth();
  const router = useRouter();

  // If already authenticated, redirect away
  useEffect(() => {
    if (token) router.push("/dashboard");
  }, [token, router]);

  const [login, { loading }] = useMutation(LOGIN_MUTATION, {
    onCompleted: (data: any) => {
      setToken(data.login.token);
      router.push("/dashboard");
    },
    onError: (error) => {
      setErrorMsg(error.message);
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg("");
    login({ variables: { email, password } });
  };

  return (
    <div className="min-h-screen flex items-center justify-center relative overflow-hidden"
      style={{ background: "var(--bg)" }}>

      {/* Ambient background blobs */}
      <div className="absolute inset-0 pointer-events-none select-none">
        <div
          className="absolute rounded-full opacity-20 blur-3xl"
          style={{
            width: 520,
            height: 520,
            top: "-120px",
            left: "-120px",
            background: "radial-gradient(circle, rgba(59,130,246,0.45) 0%, transparent 70%)",
          }}
        />
        <div
          className="absolute rounded-full opacity-15 blur-3xl"
          style={{
            width: 400,
            height: 400,
            bottom: "-80px",
            right: "-80px",
            background: "radial-gradient(circle, rgba(239,68,68,0.35) 0%, transparent 70%)",
          }}
        />
        {/* Grid overlay */}
        <div
          className="absolute inset-0 opacity-[0.03]"
          style={{
            backgroundImage:
              "linear-gradient(rgba(255,255,255,0.5) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.5) 1px, transparent 1px)",
            backgroundSize: "40px 40px",
          }}
        />
      </div>

      {/* Card */}
      <div
        className="glass-bright rounded-2xl w-full max-w-md mx-4 animate-scale-in"
        style={{ padding: "2.5rem 2.5rem 2rem" }}
      >
        {/* Logo / Brand */}
        <div className="flex flex-col items-center mb-8">
          <div
            className="w-14 h-14 rounded-2xl flex items-center justify-center mb-4 pulse-blue"
            style={{ background: "var(--brand-dim)", border: "1px solid rgba(59,130,246,0.25)" }}
          >
            {/* Hand / wave icon */}
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor"
              strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
              style={{ color: "var(--brand)" }}>
              <path d="M18 11V6a2 2 0 0 0-2-2 2 2 0 0 0-2 2v0" />
              <path d="M14 10V4a2 2 0 0 0-2-2 2 2 0 0 0-2 2v2" />
              <path d="M10 10.5V6a2 2 0 0 0-2-2 2 2 0 0 0-2 2v8" />
              <path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />
            </svg>
          </div>
          <h1 className="text-2xl font-bold tracking-tight" style={{ color: "var(--text-primary)" }}>
            SignBridge
          </h1>
          <p className="text-sm mt-1" style={{ color: "var(--text-secondary)" }}>
            Operator Command Centre
          </p>
        </div>

        {/* Error banner */}
        {errorMsg && (
          <div
            className="rounded-xl px-4 py-3 mb-5 text-sm animate-fade-fast flex items-start gap-2"
            style={{ background: "var(--critical-dim)", border: "1px solid rgba(239,68,68,0.3)", color: "#fca5a5" }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
              strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
              className="shrink-0 mt-0.5">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            {errorMsg}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-5">
          {/* Email */}
          <div>
            <label
              className="block text-xs font-semibold uppercase tracking-widest mb-2"
              style={{ color: "var(--text-secondary)" }}
            >
              Email address
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="operator@signbridge.dev"
              className="w-full rounded-xl px-4 py-3 text-sm outline-none transition-all"
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
              required
            />
          </div>

          {/* Password */}
          <div>
            <label
              className="block text-xs font-semibold uppercase tracking-widest mb-2"
              style={{ color: "var(--text-secondary)" }}
            >
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••••"
              className="w-full rounded-xl px-4 py-3 text-sm outline-none transition-all"
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
              required
            />
          </div>

          {/* Submit */}
          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 rounded-xl font-semibold text-sm transition-all mt-2"
            style={{
              background: loading
                ? "rgba(59,130,246,0.5)"
                : "var(--brand)",
              color: "#fff",
              boxShadow: loading ? "none" : "0 4px 20px rgba(59,130,246,0.35)",
              cursor: loading ? "not-allowed" : "pointer",
            }}
            onMouseOver={(e) => {
              if (!loading) (e.currentTarget as HTMLButtonElement).style.background = "#2563eb";
            }}
            onMouseOut={(e) => {
              if (!loading) (e.currentTarget as HTMLButtonElement).style.background = "var(--brand)";
            }}
          >
            {loading ? (
              <span className="flex items-center justify-center gap-2">
                <span className="w-4 h-4 rounded-full border-2 border-white/30 border-t-white animate-spin inline-block" />
                Authenticating…
              </span>
            ) : (
              "Sign in to Dashboard"
            )}
          </button>
        </form>

        <p className="text-center text-xs mt-6" style={{ color: "var(--text-muted)" }}>
          Access restricted to authorised operators only
        </p>
      </div>
    </div>
  );
}
