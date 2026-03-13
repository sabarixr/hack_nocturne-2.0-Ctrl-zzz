from __future__ import annotations

import strawberry


@strawberry.type
class NotFoundError:
    message: str


@strawberry.type
class PermissionDeniedError:
    message: str = "You do not have permission to perform this action"


@strawberry.type
class ValidationError:
    field: str
    message: str
