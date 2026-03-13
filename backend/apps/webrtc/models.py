from __future__ import annotations

import uuid

from django.db import models

from apps.emergency.models import EmergencyCall


class RTCSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    call = models.OneToOneField(
        EmergencyCall, on_delete=models.CASCADE, related_name="rtc_session"
    )
    sdp_offer = models.TextField(blank=True, default="")
    sdp_answer = models.TextField(blank=True, default="")
    ice_candidates_caller = models.JSONField(default=list)
    ice_candidates_callee = models.JSONField(default=list)
    is_connected = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "rtc_sessions"

    def __str__(self) -> str:
        return f"RTCSession(call={self.call_id})"
