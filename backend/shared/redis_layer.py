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
    return f"emergency_{call_id}"


def webrtc_group(call_id: str) -> str:
    return f"webrtc_{call_id}"


def bystander_group(session_id: str) -> str:
    return f"bystander_{session_id}"
