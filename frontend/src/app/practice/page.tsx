"use client";

import { useState, useRef } from "react";
import {
  BookOpen,
  Upload,
  CheckCircle,
  AlertTriangle,
  ChevronRight,
  Hand,
  FileVideo,
  X,
} from "lucide-react";

/* ── Sign database (hardcoded) ────────────────────────── */
interface SignInfo {
  id: string;
  label: string;
  category: string;
  difficulty: "BEGINNER" | "INTERMEDIATE" | "ADVANCED";
  critical: boolean;
  description: string;
  gesture: string;
  steps: string[];
}

const SIGNS: SignInfo[] = [
  {
    id: "help",
    label: "HELP",
    category: "Emergency",
    difficulty: "BEGINNER",
    critical: true,
    description: "Open palm raised — universal distress signal",
    gesture: "Extend all 5 fingers, palm facing forward, raise hand",
    steps: [
      "Open your hand fully, spreading all five fingers wide",
      "Face your palm outward (away from you)",
      "Raise your arm to shoulder height or above",
      "Hold the position clearly visible to the camera",
    ],
  },
  {
    id: "pain",
    label: "PAIN",
    category: "Medical",
    difficulty: "BEGINNER",
    critical: true,
    description: "Index and middle fingers together, point to affected area",
    gesture: "Keep index + middle touching, curl ring and pinky",
    steps: [
      "Extend your index and middle fingers together",
      "Curl your ring and pinky fingers into your palm",
      "Tuck your thumb across your palm",
      "Point the two extended fingers toward the area of pain",
    ],
  },
  {
    id: "doctor",
    label: "DOCTOR",
    category: "Medical",
    difficulty: "INTERMEDIATE",
    critical: true,
    description: "D-handshape — index up, thumb touches middle fingertip",
    gesture: "Raise index finger, bring thumb to touch middle fingertip",
    steps: [
      "Extend your index finger straight up",
      "Bring your thumb tip to touch the tip of your middle finger",
      "Keep your ring and pinky fingers loosely curled",
      "Hold the D-shape clearly in frame",
    ],
  },
  {
    id: "call",
    label: "CALL",
    category: "Communication",
    difficulty: "BEGINNER",
    critical: false,
    description: "Shaka / phone hand — pinky and thumb extended",
    gesture: "Extend pinky and thumb, curl index, middle, ring fingers",
    steps: [
      "Extend your thumb outward to the side",
      "Extend your pinky finger upward",
      "Curl your index, middle, and ring fingers into your palm",
      "Hold the shape steady — like a phone against your ear",
    ],
  },
  {
    id: "accident",
    label: "ACCIDENT",
    category: "Emergency",
    difficulty: "INTERMEDIATE",
    critical: false,
    description: "Devil horns — index and pinky extended",
    gesture: "Extend index and pinky, curl middle and ring fingers",
    steps: [
      "Extend your index finger upward",
      "Extend your pinky finger upward",
      "Curl your middle and ring fingers into your palm",
      "Hold your thumb tucked or across the curled fingers",
    ],
  },
  {
    id: "thief",
    label: "THIEF",
    category: "Crime",
    difficulty: "INTERMEDIATE",
    critical: false,
    description: "O-shape — all fingertips close to thumb",
    gesture: "Bring all fingertips to meet thumb tip, form an O",
    steps: [
      "Curve all four fingers inward",
      "Bring all fingertips to touch the tip of your thumb",
      "Form a clear circular 'O' shape with your hand",
      "Hold the O-shape with your hand raised at chest height",
    ],
  },
  {
    id: "hot",
    label: "HOT",
    category: "Environment",
    difficulty: "BEGINNER",
    critical: false,
    description: "Fisted hand — all fingers curled",
    gesture: "Close all fingers into a tight fist",
    steps: [
      "Close all four fingers into your palm",
      "Wrap your thumb over the front of your fingers",
      "Make a tight, firm fist",
      "Raise the fist to chest or shoulder height",
    ],
  },
  {
    id: "lose",
    label: "LOSE",
    category: "General",
    difficulty: "BEGINNER",
    critical: false,
    description: "2+ fingers extended — general distress fallback",
    gesture: "Extend 2 or more fingers loosely outward",
    steps: [
      "Extend two or more fingers (index + middle work best)",
      "Keep them loosely spread or together",
      "Hold your hand at a visible height",
      "A relaxed, open multi-finger pose is detected as LOSE",
    ],
  },
];

/* ── Helpers ──────────────────────────────────────────── */
const DIFFICULTY_COLOR = {
  BEGINNER:     { bg: "rgba(34,197,94,0.12)",  text: "#22c55e" },
  INTERMEDIATE: { bg: "rgba(245,158,11,0.12)", text: "#f59e0b" },
  ADVANCED:     { bg: "rgba(239,68,68,0.12)",  text: "#ef4444" },
};

