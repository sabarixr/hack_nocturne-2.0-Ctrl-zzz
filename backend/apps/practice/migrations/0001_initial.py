from __future__ import annotations

import uuid
import django.db.models.deletion

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ("signs", "0001_initial"),
        ("users", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="PracticeSession",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("started_at", models.DateTimeField(auto_now_add=True)),
                ("ended_at", models.DateTimeField(blank=True, null=True)),
                ("is_completed", models.BooleanField(default=False)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="practice_sessions", to="users.user")),
                ("sign", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="practice_sessions", to="signs.sign")),
            ],
            options={"db_table": "practice_sessions", "ordering": ["-started_at"]},
        ),
        migrations.CreateModel(
            name="SignAttempt",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("confidence", models.FloatField()),
                ("predicted_label", models.CharField(blank=True, default="", max_length=100)),
                ("landmark_payload", models.TextField(blank=True, default="")),
                ("feedback", models.JSONField(default=list)),
                ("attempted_at", models.DateTimeField(auto_now_add=True)),
                ("session", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="attempts", to="practice.practicesession")),
                ("sign", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="attempts", to="signs.sign")),
            ],
            options={"db_table": "sign_attempts", "ordering": ["attempted_at"]},
        ),
    ]
