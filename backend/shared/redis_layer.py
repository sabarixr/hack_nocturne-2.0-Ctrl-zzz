from __future__ import annotations

from typing import Any

from channels.layers import get_channel_layer


async def channel_group_send(group: str, message: dict[str, Any]) -> None:
    layer = get_channel_layer()
    await layer.group_send(group, message)


async def channel_group_add(group: str, channel: str) -> None:
    layer = get_channel_layer()
    await layer.group_add(group, channel)


async def channel_group_discard(group: str, channel: str) -> None:
    layer = get_channel_layer()
    await layer.group_discard(group, channel)


def emergency_group(call_id: str) -> str:
    """Group for call.update messages (status changes, urgency updates)."""
    return f"emergency_{call_id}"


def operator_message_group(call_id: str) -> str:
    """Group for operator.message events — separate from call.update so both
    subscriptions can coexist on the same WS connection without racing."""
    return f"emergency_op_{call_id}"


def frame_ml_group(call_id: str) -> str:
    """Group for frame.ml events — separate channel so frameMlStream doesn't
    starve the other subscriptions."""
    return f"emergency_ml_{call_id}"


def webrtc_group(call_id: str) -> str:
    return f"webrtc_{call_id}"


def bystander_group(session_id: str) -> str:
    return f"bystander_{session_id}"
