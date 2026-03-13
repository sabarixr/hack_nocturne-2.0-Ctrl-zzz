from __future__ import annotations

import uuid

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = []

    operations = [
        migrations.CreateModel(
            name="Sign",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("label", models.CharField(max_length=100, unique=True)),
                ("category", models.CharField(choices=[("EMERGENCY", "Emergency"), ("MEDICAL", "Medical"), ("FIRE_SAFETY", "Fire & Safety"), ("DAILY", "Daily Communication")], max_length=20)),
                ("description", models.TextField(blank=True, default="")),
                ("demo_video_url", models.URLField(blank=True, default="")),
                ("key_points", models.JSONField(default=list)),
                ("difficulty_level", models.CharField(choices=[("BEGINNER", "Beginner"), ("INTERMEDIATE", "Intermediate"), ("ADVANCED", "Advanced")], default="BEGINNER", max_length=20)),
                ("is_critical", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={"db_table": "signs", "ordering": ["category", "label"]},
        ),
    ]
