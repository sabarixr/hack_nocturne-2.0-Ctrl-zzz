from __future__ import annotations

import datetime
from typing import AsyncGenerator

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.webrtc.models import RTCSession
from shared.auth import IsAuthenticated
from shared.redis_layer import channel_group_add, channel_group_discard, channel_group_send, webrtc_group


@strawberry_django.type(RTCSession)
class RTCSessionType:
    id: strawberry.ID
    call_id: strawberry.ID
    sdp_offer: str
    sdp_answer: str
    ice_candidates_caller: strawberry.scalars.JSON
    ice_candidates_callee: strawberry.scalars.JSON
    is_connected: bool
    created_at: datetime.datetime
    updated_at: datetime.datetime


@strawberry.type
class IceCandidateEvent:
    call_id: strawberry.ID
    candidate: str
    sdp_mid: str
    sdp_m_line_index: int
    from_caller: bool


@strawberry.type
class WebRTCMutation:
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def initiate_webrtc(self, info: Info, call_id: strawberry.ID, sdp_offer: str) -> RTCSessionType:
        user_id = info.context.request.user_id
        from apps.emergency.models import EmergencyCall
        call = await EmergencyCall.objects.aget(id=call_id, user_id=user_id)
        session, _ = await RTCSession.objects.aupdate_or_create(
            call=call,
            defaults={"sdp_offer": sdp_offer, "sdp_answer": "", "is_connected": False},
        )
        await channel_group_send(
            webrtc_group(str(call_id)),
            {
                "type": "webrtc.offer",
                "call_id": str(call_id),
                "sdp_offer": sdp_offer,
            },
        )
        return session  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def submit_webrtc_answer(self, info: Info, call_id: strawberry.ID, sdp_answer: str) -> RTCSessionType:
        from apps.emergency.models import EmergencyCall
        call = await EmergencyCall.objects.aget(id=call_id)
        session = await RTCSession.objects.aget(call=call)
        session.sdp_answer = sdp_answer
        session.is_connected = True
        await session.asave(update_fields=["sdp_answer", "is_connected"])
        await channel_group_send(
            webrtc_group(str(call_id)),
            {
                "type": "webrtc.answer",
                "call_id": str(call_id),
                "sdp_answer": sdp_answer,
            },
        )
        return session  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def add_ice_candidate(
        self,
        info: Info,
        call_id: strawberry.ID,
        candidate: str,
        sdp_mid: str,
        sdp_m_line_index: int,
        from_caller: bool,
    ) -> bool:
        from apps.emergency.models import EmergencyCall
        call = await EmergencyCall.objects.aget(id=call_id)
        session = await RTCSession.objects.aget(call=call)
        new_candidate = {
            "candidate": candidate,
            "sdpMid": sdp_mid,
            "sdpMLineIndex": sdp_m_line_index,
        }
        if from_caller:
            session.ice_candidates_caller = session.ice_candidates_caller + [new_candidate]
            await session.asave(update_fields=["ice_candidates_caller"])
        else:
            session.ice_candidates_callee = session.ice_candidates_callee + [new_candidate]
            await session.asave(update_fields=["ice_candidates_callee"])

        await channel_group_send(
            webrtc_group(str(call_id)),
            {
                "type": "webrtc.ice",
                "call_id": str(call_id),
                "candidate": candidate,
                "sdp_mid": sdp_mid,
                "sdp_m_line_index": sdp_m_line_index,
                "from_caller": from_caller,
            },
        )
        return True


@strawberry.type
class WebRTCSubscription:
    @strawberry.subscription(permission_classes=[IsAuthenticated])
    async def webrtc_signaling(
        self,
        info: Info,
        call_id: strawberry.ID,
    ) -> AsyncGenerator[IceCandidateEvent, None]:
        ws = info.context["ws"]
        group = webrtc_group(str(call_id))
        await channel_group_add(group, ws.channel_name)
        try:
            async for message in ws.channel_receive():
                if message.get("type") != "webrtc.ice":
                    continue
                yield IceCandidateEvent(
                    call_id=message["call_id"],
                    candidate=message["candidate"],
                    sdp_mid=message["sdp_mid"],
                    sdp_m_line_index=message["sdp_m_line_index"],
                    from_caller=message["from_caller"],
                )
        finally:
            await channel_group_discard(group, ws.channel_name)
