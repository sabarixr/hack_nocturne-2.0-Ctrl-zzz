from __future__ import annotations

import strawberry
import strawberry_django  # noqa: F401
from strawberry_django.optimizer import DjangoOptimizerExtension

from apps.users.schema import AuthMutation, UserMutation, UserQuery
from apps.signs.schema import SignQuery
from apps.emergency.schema import EmergencyMutation, EmergencyQuery
from apps.emergency.subscriptions import EmergencySubscription
from apps.emergency.operator_schema import OperatorMutation, OperatorQuery
from apps.webrtc.schema import WebRTCMutation, WebRTCSubscription
from apps.practice.schema import PracticeMutation, PracticeQuery
from apps.bystander.schema import BystanderMutation, BystanderQuery


@strawberry.type
class Query(UserQuery, SignQuery, EmergencyQuery, PracticeQuery, BystanderQuery, OperatorQuery):
    @strawberry.field
    def health(self) -> str:
        return "ok"


@strawberry.type
class Mutation(AuthMutation, UserMutation, EmergencyMutation, WebRTCMutation, PracticeMutation, BystanderMutation, OperatorMutation):
    pass


@strawberry.type
class Subscription(EmergencySubscription, WebRTCSubscription):
    @strawberry.subscription
    async def ping(self) -> str:  # type: ignore[override,misc]
        yield "pong"  # type: ignore[misc]


schema = strawberry.Schema(
    query=Query,
    mutation=Mutation,
    subscription=Subscription,
    extensions=[DjangoOptimizerExtension],
)
