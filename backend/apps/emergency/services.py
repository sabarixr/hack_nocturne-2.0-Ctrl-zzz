from __future__ import annotations

CRITICAL_SIGNS = {"HELP", "EMERGENCY", "PAIN", "FIRE", "CHOKING", "UNCONSCIOUS", "BLEEDING"}

URGENCY_WEIGHTS = {
    "emotion_fear": 0.25,
    "emotion_pain": 0.30,
    "emotion_panic": 0.20,
    "signing_speed": 0.10,
    "tremor_level": 0.15,
}

CRITICAL_SIGN_BONUS = 0.15


def compute_urgency_score(
    recognized_signs: list[str],
    emotion_fear: float,
    emotion_pain: float,
    emotion_panic: float,
    signing_speed: float,
    tremor_level: float,
) -> float:
    base = (
        emotion_fear * URGENCY_WEIGHTS["emotion_fear"]
        + emotion_pain * URGENCY_WEIGHTS["emotion_pain"]
        + emotion_panic * URGENCY_WEIGHTS["emotion_panic"]
        + min(signing_speed / 3.0, 1.0) * URGENCY_WEIGHTS["signing_speed"]
        + tremor_level * URGENCY_WEIGHTS["tremor_level"]
    )
    has_critical = any(s.upper() in CRITICAL_SIGNS for s in recognized_signs)
    score = base + (CRITICAL_SIGN_BONUS if has_critical else 0.0)
    return round(min(score, 1.0), 4)
