from __future__ import annotations

import uuid
import django.db.models.deletion

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ("emergency", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="RTCSession",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("sdp_offer", models.TextField(blank=True, default="")),
                ("sdp_answer", models.TextField(blank=True, default="")),
                ("ice_candidates_caller", models.JSONField(default=list)),
                ("ice_candidates_callee", models.JSONField(default=list)),
                ("is_connected", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("call", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name="rtc_session", to="emergency.emergencycall")),
            ],
            options={"db_table": "rtc_sessions"},
        ),
    ]
