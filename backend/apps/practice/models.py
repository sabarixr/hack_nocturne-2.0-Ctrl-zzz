from __future__ import annotations

import uuid

from django.db import models

from apps.users.models import User
from apps.signs.models import Sign


class PracticeSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="practice_sessions")
    sign = models.ForeignKey(Sign, on_delete=models.CASCADE, related_name="practice_sessions")
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    is_completed = models.BooleanField(default=False)

    class Meta:
        db_table = "practice_sessions"
        ordering = ["-started_at"]

    def __str__(self) -> str:
        return f"PracticeSession({self.user.email}, {self.sign.label})"


class SignAttempt(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(
        PracticeSession, on_delete=models.CASCADE, related_name="attempts"
    )
    sign = models.ForeignKey(Sign, on_delete=models.CASCADE, related_name="attempts")
    confidence = models.FloatField()
    predicted_label = models.CharField(max_length=100, blank=True, default="")
    landmark_payload = models.TextField(blank=True, default="")
    feedback = models.JSONField(default=list)
    attempted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "sign_attempts"
        ordering = ["attempted_at"]

    def __str__(self) -> str:
        return f"SignAttempt({self.sign.label}, conf={self.confidence:.2f})"
