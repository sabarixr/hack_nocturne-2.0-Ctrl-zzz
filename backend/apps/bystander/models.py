from __future__ import annotations

import uuid

from django.db import models

from apps.users.models import User
from apps.emergency.models import EmergencyCall


class BystanderSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    call = models.OneToOneField(
        EmergencyCall, on_delete=models.CASCADE, related_name="bystander_session"
    )
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    gemini_call_count = models.IntegerField(default=0)

    class Meta:
        db_table = "bystander_sessions"

    def __str__(self) -> str:
        return f"BystanderSession(call={self.call_id})"


class BystanderMessage(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(
        BystanderSession, on_delete=models.CASCADE, related_name="messages"
    )
    sender = models.CharField(
        max_length=20,
        choices=[("BYSTANDER", "Bystander"), ("OPERATOR", "Operator")],
        default="BYSTANDER",
    )
    text = models.TextField()
    sent_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "bystander_messages"
        ordering = ["sent_at"]


class AiSuggestion(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(
        BystanderSession, on_delete=models.CASCADE, related_name="ai_suggestions"
    )
    primary_suggestion = models.TextField()
    steps = models.JSONField(default=list)
    warnings = models.JSONField(default=list)
    raw_context_snapshot = models.JSONField(default=dict)
    generated_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "ai_suggestions"
        ordering = ["-generated_at"]
