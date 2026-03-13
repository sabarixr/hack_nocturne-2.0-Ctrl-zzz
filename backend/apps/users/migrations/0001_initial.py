from __future__ import annotations

import apps.users.models
import django.db.models.deletion
import uuid

from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ("auth", "0012_alter_user_first_name_max_length"),
    ]

    operations = [
        migrations.CreateModel(
            name="User",
            fields=[
                ("password", models.CharField(max_length=128, verbose_name="password")),
                ("last_login", models.DateTimeField(blank=True, null=True, verbose_name="last login")),
                ("is_superuser", models.BooleanField(default=False, verbose_name="superuser status")),
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("email", models.EmailField(max_length=254, unique=True)),
                ("name", models.CharField(max_length=255)),
                ("phone", models.CharField(blank=True, default="", max_length=20)),
                ("age", models.PositiveIntegerField(blank=True, null=True)),
                ("primary_language", models.CharField(choices=[("ASL", "American Sign Language"), ("BSL", "British Sign Language"), ("ISL", "Indian Sign Language"), ("OTHER", "Other")], default="ASL", max_length=10)),
                ("profile_accuracy", models.FloatField(default=0.0)),
                ("is_calibrated", models.BooleanField(default=False)),
                ("emergency_threshold", models.FloatField(default=0.85)),
                ("panic_sensitivity", models.CharField(choices=[("LOW", "Low"), ("MEDIUM", "Medium"), ("HIGH", "High")], default="MEDIUM", max_length=10)),
                ("last_calibrated_at", models.DateTimeField(blank=True, null=True)),
                ("is_active", models.BooleanField(default=True)),
                ("is_staff", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("groups", models.ManyToManyField(blank=True, related_name="user_set", related_query_name="user", to="auth.group", verbose_name="groups")),
                ("user_permissions", models.ManyToManyField(blank=True, related_name="user_set", related_query_name="user", to="auth.permission", verbose_name="user permissions")),
            ],
            options={"db_table": "users"},
            managers=[("objects", apps.users.models.UserManager())],
        ),
        migrations.CreateModel(
            name="EmergencyContact",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("name", models.CharField(max_length=255)),
                ("phone", models.CharField(max_length=20)),
                ("relationship", models.CharField(blank=True, default="", max_length=100)),
                ("is_primary", models.BooleanField(default=False)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="emergency_contacts", to="users.user")),
            ],
            options={"db_table": "emergency_contacts", "ordering": ["-is_primary", "name"]},
        ),
        migrations.CreateModel(
            name="CalibrationProfile",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("panic_speed_multiplier", models.FloatField(default=1.0)),
                ("tremor_amplitude", models.FloatField(default=0.0)),
                ("facial_distress_baseline", models.FloatField(default=0.0)),
                ("calm_motion_baseline", models.FloatField(default=1.0)),
                ("stress_confidence_drop", models.FloatField(default=0.0)),
                ("calibration_accuracy", models.FloatField(default=0.0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("user", models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name="calibration_profile", to="users.user")),
            ],
            options={"db_table": "calibration_profiles"},
        ),
    ]
