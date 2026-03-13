from __future__ import annotations

import datetime

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.emergency.models import (
    CallStatus,
    DispatchEvent,
    EmergencyCall,
    OperatorMessage,
)
from shared.auth import IsAuthenticated, IsOperator
from shared.redis_layer import channel_group_send, emergency_group


@strawberry.input
class SendOperatorMessageInput:
    call_id: strawberry.ID
    text: str
    gloss_sequence: list[str] = strawberry.field(default_factory=list)


@strawberry.input
class DispatchInput:
    call_id: strawberry.ID
    dispatch_type: str
    eta_seconds: int | None = None


@strawberry.type
class OperatorQuery:
    @strawberry.field(permission_classes=[IsOperator])
    async def operator_calls(
        self,
        info: Info,
        include_ended: bool = False,
    ) -> list["OperatorCallView"]:
        statuses = (
            [CallStatus.CONNECTING, CallStatus.ACTIVE, CallStatus.EMERGENCY_TRIGGERED]
            if not include_ended
            else list(CallStatus.values)
        )
        calls = [
            c async for c in EmergencyCall.objects.filter(status__in=statuses)
            .order_by("-peak_urgency_score", "-started_at")
            .select_related("user", "operator")
        ]
        return [
            OperatorCallView(
                id=str(c.id),
                status=c.status,
                emergency_type=c.emergency_type,
                latitude=c.latitude,
                longitude=c.longitude,
                address=c.address,
                peak_urgency_score=c.peak_urgency_score,
                started_at=c.started_at,
                operator_accepted_at=c.operator_accepted_at,
                caller_name=c.user.name,
                caller_phone=c.user.phone,
                has_operator=c.operator_id is not None,
            )
            for c in calls
        ]

    @strawberry.field(permission_classes=[IsOperator])
    async def operator_call_detail(
        self, info: Info, call_id: strawberry.ID
    ) -> "OperatorCallView | None":
        try:
            c = await EmergencyCall.objects.select_related("user", "operator").aget(id=call_id)
        except EmergencyCall.DoesNotExist:
            return None
        return OperatorCallView(
            id=str(c.id),
            status=c.status,
            emergency_type=c.emergency_type,
            latitude=c.latitude,
            longitude=c.longitude,
            address=c.address,
            peak_urgency_score=c.peak_urgency_score,
            started_at=c.started_at,
            operator_accepted_at=c.operator_accepted_at,
            caller_name=c.user.name,
            caller_phone=c.user.phone,
            has_operator=c.operator_id is not None,
        )


@strawberry.type
class OperatorCallView:
    id: strawberry.ID
    status: str
    emergency_type: str
    latitude: float | None
    longitude: float | None
    address: str
    peak_urgency_score: float
    started_at: datetime.datetime
    operator_accepted_at: datetime.datetime | None
    caller_name: str
    caller_phone: str
    has_operator: bool


@strawberry.type
class OperatorMutation:
    @strawberry.mutation(permission_classes=[IsOperator])
    async def accept_call(self, info: Info, call_id: strawberry.ID) -> "OperatorCallView":
        operator_id = info.context.request.user_id
        call = await EmergencyCall.objects.select_related("user").aget(id=call_id)
        call.operator_id = operator_id
        call.operator_accepted_at = datetime.datetime.utcnow().replace(
            tzinfo=datetime.timezone.utc
        )
        if call.status == CallStatus.CONNECTING:
            call.status = CallStatus.ACTIVE
        await call.asave(update_fields=["operator_id", "operator_accepted_at", "status"])

        await channel_group_send(
            emergency_group(str(call.id)),
            {
                "type": "call.update",
                "call_id": str(call.id),
                "status": call.status,
                "peak_urgency_score": call.peak_urgency_score,
                "emergency_type": call.emergency_type,
                "updated_at": call.operator_accepted_at.isoformat(),
            },
        )

        return OperatorCallView(
            id=str(call.id),
            status=call.status,
            emergency_type=call.emergency_type,
            latitude=call.latitude,
            longitude=call.longitude,
            address=call.address,
            peak_urgency_score=call.peak_urgency_score,
            started_at=call.started_at,
            operator_accepted_at=call.operator_accepted_at,
            caller_name=call.user.name,
            caller_phone=call.user.phone,
            has_operator=True,
        )

    @strawberry.mutation(permission_classes=[IsOperator])
    async def send_operator_message(
        self, info: Info, input: SendOperatorMessageInput
    ) -> "OperatorMessageOut":
        call = await EmergencyCall.objects.aget(id=input.call_id)
        msg = await OperatorMessage.objects.acreate(
            call=call,
            text=input.text,
            gloss_sequence=input.gloss_sequence,
        )
        await channel_group_send(
            emergency_group(str(call.id)),
            {
                "type": "operator.message",
                "message_id": str(msg.id),
                "call_id": str(call.id),
                "text": msg.text,
                "gloss_sequence": msg.gloss_sequence,
                "sent_at": msg.sent_at.isoformat(),
            },
        )
        return OperatorMessageOut(
            id=str(msg.id),
            call_id=str(call.id),
            text=msg.text,
            gloss_sequence=msg.gloss_sequence,
            sent_at=msg.sent_at,
        )

    @strawberry.mutation(permission_classes=[IsOperator])
    async def create_dispatch_event(
        self, info: Info, input: DispatchInput
    ) -> "DispatchEventOut":
        call = await EmergencyCall.objects.aget(id=input.call_id)
        event = await DispatchEvent.objects.acreate(
            call=call,
            dispatch_type=input.dispatch_type,
            eta_seconds=input.eta_seconds,
        )
        await channel_group_send(
            emergency_group(str(call.id)),
            {
                "type": "call.update",
                "call_id": str(call.id),
                "status": call.status,
                "peak_urgency_score": call.peak_urgency_score,
                "emergency_type": call.emergency_type,
                "updated_at": event.dispatched_at.isoformat(),
            },
        )
        return DispatchEventOut(
            id=str(event.id),
            call_id=str(call.id),
            dispatch_type=event.dispatch_type,
            eta_seconds=event.eta_seconds,
            dispatched_at=event.dispatched_at,
        )


@strawberry.type
class OperatorMessageOut:
    id: strawberry.ID
    call_id: strawberry.ID
    text: str
    gloss_sequence: strawberry.scalars.JSON
    sent_at: datetime.datetime


@strawberry.type
class DispatchEventOut:
    id: strawberry.ID
    call_id: strawberry.ID
    dispatch_type: str
    eta_seconds: int | None
    dispatched_at: datetime.datetime
