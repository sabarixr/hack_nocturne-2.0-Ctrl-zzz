from __future__ import annotations

import datetime
import hashlib
import hmac
import os

import jwt
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password


def hash_password(raw: str) -> str:
    return make_password(raw)


def verify_password(raw: str, hashed: str) -> bool:
    return check_password(raw, hashed)


def create_access_token(user_id: str, is_staff: bool = False) -> str:
    now = datetime.datetime.utcnow()
    payload = {
        "sub": str(user_id),
        "staff": is_staff,
        "iat": now,
        "exp": now + datetime.timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
    )


def extract_user_id(request: object) -> str | None:
    headers = getattr(request, "headers", {}) or {}
    auth = headers.get("Authorization", "") or headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:]
    try:
        payload = decode_access_token(token)
        return payload.get("sub")
    except jwt.PyJWTError:
        return None


def extract_token_payload(request: object) -> tuple[str | None, bool]:
    """Returns (user_id, is_operator). is_operator is True when JWT staff=True."""
    headers = getattr(request, "headers", {}) or {}
    auth = headers.get("Authorization", "") or headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        return None, False
    token = auth[7:]
    try:
        payload = decode_access_token(token)
        return payload.get("sub"), bool(payload.get("staff", False))
    except jwt.PyJWTError:
        return None, False
