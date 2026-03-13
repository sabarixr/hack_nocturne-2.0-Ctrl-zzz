import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def env(key, default=None, cast=None):
    val = os.environ.get(key, default)
    if cast is not None and val is not None:
        if cast == bool:
            return str(val).lower() in ("true", "1", "yes")
        if cast == int:
            return int(val)
        if cast == list:
            return [v.strip() for v in str(val).split(",") if v.strip()]
        return cast(val)
    return val


SECRET_KEY = env("SECRET_KEY", "django-insecure-change-me")
DEBUG = env("DEBUG", "True", cast=bool)
ALLOWED_HOSTS = env("ALLOWED_HOSTS", "localhost,127.0.0.1,0.0.0.0", cast=list)

DJANGO_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "django.contrib.staticfiles",
]

THIRD_PARTY_APPS = [
    "channels",
    "strawberry_django",
    "corsheaders",
]

LOCAL_APPS = [
    "apps.users",
    "apps.emergency",
    "apps.webrtc",
    "apps.practice",
    "apps.signs",
    "apps.bystander",
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "signbridge.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
            ],
        },
    },
]

WSGI_APPLICATION = "signbridge.wsgi.application"
ASGI_APPLICATION = "signbridge.asgi.application"

_db_url: str = os.environ.get("DATABASE_URL", "postgresql://signbridge:signbridge@db:5432/signbridge")
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": _db_url.split("/")[-1],
        "USER": _db_url.split("//")[1].split(":")[0],
        "PASSWORD": _db_url.split(":")[2].split("@")[0],
        "HOST": _db_url.split("@")[1].split(":")[0],
        "PORT": _db_url.split("@")[1].split(":")[1].split("/")[0],
    }
}

REDIS_URL = env("REDIS_URL", "redis://redis:6379/0")

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {
            "hosts": [REDIS_URL],
        },
    },
}

AUTH_USER_MODEL = "users.User"

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

CORS_ALLOWED_ORIGINS = env("CORS_ALLOWED_ORIGINS", "http://localhost:3000", cast=list)
CORS_ALLOW_CREDENTIALS = True

JWT_SECRET_KEY = env("JWT_SECRET_KEY", "jwt-secret-change-me")
JWT_ALGORITHM = env("JWT_ALGORITHM", "HS256")
JWT_ACCESS_TOKEN_EXPIRE_MINUTES = env("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", "60", cast=int)

GEMINI_API_KEY = env("GEMINI_API_KEY", "")
BYPASS_MODEL = env("BYPASS_MODEL", "true", cast=bool)
TFLITE_MODEL_PATH = env("TFLITE_MODEL_PATH", "models/sign_classifier.tflite")
LSTM_MODEL_PATH = env("LSTM_MODEL_PATH", "models/sign_lstm.h5")

NOTIFY_EMERGENCY_CONTACTS = env("NOTIFY_EMERGENCY_CONTACTS", "false", cast=bool)
TWILIO_ACCOUNT_SID = env("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = env("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM_NUMBER = env("TWILIO_FROM_NUMBER", "")
TWILIO_FLOW_SID = env("TWILIO_FLOW_SID", "")

ENVIRONMENT = env("ENVIRONMENT", "development")
