from __future__ import annotations

import datetime
from collections import Counter

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.emergency.models import (
    CallStatus,
    DispatchEvent,
    EmergencyCall,
    EmergencyFrame,
    OperatorMessage,
)
from apps.emergency.services import compute_urgency_score
from shared.auth import IsAuthenticated
from shared.redis_layer import channel_group_send, emergency_group


@strawberry_django.type(EmergencyCall)
class EmergencyCallType:
    id: strawberry.ID
    status: str
    emergency_type: str
    latitude: float | None
    longitude: float | None
    address: str
    peak_urgency_score: float
    outcome: str
    started_at: datetime.datetime
    ended_at: datetime.datetime | None


@strawberry_django.type(EmergencyFrame)
class EmergencyFrameType:
    id: strawberry.ID
    call_id: strawberry.ID
    recognized_signs: strawberry.scalars.JSON
    urgency_score: float
    emotion_fear: float
    emotion_pain: float
    emotion_panic: float
    signing_speed: float
    tremor_level: float
    latitude: float | None
    longitude: float | None
    recorded_at: datetime.datetime


@strawberry_django.type(OperatorMessage)
class OperatorMessageType:
    id: strawberry.ID
    call_id: strawberry.ID
    text: str
    gloss_sequence: strawberry.scalars.JSON
    sent_at: datetime.datetime


@strawberry_django.type(DispatchEvent)
class DispatchEventType:
    id: strawberry.ID
    call_id: strawberry.ID
    dispatch_type: str
    eta_seconds: int | None
    dispatched_at: datetime.datetime


@strawberry.input
class StartCallInput:
    emergency_type: str = "UNKNOWN"
    latitude: float | None = None
    longitude: float | None = None
    address: str = ""


@strawberry.input
class SubmitFrameInput:
    call_id: strawberry.ID
    recognized_signs: list[str]
    emotion_fear: float = 0.0
    emotion_pain: float = 0.0
    emotion_panic: float = 0.0
    signing_speed: float = 1.0
    tremor_level: float = 0.0
    latitude: float | None = None
    longitude: float | None = None


@strawberry.input
class EndCallInput:
    call_id: strawberry.ID
    outcome: str = ""


@strawberry.input
class PostCallReportInput:
    call_id: strawberry.ID
    outcome: str


@strawberry.type
class EmergencyMutation:
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def start_call(self, info: Info, input: StartCallInput) -> EmergencyCallType:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.acreate(
            user_id=user_id,
            status=CallStatus.CONNECTING,
            emergency_type=input.emergency_type,
            latitude=input.latitude,
            longitude=input.longitude,
            address=input.address,
        )
        return call  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def activate_call(self, info: Info, call_id: strawberry.ID) -> EmergencyCallType:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=call_id, user_id=user_id)
        call.status = CallStatus.ACTIVE
        await call.asave(update_fields=["status"])
        return call  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def submit_frame(self, info: Info, input: SubmitFrameInput) -> EmergencyFrameType:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=input.call_id, user_id=user_id)

        urgency_score = compute_urgency_score(
            recognized_signs=input.recognized_signs,
            emotion_fear=input.emotion_fear,
            emotion_pain=input.emotion_pain,
            emotion_panic=input.emotion_panic,
            signing_speed=input.signing_speed,
            tremor_level=input.tremor_level,
        )

        frame = await EmergencyFrame.objects.acreate(
            call=call,
            recognized_signs=input.recognized_signs,
            urgency_score=urgency_score,
            emotion_fear=input.emotion_fear,
            emotion_pain=input.emotion_pain,
            emotion_panic=input.emotion_panic,
            signing_speed=input.signing_speed,
            tremor_level=input.tremor_level,
            latitude=input.latitude,
            longitude=input.longitude,
        )

        if urgency_score > call.peak_urgency_score:
            call.peak_urgency_score = urgency_score
            newly_triggered = (
                urgency_score >= 0.75
                and call.status == CallStatus.ACTIVE
            )
            if newly_triggered:
                call.status = CallStatus.EMERGENCY_TRIGGERED
            await call.asave(update_fields=["peak_urgency_score", "status"])

            if newly_triggered and call.operator_id is None:
                await _gemini_auto_reply(call, input.recognized_signs, urgency_score)

        await channel_group_send(
            emergency_group(str(call.id)),
            {
                "type": "call.update",
                "call_id": str(call.id),
                "status": call.status,
                "peak_urgency_score": call.peak_urgency_score,
                "emergency_type": call.emergency_type,
                "updated_at": datetime.datetime.utcnow()
                .replace(tzinfo=datetime.timezone.utc)
                .isoformat(),
            },
        )

        return frame  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def end_call(self, info: Info, input: EndCallInput) -> EmergencyCallType:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=input.call_id, user_id=user_id)
        call.status = CallStatus.ENDED
        call.outcome = input.outcome
        call.ended_at = datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)
        await call.asave(update_fields=["status", "outcome", "ended_at"])

        await channel_group_send(
            emergency_group(str(call.id)),
            {
                "type": "call.update",
                "call_id": str(call.id),
                "status": call.status,
                "peak_urgency_score": call.peak_urgency_score,
                "emergency_type": call.emergency_type,
                "updated_at": call.ended_at.isoformat(),
            },
        )

        return call  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def post_call_report(
        self, info: Info, input: PostCallReportInput
    ) -> EmergencyCallType:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=input.call_id, user_id=user_id)
        call.outcome = input.outcome
        await call.asave(update_fields=["outcome"])
        return call  # type: ignore[return-value]


