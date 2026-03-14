from __future__ import annotations

import asyncio
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
from apps.emergency.services import compute_urgency_score, force_urgency
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
    emotion_angry: float
    emotion_sad: float
    emotion_neutral: float
    emotion_happy: float
    emotion_surprise: float
    emotion_afraid: float
    emotion_disgust: float
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
    # Base64-encoded JPEG frame — when provided the server runs MediaPipe and
    # ignores the client-supplied emotion / sign fields (they are overwritten).
    frame_data: str | None = None
    # Client-supplied fallback values (used when frame_data is absent)
    recognized_signs: list[str] = strawberry.field(default_factory=list)
    emotion_angry: float = 0.0
    emotion_sad: float = 0.0
    emotion_neutral: float = 0.0
    emotion_happy: float = 0.0
    emotion_surprise: float = 0.0
    emotion_afraid: float = 0.0
    emotion_disgust: float = 0.0
    signing_speed: float = 1.0
    tremor_level: float = 0.0
    latitude: float | None = None
    longitude: float | None = None


@strawberry.type
class FrameMLResult:
    """ML results returned to the Flutter client after server-side processing."""
    recognized_signs: list[str]
    sign_confidence: float
    hand_detected: bool
    face_detected: bool
    emotion_neutral: float
    emotion_happy: float
    emotion_sad: float
    emotion_surprise: float
    emotion_afraid: float
    emotion_disgust: float
    emotion_angry: float
    signing_speed: float
    tremor_level: float
    urgency_score: float


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
    async def submit_frame(self, info: Info, input: SubmitFrameInput) -> FrameMLResult:
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=input.call_id, user_id=user_id)

        # ── Server-side ML processing ────────────────────────────────────────
        # When the client sends a raw JPEG frame we run MediaPipe on the server
        # and use those results instead of the (potentially absent/fake)
        # client-supplied emotion/sign fields.
        if input.frame_data:
            from apps.emergency import ml_pipeline  # noqa: PLC0415

            loop = asyncio.get_event_loop()
            ml = await loop.run_in_executor(
                None,
                ml_pipeline.process_frame,
                input.frame_data,
                str(input.call_id),
            )
            recognized_signs = ml["recognized_signs"]
            sign_confidence = ml["sign_confidence"]
            hand_detected = ml["hand_detected"]
            face_detected = ml["face_detected"]
            emotion_angry = ml["emotion_angry"]
            emotion_sad = ml["emotion_sad"]
            emotion_neutral = ml["emotion_neutral"]
            emotion_happy = ml["emotion_happy"]
            emotion_surprise = ml["emotion_surprise"]
            emotion_afraid = ml["emotion_afraid"]
            emotion_disgust = ml["emotion_disgust"]
            signing_speed = ml["signing_speed"]
            tremor_level = ml["tremor_level"]
        else:
            recognized_signs = input.recognized_signs
            sign_confidence = 0.0
            hand_detected = len(input.recognized_signs) > 0
            face_detected = input.emotion_neutral < 0.95
            emotion_angry = input.emotion_angry
            emotion_sad = input.emotion_sad
            emotion_neutral = input.emotion_neutral
            emotion_happy = input.emotion_happy
            emotion_surprise = input.emotion_surprise
            emotion_afraid = input.emotion_afraid
            emotion_disgust = input.emotion_disgust
            signing_speed = input.signing_speed
            tremor_level = input.tremor_level

        urgency_score = compute_urgency_score(
            recognized_signs=recognized_signs,
            emotion_angry=emotion_angry,
            emotion_sad=emotion_sad,
            emotion_neutral=emotion_neutral,
            emotion_happy=emotion_happy,
            emotion_surprise=emotion_surprise,
            emotion_afraid=emotion_afraid,
            emotion_disgust=emotion_disgust,
            signing_speed=signing_speed,
            tremor_level=tremor_level,
            call_id=str(input.call_id),
        )

        await EmergencyFrame.objects.acreate(
            call=call,
            recognized_signs=recognized_signs,
            urgency_score=urgency_score,
            emotion_angry=emotion_angry,
            emotion_sad=emotion_sad,
            emotion_neutral=emotion_neutral,
            emotion_happy=emotion_happy,
            emotion_surprise=emotion_surprise,
            emotion_afraid=emotion_afraid,
            emotion_disgust=emotion_disgust,
            signing_speed=signing_speed,
            tremor_level=tremor_level,
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
                await _gemini_auto_reply(call, recognized_signs, urgency_score)

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

        # Also broadcast the full ML result so frameMLStream subscribers get it
        await channel_group_send(
            emergency_group(str(call.id)),
            {
                "type": "frame.ml",
                "call_id": str(call.id),
                "recognized_signs": recognized_signs,
                "sign_confidence": sign_confidence,
                "hand_detected": hand_detected,
                "face_detected": face_detected,
                "emotion_neutral": emotion_neutral,
                "emotion_happy": emotion_happy,
                "emotion_sad": emotion_sad,
                "emotion_surprise": emotion_surprise,
                "emotion_afraid": emotion_afraid,
                "emotion_disgust": emotion_disgust,
                "emotion_angry": emotion_angry,
                "signing_speed": signing_speed,
                "tremor_level": tremor_level,
                "urgency_score": urgency_score,
            },
        )

        return FrameMLResult(
            recognized_signs=recognized_signs,
            sign_confidence=sign_confidence,
            hand_detected=hand_detected,
            face_detected=face_detected,
            emotion_neutral=emotion_neutral,
            emotion_happy=emotion_happy,
            emotion_sad=emotion_sad,
            emotion_surprise=emotion_surprise,
            emotion_afraid=emotion_afraid,
            emotion_disgust=emotion_disgust,
            emotion_angry=emotion_angry,
            signing_speed=signing_speed,
            tremor_level=tremor_level,
            urgency_score=urgency_score,
        )

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def trigger_emergency(self, info: Info, call_id: strawberry.ID) -> EmergencyCallType:
        """Force urgency to 1.0 — the SOS button. Immediately triggers EMERGENCY_TRIGGERED."""
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=call_id, user_id=user_id)
        force_urgency(str(call_id))
        call.peak_urgency_score = 1.0
        call.status = CallStatus.EMERGENCY_TRIGGERED
        await call.asave(update_fields=["peak_urgency_score", "status"])

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

        # Trigger AI advice immediately
        await _gemini_auto_reply(call, [], 1.0)
        return call  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def send_message(self, info: Info, call_id: strawberry.ID, text: str) -> OperatorMessageType:
        """User sends a typed text message during the call — broadcast to operator dashboard."""
        user_id = info.context.request.user_id
        call = await EmergencyCall.objects.aget(id=call_id, user_id=user_id)

        msg = await OperatorMessage.objects.acreate(
            call=call,
            text=f"[USER] {text}",
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

        # AI replies to the user's typed message immediately
        if call.operator_id is None:
            await _gemini_auto_reply(call, [], call.peak_urgency_score, user_message=text)

        return msg  # type: ignore[return-value]

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


async def _gemini_auto_reply(
    call: EmergencyCall,
    recognized_signs: list[str],
    urgency_score: float,
    user_message: str = "",
) -> None:
    """Fire one Gemini-generated operator message when no human operator has accepted the call."""
    from apps.bystander.services import get_gemini_suggestion

    # Build recent conversation history from the last few OperatorMessages
    history: list[dict] = []
    async for m in OperatorMessage.objects.filter(call=call).order_by("-sent_at")[:6]:
        role = "user" if m.text.startswith("[USER]") else "assistant"
        history.append({"role": role, "text": m.text.removeprefix("[USER] ")})
    history.reverse()

    result = await get_gemini_suggestion(
        emergency_type=call.emergency_type,
        recognized_signs=recognized_signs,
        urgency_score=urgency_score,
        conversation_history=history,
        user_message=user_message,
    )

    full_text = result["primary_suggestion"]

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