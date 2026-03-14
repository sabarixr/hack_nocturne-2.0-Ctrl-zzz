from __future__ import annotations

from django.conf import settings

GEMINI_MAX_CALLS = 5

# Signs that are meaningful enough to act on
_MEANINGFUL_SIGNS = {
    "help", "pain", "doctor", "emergency", "fire", "choking", "unconscious",
    "bleeding", "danger", "accident", "thief", "call", "hurt", "sick",
}

_SYSTEM_PROMPT = (
    "You are an AI emergency assistant for a deaf or hard-of-hearing person who "
    "is using sign language to communicate during an emergency. "
    "Your job:\n"
    "1. If you have clear signs or a user message to work with, give ONE short, "
    "calm, actionable instruction (max 2 sentences).\n"
    "2. If the signs detected are unclear or absent, ask the user ONE simple "
    "yes/no or short-answer question to understand the situation better "
    "(e.g. 'Are you injured?' or 'Is there someone with you?').\n"
    "Never make up details. Never be verbose. Respond in plain English only."
)


async def get_gemini_suggestion(
    emergency_type: str,
    recognized_signs: list[str],
    urgency_score: float,
    conversation_history: list[dict],
    user_message: str = "",
) -> dict:
    api_key = settings.GEMINI_API_KEY
    if not api_key:
        return _fallback_suggestion(emergency_type, urgency_score)

    try:
        import google.generativeai as genai

        genai.configure(api_key=api_key)
        model = genai.GenerativeModel("gemini-1.5-flash")

        # Decide if signs are meaningful or noisy
        clean_signs = [s.lower() for s in recognized_signs if s.lower() in _MEANINGFUL_SIGNS]
        has_clear_input = bool(clean_signs) or bool(user_message.strip())

        if has_clear_input:
            situation = []
            if clean_signs:
                situation.append(f"Detected signs: {', '.join(clean_signs)}.")
            if user_message.strip():
                situation.append(f"User typed: \"{user_message.strip()}\"")
            situation.append(f"Urgency: {urgency_score:.0%}.")
            context = " ".join(situation)
            prompt = (
                f"{_SYSTEM_PROMPT}\n\n"
                f"Situation: {context}\n"
                "Give a short, actionable response (1-2 sentences max)."
            )
        else:
            # No clear signs — ask a clarifying question
            prompt = (
                f"{_SYSTEM_PROMPT}\n\n"
                "No clear signs detected yet. Ask the user ONE simple question "
                "to understand what kind of help they need. Keep it under 10 words."
            )

        parts = [prompt]
        for msg in conversation_history[-4:]:
            parts.append(f"{msg.get('role','user').upper()}: {msg.get('text','')}")

        response = model.generate_content("\n".join(parts))
        text = response.text.strip()
        # Return as a single clean message — no bullet parsing needed
        return {"primary_suggestion": text, "steps": [], "warnings": []}
    except Exception:
        return _fallback_suggestion(emergency_type, urgency_score)


def _fallback_suggestion(emergency_type: str, urgency_score: float) -> dict:
    suggestions = {
        "MEDICAL": {
            "primary_suggestion": "Call 911 immediately and stay with the person.",
            "steps": [
                "Check if the person is conscious and breathing.",
                "Do not move the person unless in immediate danger.",
                "Keep them calm and comfortable.",
                "Provide their location to the dispatcher.",
            ],
            "warnings": ["Do not give food or water.", "Do not leave them alone."],
        },
        "FIRE": {
            "primary_suggestion": "Evacuate immediately and call 911.",
            "steps": [
                "Alert others in the building.",
                "Use stairs — not elevators.",
                "Close doors behind you to slow fire spread.",
                "Meet at the designated assembly point.",
            ],
            "warnings": ["Do not re-enter the building.", "Stay low to avoid smoke."],
        },
        "POLICE": {
            "primary_suggestion": "Call 911 and describe the situation clearly.",
            "steps": [
                "Find a safe location away from any threat.",
                "Stay on the line with the dispatcher.",
                "Do not confront the threat.",
            ],
            "warnings": ["Do not share your location publicly."],
        },
    }
    default = {
        "primary_suggestion": "Call 911 and describe the emergency.",
        "steps": ["Stay calm.", "Provide your location.", "Follow dispatcher instructions."],
        "warnings": [],
    }
    return suggestions.get(emergency_type.upper(), default)
