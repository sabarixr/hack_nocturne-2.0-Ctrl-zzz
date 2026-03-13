from __future__ import annotations

from django.conf import settings

GEMINI_MAX_CALLS = 5

_SYSTEM_PROMPT = (
    "You are an emergency response assistant helping a bystander assist a deaf or "
    "hard-of-hearing person in an emergency situation. Provide clear, actionable "
    "first-response guidance. Keep responses concise and calm."
)


async def get_gemini_suggestion(
    emergency_type: str,
    recognized_signs: list[str],
    urgency_score: float,
    conversation_history: list[dict],
) -> dict:
    api_key = settings.GEMINI_API_KEY
    if not api_key:
        return _fallback_suggestion(emergency_type, urgency_score)

    try:
        import google.generativeai as genai

        genai.configure(api_key=api_key)
        model = genai.GenerativeModel("gemini-pro")

        context = (
            f"Emergency type: {emergency_type}. "
            f"Recognized signs: {', '.join(recognized_signs) if recognized_signs else 'unknown'}. "
            f"Urgency score: {urgency_score:.2f}."
        )
        messages = [{"role": "user", "parts": [_SYSTEM_PROMPT + "\n\n" + context]}]
        for msg in conversation_history[-6:]:
            messages.append({"role": msg["role"], "parts": [msg["text"]]})

        response = model.generate_content(messages)
        text = response.text.strip()
        lines = [l.strip() for l in text.split("\n") if l.strip()]
        primary = lines[0] if lines else text
        steps = [l.lstrip("•-0123456789. ") for l in lines[1:] if l]
        return {"primary_suggestion": primary, "steps": steps, "warnings": []}
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
