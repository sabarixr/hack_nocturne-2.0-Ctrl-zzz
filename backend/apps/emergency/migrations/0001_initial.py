from __future__ import annotations

import uuid
import django.db.models.deletion

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ("users", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="EmergencyCall",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("status", models.CharField(choices=[("CONNECTING", "Connecting"), ("ACTIVE", "Active"), ("EMERGENCY_TRIGGERED", "Emergency Triggered"), ("ENDED", "Ended")], default="CONNECTING", max_length=30)),
                ("emergency_type", models.CharField(choices=[("MEDICAL", "Medical"), ("FIRE", "Fire"), ("POLICE", "Police"), ("OTHER", "Other"), ("UNKNOWN", "Unknown")], default="UNKNOWN", max_length=20)),
                ("latitude", models.FloatField(blank=True, null=True)),
                ("longitude", models.FloatField(blank=True, null=True)),
                ("address", models.TextField(blank=True, default="")),
                ("peak_urgency_score", models.FloatField(default=0.0)),
                ("outcome", models.CharField(blank=True, default="", max_length=255)),
                ("operator_accepted_at", models.DateTimeField(blank=True, null=True)),
                ("started_at", models.DateTimeField(auto_now_add=True)),
                ("ended_at", models.DateTimeField(blank=True, null=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="emergency_calls", to="users.user")),
                ("operator", models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name="handled_calls", to="users.user")),
            ],
            options={"db_table": "emergency_calls", "ordering": ["-started_at"]},
        ),
        migrations.CreateModel(
            name="EmergencyFrame",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("recognized_signs", models.JSONField(default=list)),
                ("urgency_score", models.FloatField(default=0.0)),
                ("emotion_fear", models.FloatField(default=0.0)),
                ("emotion_pain", models.FloatField(default=0.0)),
                ("emotion_panic", models.FloatField(default=0.0)),
                ("signing_speed", models.FloatField(default=1.0)),
                ("tremor_level", models.FloatField(default=0.0)),
                ("latitude", models.FloatField(blank=True, null=True)),
                ("longitude", models.FloatField(blank=True, null=True)),
                ("recorded_at", models.DateTimeField(auto_now_add=True)),
                ("call", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="frames", to="emergency.emergencycall")),
            ],
            options={"db_table": "emergency_frames", "ordering": ["recorded_at"]},
        ),
        migrations.CreateModel(
            name="OperatorMessage",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("text", models.TextField()),
                ("gloss_sequence", models.JSONField(default=list)),
                ("sent_at", models.DateTimeField(auto_now_add=True)),
                ("call", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="operator_messages", to="emergency.emergencycall")),
            ],
            options={"db_table": "operator_messages", "ordering": ["sent_at"]},
        ),
        migrations.CreateModel(
            name="DispatchEvent",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("dispatch_type", models.CharField(max_length=50)),
                ("eta_seconds", models.IntegerField(blank=True, null=True)),
                ("dispatched_at", models.DateTimeField(auto_now_add=True)),
                ("call", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="dispatch_events", to="emergency.emergencycall")),
            ],
            options={"db_table": "dispatch_events", "ordering": ["dispatched_at"]},
        ),
    ]
