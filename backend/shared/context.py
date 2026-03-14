from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from strawberry.channels import GraphQLWSConsumer

from apps.users.services import extract_token_payload


@dataclass
class WSContext:
    """Context object for WebSocket connections.

    Mirrors the attribute-access API of StrawberryDjangoContext so that
    permission classes like IsAuthenticated (which do info.context.request.user_id)
    work identically for both HTTP and WS.
    """

    request: Any  # _WSRequest — has .user_id and .is_operator
    ws: Any       # the ChannelsWSConsumer instance
    user_id: Any = None
    is_operator: bool = False
    connection_params: Any = None

    # Allow dict-style access: info.context["ws"], info.context["request"], etc.
    def __getitem__(self, key: str) -> Any:
        return getattr(self, key)

    def __setitem__(self, key: str, value: Any) -> None:
        setattr(self, key, value)

    def get(self, key: str, default: Any = None) -> Any:
        return getattr(self, key, default)


class AuthenticatedGraphqlWsConsumer(GraphQLWSConsumer):
    """GraphqlWsConsumer that authenticates via the connection_init payload.

    The Flutter client must send:
        {"type": "connection_init", "payload": {"Authorization": "Bearer <token>"}}
    """

    async def get_context(self, request: Any, connection_params: Any) -> WSContext:
        # connection_params is the dict from the connection_init payload.
        # It contains {"Authorization": "Bearer <token>"}.
        params: dict[str, Any] = connection_params or {}
        auth: str = params.get("Authorization", "") or params.get("authorization", "")

        class _FakeRequest:
            pass

        fake = _FakeRequest()
        fake.headers = {"Authorization": auth, "authorization": auth}  # type: ignore[attr-defined]

        user_id, is_operator = extract_token_payload(fake)

        # Build a lightweight request-like object so HTTP permission classes
        # (IsAuthenticated, IsOperator) work unchanged for WS subscriptions.
        class _WSRequest:
            pass

        req = _WSRequest()
        req.user_id = user_id  # type: ignore[attr-defined]
        req.is_operator = is_operator  # type: ignore[attr-defined]

        return WSContext(
            request=req,
            ws=self,
            user_id=user_id,
            is_operator=is_operator,
            connection_params=params,
        )
