from django.urls import path
from strawberry.django.views import AsyncGraphQLView
from signbridge.schema import schema
from apps.users.services import extract_token_payload


class AuthenticatedGraphQLView(AsyncGraphQLView):
    async def get_context(self, request, response):
        ctx = await super().get_context(request, response)
        user_id, is_operator = extract_token_payload(request)
        request.user_id = user_id
        request.is_operator = is_operator
        return ctx


urlpatterns = [
    path("graphql", AuthenticatedGraphQLView.as_view(schema=schema)),
]
