"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";
import {
  LayoutDashboard,
  HandMetal,
  LogOut,
  Radio,
  ShieldAlert,
} from "lucide-react";
import clsx from "clsx";

const NAV = [
  { href: "/dashboard", icon: LayoutDashboard, label: "Dashboard" },
  { href: "/practice",  icon: HandMetal,        label: "Sign Practice" },
];

export function Sidebar() {
  const pathname = usePathname();
  const router   = useRouter();
  const { token, setToken } = useAuth();

  // Don't render on login page or if not authed
  if (!token || pathname === "/login") return null;

  const handleLogout = () => {
    setToken(null);
    router.push("/login");
  };

  return (
    <aside
      className="fixed left-0 top-0 h-screen w-56 flex flex-col z-30"
      style={{
        background: "var(--surface-1)",
        borderRight: "1px solid var(--border)",
      }}
    >
      {/* Logo */}
      <div
        className="flex items-center gap-3 px-5 py-5"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <div
          className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0"
          style={{ background: "var(--brand-dim)", border: "1px solid rgba(59,130,246,0.3)" }}
        >
          <ShieldAlert size={15} style={{ color: "var(--brand)" }} />
        </div>
        <div>
          <p className="text-sm font-bold leading-tight" style={{ color: "var(--text-primary)" }}>
            SignBridge
          </p>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>
            Operator Portal
          </p>
        </div>
      </div>

      {/* Live badge */}
      <div className="px-5 py-3">
        <span
          className="flex items-center gap-2 text-xs font-medium px-3 py-1.5 rounded-lg w-full"
          style={{ background: "rgba(34,197,94,0.08)", color: "var(--success)", border: "1px solid rgba(34,197,94,0.15)" }}
        >
          <span className="relative inline-flex w-1.5 h-1.5 rounded-full ping-dot" style={{ background: "var(--success)" }} />
          System Live
        </span>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-2 flex flex-col gap-1">
        {NAV.map(({ href, icon: Icon, label }) => {
          const active = pathname === href || pathname.startsWith(href + "/");
          return (
            <Link
              key={href}
              href={href}
              className={clsx(
                "flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all",
              )}
              style={{
                background: active ? "rgba(59,130,246,0.12)" : "transparent",
                color: active ? "var(--brand)" : "var(--text-secondary)",
                border: active ? "1px solid rgba(59,130,246,0.2)" : "1px solid transparent",
              }}
            >
              <Icon size={16} />
              {label}
              {active && (
                <span
                  className="ml-auto w-1 h-4 rounded-full"
                  style={{ background: "var(--brand)" }}
                />
              )}
            </Link>
          );
        })}
      </nav>

      {/* Radio / online status */}
      <div className="px-4 pb-3">
        <div
          className="flex items-center gap-2 px-3 py-2.5 rounded-xl text-xs"
          style={{ background: "rgba(255,255,255,0.03)", border: "1px solid var(--border)" }}
        >
          <Radio size={13} style={{ color: "var(--text-muted)" }} />
          <span style={{ color: "var(--text-muted)" }}>Dispatch radio</span>
          <span
            className="ml-auto text-xs font-bold"
            style={{ color: "var(--success)" }}
          >
            ON
          </span>
        </div>
      </div>

      {/* Logout */}
      <div className="px-3 pb-5" style={{ borderTop: "1px solid var(--border)", paddingTop: 12 }}>
        <button
          onClick={handleLogout}
          className="flex items-center gap-3 w-full px-3 py-2.5 rounded-xl text-sm font-medium transition-all"
          style={{ color: "var(--text-muted)", background: "transparent", border: "1px solid transparent" }}
          onMouseOver={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = "rgba(239,68,68,0.08)";
            (e.currentTarget as HTMLButtonElement).style.color = "var(--critical)";
          }}
          onMouseOut={(e) => {
            (e.currentTarget as HTMLButtonElement).style.background = "transparent";
            (e.currentTarget as HTMLButtonElement).style.color = "var(--text-muted)";
          }}
        >
          <LogOut size={15} />
          Sign out
        </button>
      </div>
    </aside>
  );
}
