from __future__ import annotations

import uuid

from django.db import models

from apps.users.models import User


class CallStatus(models.TextChoices):
    CONNECTING = "CONNECTING", "Connecting"
    ACTIVE = "ACTIVE", "Active"
    EMERGENCY_TRIGGERED = "EMERGENCY_TRIGGERED", "Emergency Triggered"
    ENDED = "ENDED", "Ended"


class EmergencyType(models.TextChoices):
    MEDICAL = "MEDICAL", "Medical"
    FIRE = "FIRE", "Fire"
    POLICE = "POLICE", "Police"
    OTHER = "OTHER", "Other"
    UNKNOWN = "UNKNOWN", "Unknown"


class EmergencyCall(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="emergency_calls")
    operator = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="handled_calls",
    )
    status = models.CharField(
        max_length=30, choices=CallStatus.choices, default=CallStatus.CONNECTING
    )
    emergency_type = models.CharField(
        max_length=20, choices=EmergencyType.choices, default=EmergencyType.UNKNOWN
    )
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    address = models.TextField(blank=True, default="")
    peak_urgency_score = models.FloatField(default=0.0)
    outcome = models.CharField(max_length=255, blank=True, default="")
    operator_accepted_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "emergency_calls"
        ordering = ["-started_at"]

    def __str__(self) -> str:
        return f"EmergencyCall({self.user.email}, {self.status})"


class EmergencyFrame(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    call = models.ForeignKey(
        EmergencyCall, on_delete=models.CASCADE, related_name="frames"
    )
    recognized_signs = models.JSONField(default=list)
    urgency_score = models.FloatField(default=0.0)
    emotion_fear = models.FloatField(default=0.0)
    emotion_pain = models.FloatField(default=0.0)
    emotion_panic = models.FloatField(default=0.0)
    signing_speed = models.FloatField(default=1.0)
    tremor_level = models.FloatField(default=0.0)
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    recorded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "emergency_frames"
        ordering = ["recorded_at"]


class OperatorMessage(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    call = models.ForeignKey(
        EmergencyCall, on_delete=models.CASCADE, related_name="operator_messages"
    )
    text = models.TextField()
    gloss_sequence = models.JSONField(default=list)
    sent_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "operator_messages"
        ordering = ["sent_at"]


class DispatchEvent(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    call = models.ForeignKey(
        EmergencyCall, on_delete=models.CASCADE, related_name="dispatch_events"
    )
    dispatch_type = models.CharField(max_length=50)
    eta_seconds = models.IntegerField(null=True, blank=True)
    dispatched_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "dispatch_events"
        ordering = ["dispatched_at"]
