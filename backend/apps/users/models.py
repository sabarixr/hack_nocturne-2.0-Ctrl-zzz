from __future__ import annotations

import uuid

from django.contrib.auth.base_user import AbstractBaseUser, BaseUserManager
from django.contrib.auth.models import PermissionsMixin
from django.db import models


class UserManager(BaseUserManager["User"]):
    def create_user(self, email: str, password: str, **extra_fields: object) -> "User":
        if not email:
            raise ValueError("Email is required")
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email: str, password: str, **extra_fields: object) -> "User":
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        return self.create_user(email, password, **extra_fields)


class PanicSensitivity(models.TextChoices):
    LOW = "LOW", "Low"
    MEDIUM = "MEDIUM", "Medium"
    HIGH = "HIGH", "High"


class SignLanguage(models.TextChoices):
    ASL = "ASL", "American Sign Language"
    BSL = "BSL", "British Sign Language"
    ISL = "ISL", "Indian Sign Language"
    OTHER = "OTHER", "Other"


class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=255)
    phone = models.CharField(max_length=20, blank=True, default="")
    age = models.PositiveIntegerField(null=True, blank=True)
    primary_language = models.CharField(
        max_length=10, choices=SignLanguage.choices, default=SignLanguage.ASL
    )
    profile_accuracy = models.FloatField(default=0.0)
    is_calibrated = models.BooleanField(default=False)
    emergency_threshold = models.FloatField(default=0.85)
    panic_sensitivity = models.CharField(
        max_length=10, choices=PanicSensitivity.choices, default=PanicSensitivity.MEDIUM
    )
    last_calibrated_at = models.DateTimeField(null=True, blank=True)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["name"]

    objects: UserManager = UserManager()

    class Meta:
        db_table = "users"

    def __str__(self) -> str:
        return self.email


class EmergencyContact(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="emergency_contacts")
    name = models.CharField(max_length=255)
    phone = models.CharField(max_length=20)
    relationship = models.CharField(max_length=100, blank=True, default="")
    is_primary = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "emergency_contacts"
        ordering = ["-is_primary", "name"]

    def __str__(self) -> str:
        return f"{self.name} ({self.user.email})"


class CalibrationProfile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="calibration_profile"
    )
    panic_speed_multiplier = models.FloatField(default=1.0)
    tremor_amplitude = models.FloatField(default=0.0)
    facial_distress_baseline = models.FloatField(default=0.0)
    calm_motion_baseline = models.FloatField(default=1.0)
    stress_confidence_drop = models.FloatField(default=0.0)
    calibration_accuracy = models.FloatField(default=0.0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "calibration_profiles"

    def __str__(self) -> str:
        return f"CalibrationProfile({self.user.email})"
