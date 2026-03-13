from __future__ import annotations

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.signs.models import Sign
from shared.auth import IsAuthenticated


@strawberry_django.type(Sign)
class SignType:
    id: strawberry.ID
    label: str
    category: str
    description: str
    demo_video_url: str
    key_points: list[str]
    difficulty_level: str
    is_critical: bool


@strawberry.type
class SignQuery:
    @strawberry.field
    async def sign_database(
        self,
        category: str | None = None,
        search: str | None = None,
        is_critical: bool | None = None,
    ) -> list[SignType]:
        qs = Sign.objects.all()
        if category:
            qs = qs.filter(category=category)
        if search:
            qs = qs.filter(label__icontains=search)
        if is_critical is not None:
            qs = qs.filter(is_critical=is_critical)
        return [s async for s in qs]  # type: ignore[return-value]

    @strawberry.field
    async def sign(self, id: strawberry.ID) -> SignType | None:
        try:
            return await Sign.objects.aget(id=id)  # type: ignore[return-value]
        except Sign.DoesNotExist:
            return None

    @strawberry.field
    async def sign_by_label(self, label: str) -> SignType | None:
        try:
            return await Sign.objects.aget(label__iexact=label)  # type: ignore[return-value]
        except Sign.DoesNotExist:
            return None

    @strawberry.field
    async def critical_signs(self) -> list[SignType]:
        return [s async for s in Sign.objects.filter(is_critical=True)]  # type: ignore[return-value]
