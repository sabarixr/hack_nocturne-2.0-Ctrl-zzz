from __future__ import annotations

import datetime
from typing import AsyncGenerator

import strawberry
from strawberry.types import Info

from shared.auth import IsAuthenticated
from shared.redis_layer import (
    bystander_group,
    channel_group_add,
    channel_group_discard,
    emergency_group,
)


@strawberry.type
class CallUpdateEvent:
    call_id: strawberry.ID
    status: str
    peak_urgency_score: float
    emergency_type: str
    updated_at: datetime.datetime


@strawberry.type
class OperatorMessageEvent:
    message_id: strawberry.ID
    call_id: strawberry.ID
    text: str
    gloss_sequence: strawberry.scalars.JSON
    sent_at: datetime.datetime
    sender: str  # "user" | "operator"


@strawberry.type
class BystanderMessageEvent:
    session_id: strawberry.ID
    sender: str
    text: str
    sent_at: datetime.datetime


@strawberry.type
class FrameMLEvent:
    """Real-time ML result pushed after each frame is processed server-side."""
    call_id: strawberry.ID
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


@strawberry.type
class EmergencySubscription:
    @strawberry.subscription(permission_classes=[IsAuthenticated])
    async def emergency_call_updated(
        self,
        info: Info,
        call_id: strawberry.ID,
    ) -> AsyncGenerator[CallUpdateEvent, None]:
        ws = info.context["ws"]
        group = emergency_group(str(call_id))
        await channel_group_add(group, ws.channel_name)
        try:
            async for message in ws.channel_receive():
                if message.get("type") != "call.update":
                    continue
                yield CallUpdateEvent(
                    call_id=message["call_id"],
                    status=message["status"],
                    peak_urgency_score=message["peak_urgency_score"],
                    emergency_type=message["emergency_type"],
                    updated_at=datetime.datetime.fromisoformat(message["updated_at"]),
                )
        finally:
            await channel_group_discard(group, ws.channel_name)

    @strawberry.subscription(permission_classes=[IsAuthenticated])
    async def operator_message_received(
        self,
        info: Info,
        call_id: strawberry.ID,
    ) -> AsyncGenerator[OperatorMessageEvent, None]:
        ws = info.context["ws"]
        group = emergency_group(str(call_id))
        await channel_group_add(group, ws.channel_name)
        try:
            async for message in ws.channel_receive():
                if message.get("type") != "operator.message":
                    continue
                yield OperatorMessageEvent(
                    message_id=message["message_id"],
                    call_id=message["call_id"],
                    text=message["text"],
                    gloss_sequence=message["gloss_sequence"],
                    sent_at=datetime.datetime.fromisoformat(message["sent_at"]),
                    sender=message.get("sender", "user" if message["text"].startswith("[USER]") else "operator"),
                )
        finally:
            await channel_group_discard(group, ws.channel_name)

    @strawberry.subscription(permission_classes=[IsAuthenticated])
    async def bystander_message_stream(
        self,
        info: Info,
        session_id: strawberry.ID,
    ) -> AsyncGenerator[BystanderMessageEvent, None]:
        ws = info.context["ws"]
        group = bystander_group(str(session_id))
        await channel_group_add(group, ws.channel_name)
        try:
            async for message in ws.channel_receive():
                if message.get("type") != "bystander.message":
                    continue
                yield BystanderMessageEvent(
                    session_id=message["session_id"],
                    sender=message["sender"],
                    text=message["text"],
                    sent_at=datetime.datetime.fromisoformat(message["sent_at"]),
                )
        finally:
            await channel_group_discard(group, ws.channel_name)

    @strawberry.subscription(permission_classes=[IsAuthenticated])
    async def frame_ml_stream(
        self,
        info: Info,
        call_id: strawberry.ID,
    ) -> AsyncGenerator[FrameMLEvent, None]:
        """Subscribe to real-time ML results for a call.

        The server pushes a FrameMLEvent every time a frame is processed by
        the MediaPipe pipeline, allowing the Flutter client to receive urgency
        scores and detection results as a continuous stream rather than waiting
        for individual mutation responses.
        """
        ws = info.context["ws"]
        group = emergency_group(str(call_id))
        await channel_group_add(group, ws.channel_name)
        try:
            async for message in ws.channel_receive():
                if message.get("type") != "frame.ml":
                    continue
                yield FrameMLEvent(
                    call_id=message["call_id"],
                    recognized_signs=message["recognized_signs"],
                    sign_confidence=message["sign_confidence"],
                    hand_detected=message["hand_detected"],
                    face_detected=message["face_detected"],
                    emotion_neutral=message["emotion_neutral"],
                    emotion_happy=message["emotion_happy"],
                    emotion_sad=message["emotion_sad"],
                    emotion_surprise=message["emotion_surprise"],
                    emotion_afraid=message["emotion_afraid"],
                    emotion_disgust=message["emotion_disgust"],
                    emotion_angry=message["emotion_angry"],
                    signing_speed=message["signing_speed"],
                    tremor_level=message["tremor_level"],
                    urgency_score=message["urgency_score"],
                )
        finally:
            await channel_group_discard(group, ws.channel_name)

