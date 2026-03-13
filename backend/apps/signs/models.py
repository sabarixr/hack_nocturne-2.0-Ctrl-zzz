from __future__ import annotations

import uuid

from django.db import models


class Sign(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    label = models.CharField(max_length=100, unique=True)
    category = models.CharField(
        max_length=20,
        choices=[
            ("EMERGENCY", "Emergency"),
            ("MEDICAL", "Medical"),
            ("FIRE_SAFETY", "Fire & Safety"),
            ("DAILY", "Daily Communication"),
        ],
    )
    description = models.TextField(blank=True, default="")
    demo_video_url = models.URLField(blank=True, default="")
    key_points = models.JSONField(default=list)
    difficulty_level = models.CharField(
        max_length=20,
        choices=[
            ("BEGINNER", "Beginner"),
            ("INTERMEDIATE", "Intermediate"),
            ("ADVANCED", "Advanced"),
        ],
        default="BEGINNER",
    )
    is_critical = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "signs"
        ordering = ["category", "label"]

    def __str__(self) -> str:
        return f"{self.label} ({self.category})"
