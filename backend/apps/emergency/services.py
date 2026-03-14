from __future__ import annotations

import collections
from typing import Any

# ---------------------------------------------------------------------------
# Sign vocabulary
# ---------------------------------------------------------------------------

# High-urgency single signs — each alone gives a meaningful score boost
HIGH_URGENCY_SIGNS = {"help", "emergency", "pain", "fire", "choking", "unconscious", "bleeding", "danger"}

# Medium-urgency signs — concerning but need context
MEDIUM_URGENCY_SIGNS = {"doctor", "accident", "thief", "call", "hurt", "sick", "lose"}

# Dangerous combos: if ANY two of these appear in the recent window → high boost
DANGER_COMBOS = [
    {"help", "doctor"},
    {"help", "pain"},
    {"help", "accident"},
    {"call", "doctor"},
    {"call", "help"},
    {"doctor", "pain"},
    {"thief", "help"},
    {"accident", "call"},
]

# Repeated urgency: if the same high-urgency sign appears N times in window
REPEAT_THRESHOLD = 3        # 3+ repeats of the same critical sign
REPEAT_BOOST = 0.35         # bonus added when repeat threshold hit

# Sequence window: how many recent frames of signs to consider
SEQUENCE_WINDOW = 15        # last N sign-frames kept per call

# ---------------------------------------------------------------------------
# Emotion urgency weights
# ---------------------------------------------------------------------------

EMOTION_WEIGHTS = {
    "emotion_afraid":   0.32,
    "emotion_angry":    0.18,
    "emotion_sad":      0.12,
    "emotion_disgust":  0.10,
    "emotion_surprise": 0.08,
}

# ---------------------------------------------------------------------------
# Per-call sign history (sliding window)
# ---------------------------------------------------------------------------

_sign_history: dict[str, collections.deque] = {}


def _sign_deque(call_id: str) -> collections.deque:
    if call_id not in _sign_history:
        _sign_history[call_id] = collections.deque(maxlen=SEQUENCE_WINDOW)
    return _sign_history[call_id]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def compute_urgency_score(
    recognized_signs: list[str],
    emotion_angry: float,
    emotion_sad: float,
    emotion_neutral: float,
    emotion_happy: float,
    emotion_surprise: float,
    emotion_afraid: float,
    emotion_disgust: float,
    signing_speed: float,
    tremor_level: float,
    call_id: str = "",
) -> float:
    """
    Sequence-aware urgency score in [0, 1].

    Scoring layers (additive, clamped to 1.0):
      1. Emotion component  — weighted sum of distress emotions
      2. Single-sign boost  — immediate bonus for high/medium urgency signs
      3. Combo boost        — two dangerous signs co-occurring in window
      4. Repeat boost       — same critical sign signed 3+ times in window
      5. Motion component   — elevated signing speed / tremor
    """
    # ── 1. Emotion component ─────────────────────────────────────────────────
    emotion_score = (
        emotion_afraid   * EMOTION_WEIGHTS["emotion_afraid"]
        + emotion_angry  * EMOTION_WEIGHTS["emotion_angry"]
        + emotion_sad    * EMOTION_WEIGHTS["emotion_sad"]
        + emotion_disgust * EMOTION_WEIGHTS["emotion_disgust"]
        + emotion_surprise * EMOTION_WEIGHTS["emotion_surprise"]
    )  # max ~0.80 if all maxed

    # ── 2. Single-sign boost ─────────────────────────────────────────────────
    sign_lower = {s.lower() for s in recognized_signs}
    single_boost = 0.0
    if sign_lower & HIGH_URGENCY_SIGNS:
        single_boost = 0.30
    elif sign_lower & MEDIUM_URGENCY_SIGNS:
        single_boost = 0.12

    # ── 3. Sequence / combo analysis ─────────────────────────────────────────
    dq = _sign_deque(call_id) if call_id else collections.deque(maxlen=SEQUENCE_WINDOW)
    if recognized_signs:
        dq.extend(recognized_signs)

    window_signs = {s.lower() for s in dq}

    combo_boost = 0.0
    for combo in DANGER_COMBOS:
        if combo.issubset(window_signs):
            combo_boost = 0.35
            break  # one combo is enough

    # ── 4. Repeat boost ──────────────────────────────────────────────────────
    repeat_boost = 0.0
    if dq:
        counts: dict[str, int] = {}
        for s in dq:
            sl = s.lower()
            counts[sl] = counts.get(sl, 0) + 1
        for sign, count in counts.items():
            if sign in HIGH_URGENCY_SIGNS and count >= REPEAT_THRESHOLD:
                repeat_boost = REPEAT_BOOST
                break

    # ── 5. Motion component ──────────────────────────────────────────────────
    motion_score = (
        min(signing_speed / 3.0, 1.0) * 0.08
        + tremor_level * 0.10
    )

    # ── Combine ───────────────────────────────────────────────────────────────
    # Emotion is a continuous baseline; boosts are discrete jumps
    total = emotion_score + single_boost + combo_boost + repeat_boost + motion_score
    return round(min(total, 1.0), 4)


def force_urgency(call_id: str) -> None:
    """Mark a call as manually triggered (SOS). Clears sign history."""
    if call_id in _sign_history:
        del _sign_history[call_id]