@strawberry.type
class EmergencyQuery:
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def active_call(self, info: Info) -> EmergencyCallType | None:
        user_id = info.context.request.user_id
        try:
            return await EmergencyCall.objects.aget(  # type: ignore[return-value]
                user_id=user_id,
                status__in=[CallStatus.CONNECTING, CallStatus.ACTIVE, CallStatus.EMERGENCY_TRIGGERED],
            )
        except EmergencyCall.DoesNotExist:
            return None

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def call_frames(self, info: Info, call_id: strawberry.ID) -> list[EmergencyFrameType]:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=call_id, user_id=user_id)
        return [f async for f in EmergencyFrame.objects.filter(call=call)]  # type: ignore[return-value]

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def call_history(
        self,
        info: Info,
        limit: int = 20,
        offset: int = 0,
    ) -> list[EmergencyCallType]:
        user_id = info.context.request.user_id
        return [
            c async for c in EmergencyCall.objects.filter(
                user_id=user_id, status=CallStatus.ENDED
            )[offset : offset + limit]
        ]  # type: ignore[return-value]

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def call_report(self, info: Info, call_id: strawberry.ID) -> "CallReportType | None":
        user_id = info.context.request.user_id
        try:
            call = await EmergencyCall.objects.aget(id=call_id, user_id=user_id)
        except EmergencyCall.DoesNotExist:
            return None

        frames = [f async for f in EmergencyFrame.objects.filter(call=call)]
        all_signs: list[str] = []
        for frame in frames:
            all_signs.extend(frame.recognized_signs)

        top_signs = [s for s, _ in Counter(all_signs).most_common(10)]
        duration_seconds: int | None = None
        if call.ended_at and call.started_at:
            duration_seconds = int((call.ended_at - call.started_at).total_seconds())

        return CallReportType(
            call=call,  # type: ignore[arg-type]
            total_frames=len(frames),
            peak_urgency_score=call.peak_urgency_score,
            top_recognized_signs=top_signs,
            duration_seconds=duration_seconds,
            outcome=call.outcome,
        )


@strawberry.type
class CallReportType:
    call: EmergencyCallType
    total_frames: int
    peak_urgency_score: float
    top_recognized_signs: list[str]
    duration_seconds: int | None
    outcome: str


async def _gemini_auto_reply(call: EmergencyCall, recognized_signs: list[str], urgency_score: float) -> None:
    """Fire one Gemini-generated operator message when no human operator has accepted the call."""
    from apps.bystander.services import get_gemini_suggestion

    result = await get_gemini_suggestion(
        emergency_type=call.emergency_type,
        recognized_signs=recognized_signs,
        urgency_score=urgency_score,
        conversation_history=[],
    )

    primary = result["primary_suggestion"]
    steps: list[str] = result.get("steps", [])
    full_text = primary
    if steps:
        full_text += "\n" + "\n".join(f"• {s}" for s in steps)

    msg = await OperatorMessage.objects.acreate(
        call=call,
        text=full_text,
        gloss_sequence=[],
    )

    await channel_group_send(
        emergency_group(str(call.id)),
        {
            "type": "operator.message",
            "message_id": str(msg.id),
            "call_id": str(call.id),
            "text": msg.text,
            "gloss_sequence": [],
            "sent_at": msg.sent_at.isoformat(),
        },
    )