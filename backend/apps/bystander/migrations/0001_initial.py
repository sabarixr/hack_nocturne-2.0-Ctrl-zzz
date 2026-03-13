from __future__ import annotations

import uuid
import django.db.models.deletion

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ("emergency", "0001_initial"),
        ("users", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="BystanderSession",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("started_at", models.DateTimeField(auto_now_add=True)),
                ("ended_at", models.DateTimeField(blank=True, null=True)),
                ("gemini_call_count", models.IntegerField(default=0)),
                ("call", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name="bystander_session", to="emergency.emergencycall")),
            ],
            options={"db_table": "bystander_sessions"},
        ),
        migrations.CreateModel(
            name="BystanderMessage",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("sender", models.CharField(choices=[("BYSTANDER", "Bystander"), ("OPERATOR", "Operator")], default="BYSTANDER", max_length=20)),
                ("text", models.TextField()),
                ("sent_at", models.DateTimeField(auto_now_add=True)),
                ("session", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="messages", to="bystander.bystandersession")),
            ],
            options={"db_table": "bystander_messages", "ordering": ["sent_at"]},
        ),
        migrations.CreateModel(
            name="AiSuggestion",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("primary_suggestion", models.TextField()),
                ("steps", models.JSONField(default=list)),
                ("warnings", models.JSONField(default=list)),
                ("raw_context_snapshot", models.JSONField(default=dict)),
                ("generated_at", models.DateTimeField(auto_now_add=True)),
                ("session", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="ai_suggestions", to="bystander.bystandersession")),
            ],
            options={"db_table": "ai_suggestions", "ordering": ["-generated_at"]},
        ),
    ]
