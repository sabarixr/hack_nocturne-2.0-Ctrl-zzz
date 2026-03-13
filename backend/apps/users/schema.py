from __future__ import annotations

import datetime
from typing import Any

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.users.models import (
    CalibrationProfile,
    EmergencyContact,
    User,
)
from apps.users.services import create_access_token, verify_password
from shared.auth import IsAuthenticated


@strawberry_django.type(User)
class UserType:
    id: strawberry.ID
    email: str
    name: str
    phone: str
    age: int | None
    primary_language: str
    profile_accuracy: float
    is_calibrated: bool
    emergency_threshold: float
    panic_sensitivity: str
    last_calibrated_at: datetime.datetime | None
    created_at: datetime.datetime
    updated_at: datetime.datetime

    @strawberry_django.field
    def emergency_contacts(self, root: User) -> list["EmergencyContactType"]:
        return list(root.emergency_contacts.all())

    @strawberry_django.field
    def calibration_profile(self, root: User) -> "CalibrationProfileType | None":
        return getattr(root, "calibration_profile", None)


@strawberry_django.type(EmergencyContact)
class EmergencyContactType:
    id: strawberry.ID
    name: str
    phone: str
    relationship: str
    is_primary: bool
    created_at: datetime.datetime
    updated_at: datetime.datetime


@strawberry_django.type(CalibrationProfile)
class CalibrationProfileType:
    id: strawberry.ID
    panic_speed_multiplier: float
    tremor_amplitude: float
    facial_distress_baseline: float
    calm_motion_baseline: float
    stress_confidence_drop: float
    calibration_accuracy: float
    created_at: datetime.datetime
    updated_at: datetime.datetime


@strawberry.type
class AuthPayload:
    token: str
    user: UserType


@strawberry.input
class RegisterInput:
    name: str
    email: str
    password: str
    phone: str = ""
    age: int | None = None
    primary_language: str = "ASL"


@strawberry.input
class LoginInput:
    email: str
    password: str


@strawberry.input
class UpdateProfileInput:
    name: str | None = None
    phone: str | None = None
    age: int | None = None
    primary_language: str | None = None
    emergency_threshold: float | None = None
    panic_sensitivity: str | None = None


@strawberry.input
class EmergencyContactInput:
    name: str
    phone: str
    relationship: str = ""
    is_primary: bool = False


@strawberry.input
class CalibrationInput:
    panic_speed_multiplier: float
    tremor_amplitude: float
    facial_distress_baseline: float
    calm_motion_baseline: float
    stress_confidence_drop: float
    calibration_accuracy: float


@strawberry.type
class UserQuery:
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def me(self, info: Info) -> UserType:
        user = await User.objects.aget(id=info.context.request.user_id)
        return user  # type: ignore[return-value]

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def emergency_contacts(self, info: Info) -> list[EmergencyContactType]:
        contacts = EmergencyContact.objects.filter(user_id=info.context.request.user_id)
        return [c async for c in contacts]  # type: ignore[return-value]


@strawberry.type
class AuthMutation:
    @strawberry.mutation
    async def register(self, input: RegisterInput) -> AuthPayload:
        if await User.objects.filter(email=input.email).aexists():
            raise ValueError("Email already registered")

        user = User(
            email=input.email,
            name=input.name,
            phone=input.phone,
            age=input.age,
            primary_language=input.primary_language,
        )
        user.set_password(input.password)
        await user.asave()

        token = create_access_token(str(user.id))
        return AuthPayload(token=token, user=user)  # type: ignore[return-value]

    @strawberry.mutation
    async def login(self, input: LoginInput) -> AuthPayload:
        try:
            user = await User.objects.aget(email=input.email)
        except User.DoesNotExist:
            raise ValueError("Invalid credentials")

        if not verify_password(input.password, user.password):
            raise ValueError("Invalid credentials")

        token = create_access_token(str(user.id), is_staff=user.is_staff)
        return AuthPayload(token=token, user=user)  # type: ignore[return-value]


@strawberry.type
class UserMutation:
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def update_profile(self, info: Info, input: UpdateProfileInput) -> UserType:
        user = await User.objects.aget(id=info.context.request.user_id)
        fields = input.__dict__
        for field, value in fields.items():
            if value is not None:
                setattr(user, field, value)
        await user.asave()
        return user  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def add_emergency_contact(
        self, info: Info, input: EmergencyContactInput
    ) -> EmergencyContactType:
        if input.is_primary:
            await EmergencyContact.objects.filter(
                user_id=info.context.request.user_id, is_primary=True
            ).aupdate(is_primary=False)

        contact = await EmergencyContact.objects.acreate(
            user_id=info.context.request.user_id,
            name=input.name,
            phone=input.phone,
            relationship=input.relationship,
            is_primary=input.is_primary,
        )
        return contact  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def update_emergency_contact(
        self, info: Info, id: strawberry.ID, input: EmergencyContactInput
    ) -> EmergencyContactType:
        contact = await EmergencyContact.objects.aget(
            id=id, user_id=info.context.request.user_id
        )
        if input.is_primary and not contact.is_primary:
            await EmergencyContact.objects.filter(
                user_id=info.context.request.user_id, is_primary=True
            ).aupdate(is_primary=False)

        contact.name = input.name
        contact.phone = input.phone
        contact.relationship = input.relationship
        contact.is_primary = input.is_primary
        await contact.asave()
        return contact  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def delete_emergency_contact(
        self, info: Info, id: strawberry.ID
    ) -> bool:
        deleted, _ = await EmergencyContact.objects.filter(
            id=id, user_id=info.context.request.user_id
        ).adelete()
        return deleted > 0

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def save_calibration_profile(
        self, info: Info, input: CalibrationInput
    ) -> CalibrationProfileType:
        profile, _ = await CalibrationProfile.objects.aupdate_or_create(
            user_id=info.context.request.user_id,
            defaults={
                "panic_speed_multiplier": input.panic_speed_multiplier,
                "tremor_amplitude": input.tremor_amplitude,
                "facial_distress_baseline": input.facial_distress_baseline,
                "calm_motion_baseline": input.calm_motion_baseline,
                "stress_confidence_drop": input.stress_confidence_drop,
                "calibration_accuracy": input.calibration_accuracy,
            },
        )
        await User.objects.filter(id=info.context.request.user_id).aupdate(
            is_calibrated=True,
            last_calibrated_at=datetime.datetime.utcnow(),
        )
        return profile  # type: ignore[return-value]
