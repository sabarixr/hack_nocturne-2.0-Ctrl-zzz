from __future__ import annotations

from typing import Any

from strawberry.channels import GraphQLWSConsumer

from apps.users.services import extract_token_payload


class AuthenticatedGraphqlWsConsumer(GraphQLWSConsumer):
    """GraphqlWsConsumer that authenticates via the connection_init payload.

    The Flutter client must send:
        {"type": "connection_init", "payload": {"Authorization": "Bearer <token>"}}
    """

    async def on_ws_connect(self, data: dict[str, Any]) -> Any:
        payload: dict[str, Any] = data or {}
        auth: str = payload.get("Authorization", "") or payload.get("authorization", "")

        class _FakeRequest:
            headers = {"Authorization": auth, "authorization": auth}

        user_id, is_operator = extract_token_payload(_FakeRequest())
        self.scope["user_id"] = user_id
        self.scope["is_operator"] = is_operator
        return await super().on_ws_connect(data)

    async def get_context(self, *args: Any, **kwargs: Any) -> Any:
        ctx = await super().get_context(*args, **kwargs)
        # ctx is a dict for Strawberry Channels; inject auth attributes
        ctx["user_id"] = self.scope.get("user_id")
        ctx["is_operator"] = self.scope.get("is_operator", False)

        # Attach a lightweight request-like object so HTTP permission classes
        # (IsAuthenticated, IsOperator) work unchanged for WS subscriptions.
        class _WSRequest:
            pass

        req = _WSRequest()
        req.user_id = ctx["user_id"]  # type: ignore[attr-defined]
        req.is_operator = ctx["is_operator"]  # type: ignore[attr-defined]
        ctx["request"] = req
        return ctx
