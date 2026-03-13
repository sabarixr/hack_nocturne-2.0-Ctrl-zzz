from __future__ import annotations

import datetime

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.bystander.models import AiSuggestion, BystanderMessage, BystanderSession
from apps.bystander.services import GEMINI_MAX_CALLS, get_gemini_suggestion
from shared.auth import IsAuthenticated
from shared.redis_layer import bystander_group, channel_group_send


@strawberry_django.type(BystanderSession)
class BystanderSessionType:
    id: strawberry.ID
    call_id: strawberry.ID
    started_at: datetime.datetime
    ended_at: datetime.datetime | None
    gemini_call_count: int


@strawberry_django.type(BystanderMessage)
class BystanderMessageType:
    id: strawberry.ID
    session_id: strawberry.ID
    sender: str
    text: str
    sent_at: datetime.datetime


@strawberry_django.type(AiSuggestion)
class AiSuggestionType:
    id: strawberry.ID
    session_id: strawberry.ID
    primary_suggestion: str
    steps: strawberry.scalars.JSON
    warnings: strawberry.scalars.JSON
    generated_at: datetime.datetime


@strawberry.input
class StartBystanderInput:
    call_id: strawberry.ID


@strawberry.input
class SendBystanderMessageInput:
    session_id: strawberry.ID
    text: str


@strawberry.type
class BystanderQuery:
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def bystander_session(
        self, info: Info, call_id: strawberry.ID
    ) -> BystanderSessionType | None:
        try:
            return await BystanderSession.objects.aget(call_id=call_id)  # type: ignore[return-value]
        except BystanderSession.DoesNotExist:
            return None

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def bystander_messages(
        self, info: Info, session_id: strawberry.ID
    ) -> list[BystanderMessageType]:
        return [
            m async for m in BystanderMessage.objects.filter(session_id=session_id)
        ]  # type: ignore[return-value]

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def ai_suggestions(
        self, info: Info, session_id: strawberry.ID
    ) -> list[AiSuggestionType]:
        return [
            s async for s in AiSuggestion.objects.filter(session_id=session_id)
        ]  # type: ignore[return-value]


@strawberry.type
class BystanderMutation:
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def start_bystander_session(
        self, info: Info, input: StartBystanderInput
    ) -> BystanderSessionType:
        session, _ = await BystanderSession.objects.aupdate_or_create(
            call_id=input.call_id,
            defaults={"ended_at": None},
        )
        return session  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def send_bystander_message(
        self, info: Info, input: SendBystanderMessageInput
    ) -> BystanderMessageType:
        session = await BystanderSession.objects.aget(id=input.session_id)
        msg = await BystanderMessage.objects.acreate(
            session=session,
            sender="BYSTANDER",
            text=input.text,
        )
        await channel_group_send(
            bystander_group(str(session.id)),
            {
                "type": "bystander.message",
                "session_id": str(session.id),
                "sender": "BYSTANDER",
                "text": input.text,
                "sent_at": msg.sent_at.isoformat(),
            },
        )
        return msg  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def request_ai_suggestion(
        self, info: Info, session_id: strawberry.ID
    ) -> AiSuggestionType:
        session = await BystanderSession.objects.select_related("call").aget(id=session_id)

        if session.gemini_call_count >= GEMINI_MAX_CALLS:
            existing = await AiSuggestion.objects.filter(session=session).afirst()
            if existing:
                return existing  # type: ignore[return-value]

        call = session.call
        from apps.emergency.models import EmergencyFrame

        frames_qs = EmergencyFrame.objects.filter(call=call).order_by("-recorded_at")[:5]
        recent_frames = [f async for f in frames_qs]

        all_signs: list[str] = []
        latest_urgency = 0.0
        for frame in recent_frames:
            all_signs.extend(frame.recognized_signs)
            latest_urgency = max(latest_urgency, frame.urgency_score)

        history_qs = BystanderMessage.objects.filter(session=session).order_by("-sent_at")[:6]
        history = [
            {"role": "user" if m.sender == "BYSTANDER" else "model", "text": m.text}
            async for m in history_qs
        ]

        result = await get_gemini_suggestion(
            emergency_type=call.emergency_type,
            recognized_signs=list(set(all_signs)),
            urgency_score=latest_urgency,
            conversation_history=history,
        )

        session.gemini_call_count += 1
        await session.asave(update_fields=["gemini_call_count"])

        suggestion = await AiSuggestion.objects.acreate(
            session=session,
            primary_suggestion=result["primary_suggestion"],
            steps=result["steps"],
            warnings=result["warnings"],
            raw_context_snapshot={
                "emergency_type": call.emergency_type,
                "recognized_signs": list(set(all_signs)),
                "urgency_score": latest_urgency,
            },
        )

        await channel_group_send(
            bystander_group(str(session.id)),
            {
                "type": "bystander.message",
                "session_id": str(session.id),
                "sender": "AI",
                "text": result["primary_suggestion"],
                "sent_at": suggestion.generated_at.isoformat(),
            },
        )

        return suggestion  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def end_bystander_session(
        self, info: Info, session_id: strawberry.ID
    ) -> BystanderSessionType:
        session = await BystanderSession.objects.aget(id=session_id)
        session.ended_at = datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)
        await session.asave(update_fields=["ended_at"])
        return session  # type: ignore[return-value]