const CATEGORY_COLOR: Record<string, string> = {
  Emergency:     "#ef4444",
  Medical:       "#a855f7",
  Communication: "#3b82f6",
  Crime:         "#f97316",
  Environment:   "#14b8a6",
  General:       "#6b7280",
};

/* ── Page ─────────────────────────────────────────────── */
export default function PracticePage() {
  const [selected, setSelected] = useState<SignInfo>(SIGNS[0]);
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadDone, setUploadDone] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const diff = DIFFICULTY_COLOR[selected.difficulty];
  const catColor = CATEGORY_COLOR[selected.category] ?? "#6b7280";

  const handleFileChange = (file: File | null) => {
    if (!file) return;
    setUploadFile(file);
    setUploadDone(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file && file.type.startsWith("video/")) handleFileChange(file);
  };

  const handleUpload = async () => {
    if (!uploadFile) return;
    setUploading(true);
    // Placeholder: simulate upload delay, then show success
    await new Promise((r) => setTimeout(r, 1400));
    setUploading(false);
    setUploadDone(true);
  };

  const clearFile = () => {
    setUploadFile(null);
    setUploadDone(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  return (
    <div className="min-h-screen flex flex-col" style={{ background: "var(--bg)" }}>
      {/* ── Top bar ────────────────────── */}
      <header
        className="glass sticky top-0 z-20 flex items-center gap-4 px-6 py-4"
        style={{ borderBottom: "1px solid var(--border)" }}
      >
        <BookOpen size={18} style={{ color: "var(--brand)" }} />
        <div>
          <h1 className="font-bold text-base" style={{ color: "var(--text-primary)" }}>
            Sign Practice Library
          </h1>
          <p className="text-xs" style={{ color: "var(--text-muted)" }}>
            Learn all 8 recognised sign classes · Upload practice videos
          </p>
        </div>
        <div className="ml-auto flex items-center gap-2">
          <span
            className="px-3 py-1 rounded-full text-xs font-semibold"
            style={{ background: "rgba(34,197,94,0.1)", color: "#22c55e", border: "1px solid rgba(34,197,94,0.2)" }}
          >
            {SIGNS.length} Signs
          </span>
          <span
            className="px-3 py-1 rounded-full text-xs font-semibold"
            style={{ background: "rgba(239,68,68,0.1)", color: "#ef4444", border: "1px solid rgba(239,68,68,0.2)" }}
          >
            {SIGNS.filter((s) => s.critical).length} Critical
          </span>
        </div>
      </header>

      {/* ── Two-column layout ──────────── */}
      <div className="flex-1 flex overflow-hidden" style={{ minHeight: 0 }}>
        {/* Left: sign list */}
        <aside
          className="w-72 shrink-0 overflow-y-auto"
          style={{ background: "var(--surface-1)", borderRight: "1px solid var(--border)" }}
        >
          <div className="p-4 space-y-2">
            <p className="section-label px-1 mb-3">All Signs</p>
            {SIGNS.map((sign, i) => {
              const active = selected.id === sign.id;
              const dc = DIFFICULTY_COLOR[sign.difficulty];
              return (
                <button
                  key={sign.id}
                  onClick={() => { setSelected(sign); setUploadFile(null); setUploadDone(false); }}
                  className={`w-full text-left rounded-2xl p-4 transition-all card-hover animate-fade-up`}
                  style={{
                    animationDelay: `${i * 40}ms`,
                    background: active ? "rgba(59,130,246,0.1)" : "var(--surface-2)",
                    border: `1px solid ${active ? "rgba(59,130,246,0.35)" : "var(--border)"}`,
                  }}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <span
                        className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0 text-sm font-black"
                        style={{
                          background: sign.critical ? "rgba(239,68,68,0.1)" : "rgba(59,130,246,0.08)",
                          color: sign.critical ? "#ef4444" : "var(--brand)",
                        }}
                      >
                        {sign.label[0]}
                      </span>
                      <div className="min-w-0">
                        <p
                          className="font-bold text-sm truncate"
                          style={{ color: active ? "var(--text-primary)" : "var(--text-secondary)" }}
                        >
                          {sign.label}
                        </p>
                        <p className="text-xs truncate" style={{ color: "var(--text-muted)" }}>
                          {sign.category}
                        </p>
                      </div>
                    </div>
                    <div className="flex flex-col items-end gap-1 shrink-0">
                      {sign.critical && (
                        <span
                          className="px-1.5 py-0.5 rounded text-xs font-bold uppercase"
                          style={{ background: "rgba(239,68,68,0.1)", color: "#ef4444", fontSize: 9, letterSpacing: "0.06em" }}
                        >
                          CRITICAL
                        </span>
                      )}
                      <span
                        className="px-1.5 py-0.5 rounded text-xs font-semibold"
                        style={{ background: dc.bg, color: dc.text, fontSize: 9 }}
                      >
                        {sign.difficulty}
                      </span>
                    </div>
                  </div>
                  {active && (
                    <ChevronRight
                      size={14}
                      className="absolute right-3 top-1/2 -translate-y-1/2"
                      style={{ color: "var(--brand)" }}
                    />
                  )}
                </button>
              );
            })}
          </div>
        </aside>

        {/* Right: sign detail + upload */}
        <main className="flex-1 overflow-y-auto px-8 py-6 space-y-6">
          {/* Header card */}
          <div
            className="rounded-2xl p-6 animate-fade-in"
            style={{
              background: "var(--surface-1)",
              border: `1px solid ${selected.critical ? "rgba(239,68,68,0.2)" : "var(--border)"}`,
            }}
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-3 mb-2">
                  <h2 className="text-2xl font-black tracking-tight" style={{ color: "var(--text-primary)" }}>
                    {selected.label}
                  </h2>
                  {selected.critical && (
                    <span
                      className="flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-bold"
                      style={{ background: "rgba(239,68,68,0.12)", color: "#ef4444", border: "1px solid rgba(239,68,68,0.25)" }}
                    >
                      <AlertTriangle size={11} />
                      CRITICAL SIGN
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-2 mb-3">
                  <span
                    className="px-2.5 py-1 rounded-lg text-xs font-semibold"
                    style={{ background: `${catColor}18`, color: catColor }}
                  >
                    {selected.category}
                  </span>
                  <span
                    className="px-2.5 py-1 rounded-lg text-xs font-semibold"
                    style={{ background: diff.bg, color: diff.text }}
                  >
                    {selected.difficulty}
                  </span>
                </div>
                <p style={{ color: "var(--text-secondary)", fontSize: 14, lineHeight: 1.6 }}>
                  {selected.description}
                </p>
              </div>

              {/* Large sign avatar */}
              <div
                className="w-20 h-20 rounded-2xl flex items-center justify-center shrink-0 text-3xl font-black"
                style={{
                  background: selected.critical ? "rgba(239,68,68,0.1)" : "rgba(59,130,246,0.08)",
                  border: `1px solid ${selected.critical ? "rgba(239,68,68,0.2)" : "rgba(59,130,246,0.15)"}`,
                  color: selected.critical ? "#ef4444" : "var(--brand)",
                }}
              >
                {selected.label[0]}
              </div>
            </div>
          </div>

          {/* Gesture & key points */}
          <div className="grid grid-cols-2 gap-4 animate-fade-up" style={{ animationDelay: "60ms" }}>
            {/* Hand shape */}
            <div
              className="rounded-2xl p-5"
              style={{ background: "var(--surface-1)", border: "1px solid var(--border)" }}
            >
              <div className="flex items-center gap-2 mb-3">
                <Hand size={14} style={{ color: "var(--brand)" }} />
                <span className="section-label">Hand Shape</span>
              </div>
              <p style={{ color: "var(--text-secondary)", fontSize: 13, lineHeight: 1.6 }}>
                {selected.gesture}
              </p>
            </div>

            {/* Category info */}
            <div
              className="rounded-2xl p-5"
              style={{ background: "var(--surface-1)", border: "1px solid var(--border)" }}
            >
              <div className="flex items-center gap-2 mb-3">
                <span
                  className="w-3 h-3 rounded-full shrink-0"
                  style={{ background: catColor }}
                />
                <span className="section-label">Category</span>
              </div>
              <p
                className="font-bold text-sm"
                style={{ color: catColor }}
              >
                {selected.category}
              </p>
              <p style={{ color: "var(--text-muted)", fontSize: 12, marginTop: 4, lineHeight: 1.5 }}>
                {selected.critical
                  ? "This sign triggers high-urgency alerts in the system"
                  : "This sign is used for context and situational awareness"}
              </p>
            </div>
          </div>

          {/* Step-by-step guide */}
          <div
            className="rounded-2xl p-6 animate-fade-up"
            style={{ animationDelay: "120ms", background: "var(--surface-1)", border: "1px solid var(--border)" }}
          >
            <div className="flex items-center gap-2 mb-4">
              <BookOpen size={14} style={{ color: "var(--brand)" }} />
              <span className="section-label">How to Sign</span>
            </div>
            <ol className="space-y-3">
              {selected.steps.map((step, i) => (
                <li key={i} className="flex items-start gap-3">
                  <span
                    className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold shrink-0 mt-0.5"
                    style={{ background: "rgba(59,130,246,0.15)", color: "var(--brand)" }}
                  >
                    {i + 1}
                  </span>
                  <p style={{ color: "var(--text-secondary)", fontSize: 13, lineHeight: 1.6 }}>
                    {step}
                  </p>
                </li>
              ))}
            </ol>
          </div>

          {/* Upload zone */}
          <div
            className="rounded-2xl p-6 animate-fade-up"
            style={{ animationDelay: "180ms", background: "var(--surface-1)", border: "1px solid var(--border)" }}
          >
            <div className="flex items-center gap-2 mb-4">
              <Upload size={14} style={{ color: "var(--brand)" }} />
              <span className="section-label">Practice Video Upload</span>
            </div>
            <p style={{ color: "var(--text-muted)", fontSize: 12, marginBottom: 16, lineHeight: 1.5 }}>
              Record yourself performing the <strong style={{ color: "var(--text-secondary)" }}>{selected.label}</strong> sign and upload
              for review. Supported formats: MP4, MOV, WebM.
            </p>

            {/* Drop zone */}
            {!uploadFile ? (
              <div
                className={`drop-zone cursor-pointer flex flex-col items-center justify-center py-12 ${dragOver ? "dragging" : ""}`}
                onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
                onDragLeave={() => setDragOver(false)}
                onDrop={handleDrop}
                onClick={() => fileInputRef.current?.click()}
              >
                <FileVideo size={32} style={{ color: "var(--text-muted)", marginBottom: 12 }} />
                <p className="font-semibold text-sm" style={{ color: "var(--text-secondary)" }}>
                  Drop video here or click to browse
                </p>
                <p style={{ color: "var(--text-muted)", fontSize: 12, marginTop: 6 }}>
                  Max 100 MB · MP4, MOV, WebM
                </p>
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="video/*"
                  className="hidden"
                  onChange={(e) => handleFileChange(e.target.files?.[0] ?? null)}
                />
              </div>
            ) : (
              <div
                className="rounded-2xl p-4 flex items-center justify-between"
                style={{
                  background: uploadDone ? "rgba(34,197,94,0.08)" : "rgba(59,130,246,0.08)",
                  border: `1px solid ${uploadDone ? "rgba(34,197,94,0.25)" : "rgba(59,130,246,0.2)"}`,
                }}
              >
                <div className="flex items-center gap-3 min-w-0">
                  {uploadDone ? (
                    <CheckCircle size={20} style={{ color: "#22c55e", flexShrink: 0 }} />
                  ) : (
                    <FileVideo size={20} style={{ color: "var(--brand)", flexShrink: 0 }} />
                  )}
                  <div className="min-w-0">
                    <p
                      className="font-semibold text-sm truncate"
                      style={{ color: "var(--text-primary)" }}
                    >
                      {uploadFile.name}
                    </p>
                    <p style={{ color: "var(--text-muted)", fontSize: 11 }}>
                      {uploadDone ? "Uploaded successfully" : `${(uploadFile.size / 1024 / 1024).toFixed(1)} MB`}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  {!uploadDone && (
                    <button
                      onClick={handleUpload}
                      disabled={uploading}
                      className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-bold transition-all"
                      style={{
                        background: uploading ? "rgba(59,130,246,0.3)" : "var(--brand)",
                        color: "#fff",
                        cursor: uploading ? "not-allowed" : "pointer",
                      }}
                    >
                      {uploading ? (
                        <>
                          <div
                            className="w-3 h-3 rounded-full border border-t-transparent animate-spin"
                            style={{ borderColor: "rgba(255,255,255,0.4)", borderTopColor: "#fff" }}
                          />
                          Uploading…
                        </>
                      ) : (
                        <>
                          <Upload size={13} />
                          Submit
                        </>
                      )}
                    </button>
                  )}
                  <button
                    onClick={clearFile}
                    className="p-2 rounded-xl transition-all"
                    style={{ color: "var(--text-muted)", background: "transparent" }}
                    onMouseOver={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "rgba(255,255,255,0.06)")}
                    onMouseOut={(e) => ((e.currentTarget as HTMLButtonElement).style.background = "transparent")}
                  >
                    <X size={16} />
                  </button>
                </div>
              </div>
            )}

            {uploadDone && (
              <p
                className="mt-3 text-xs text-center animate-fade-in"
                style={{ color: "#22c55e" }}
              >
                Video submitted for the <strong>{selected.label}</strong> sign. Thank you!
              </p>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
