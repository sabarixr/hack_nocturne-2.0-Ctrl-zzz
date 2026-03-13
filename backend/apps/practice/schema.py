from __future__ import annotations

import datetime

import strawberry
import strawberry_django
from strawberry.types import Info

from apps.practice.models import PracticeSession, SignAttempt
from apps.practice.services import generate_feedback, run_inference
from apps.signs.models import Sign
from shared.auth import IsAuthenticated


@strawberry_django.type(PracticeSession)
class PracticeSessionType:
    id: strawberry.ID
    sign_id: strawberry.ID
    started_at: datetime.datetime
    ended_at: datetime.datetime | None
    is_completed: bool


@strawberry_django.type(SignAttempt)
class SignAttemptType:
    id: strawberry.ID
    session_id: strawberry.ID
    sign_id: strawberry.ID
    confidence: float
    predicted_label: str
    feedback: strawberry.scalars.JSON
    attempted_at: datetime.datetime


@strawberry.input
class StartPracticeInput:
    sign_id: strawberry.ID


@strawberry.input
class SubmitAttemptInput:
    session_id: strawberry.ID
    landmark_payload: str


@strawberry.type
class PracticeQuery:
    @strawberry.field(permission_classes=[IsAuthenticated])
    async def practice_sessions(self, info: Info) -> list[PracticeSessionType]:
        user_id = info.context.request.user_id
        return [
            s async for s in PracticeSession.objects.filter(user_id=user_id)
        ]  # type: ignore[return-value]

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def practice_session(
        self, info: Info, session_id: strawberry.ID
    ) -> PracticeSessionType | None:
        user_id = info.context.request.user_id
        try:
            return await PracticeSession.objects.aget(  # type: ignore[return-value]
                id=session_id, user_id=user_id
            )
        except PracticeSession.DoesNotExist:
            return None

    @strawberry.field(permission_classes=[IsAuthenticated])
    async def session_attempts(
        self, info: Info, session_id: strawberry.ID
    ) -> list[SignAttemptType]:
        user_id = info.context.request.user_id
        session = await PracticeSession.objects.aget(id=session_id, user_id=user_id)
        return [
            a async for a in SignAttempt.objects.filter(session=session)
        ]  # type: ignore[return-value]


@strawberry.type
class PracticeMutation:
    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def start_practice(
        self, info: Info, input: StartPracticeInput
    ) -> PracticeSessionType:
        user_id = info.context.request.user_id
        sign = await Sign.objects.aget(id=input.sign_id)
        session = await PracticeSession.objects.acreate(user_id=user_id, sign=sign)
        return session  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def submit_sign_attempt(
        self, info: Info, input: SubmitAttemptInput
    ) -> SignAttemptType:
        user_id = info.context.request.user_id
        session = await PracticeSession.objects.select_related("sign").aget(
            id=input.session_id, user_id=user_id
        )
        sign = session.sign

        result = run_inference(input.landmark_payload, sign.label)
        predicted_label: str = result["label"]
        confidence: float = result["confidence"]
        feedback = generate_feedback(predicted_label, sign.label, confidence)

        attempt = await SignAttempt.objects.acreate(
            session=session,
            sign=sign,
            confidence=confidence,
            predicted_label=predicted_label,
            landmark_payload=input.landmark_payload,
            feedback=feedback,
        )

        await _update_profile_accuracy(user_id)

        return attempt  # type: ignore[return-value]

    @strawberry.mutation(permission_classes=[IsAuthenticated])
    async def end_practice(self, info: Info, session_id: strawberry.ID) -> PracticeSessionType:
        user_id = info.context.request.user_id
        session = await PracticeSession.objects.aget(id=session_id, user_id=user_id)
        session.is_completed = True
        session.ended_at = datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc)
        await session.asave(update_fields=["is_completed", "ended_at"])
        return session  # type: ignore[return-value]


async def _update_profile_accuracy(user_id: str) -> None:
    from django.db.models import Avg

    avg = await SignAttempt.objects.filter(
        session__user_id=user_id
    ).aaggregate(avg=Avg("confidence"))
    accuracy = avg.get("avg") or 0.0

    from apps.users.models import User
    await User.objects.filter(id=user_id).aupdate(profile_accuracy=round(accuracy, 4))
