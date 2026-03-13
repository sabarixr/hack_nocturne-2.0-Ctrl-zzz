from __future__ import annotations

from typing import Any

import jwt
from django.conf import settings
from strawberry.permission import BasePermission
from strawberry.types import Info

from apps.users.services import create_access_token as create_access_token  # re-export


def decode_token(token: str) -> dict[str, Any]:
    return jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])


def get_user_id_from_request(request: Any) -> str | None:
    auth_header = getattr(request, "headers", {}).get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None
    token = auth_header.split(" ", 1)[1]
    try:
        payload = decode_token(token)
        return payload.get("sub")
    except jwt.PyJWTError:
        return None


class IsAuthenticated(BasePermission):
    message = "Authentication required"

    def has_permission(self, source: Any, info: Info, **kwargs: Any) -> bool:
        return info.context.request.user_id is not None


class IsOperator(BasePermission):
    message = "Operator access required"

    def has_permission(self, source: Any, info: Info, **kwargs: Any) -> bool:
        return getattr(info.context.request, "is_operator", False)
