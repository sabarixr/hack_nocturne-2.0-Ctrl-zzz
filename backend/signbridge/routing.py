from django.urls import re_path
from shared.context import AuthenticatedGraphqlWsConsumer
from signbridge.schema import schema

websocket_urlpatterns = [
    re_path(r"^graphql$", AuthenticatedGraphqlWsConsumer.as_asgi(schema=schema)),
]
