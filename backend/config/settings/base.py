"""
Texora AI - Base Django Settings
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Build paths inside the project like this: BASE_DIR / 'subdir'.
# BASE_DIR is 'backend/'
BASE_DIR = Path(__file__).resolve().parent.parent.parent

# Add apps folder to sys.path so apps can be registered and imported cleanly
sys.path.insert(0, str(BASE_DIR / "apps"))

# Load environment variables (.env in backend or root)
env_path = BASE_DIR / ".env"
if env_path.exists():
    load_dotenv(env_path)
else:
    root_env_path = BASE_DIR.parent / ".env"
    if root_env_path.exists():
        load_dotenv(root_env_path)

# Quick-start development settings - unsuitable for production
SECRET_KEY = os.getenv(
    "DJANGO_SECRET_KEY",
    "django-insecure-texora-ai-foundation-secret-key-change-in-production-2026",
)

DEBUG = os.getenv("DJANGO_DEBUG", "False").lower() in ("true", "1", "t", "yes")

# Allowed Hosts
allowed_hosts_raw = os.getenv("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost")
ALLOWED_HOSTS = [h.strip() for h in allowed_hosts_raw.split(",") if h.strip()]

# Application definition
DJANGO_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
]

THIRD_PARTY_APPS = [
    "rest_framework",
    "corsheaders",
]

LOCAL_APPS = [
    "apps.core.apps.CoreConfig",
    "apps.factories.apps.FactoriesConfig",
    "apps.machines.apps.MachinesConfig",
    "apps.production.apps.ProductionConfig",
    "apps.maintenance.apps.MaintenanceConfig",
    "apps.quality.apps.QualityConfig",
    "apps.inventory.apps.InventoryConfig",
    "apps.energy.apps.EnergyConfig",
    "apps.incidents.apps.IncidentsConfig",
    "apps.ai_agents.apps.AiAgentsConfig",
    "apps.approvals.apps.ApprovalsConfig",
    "apps.audit_logs.apps.AuditLogsConfig",
    "apps.simulation.apps.SimulationConfig",
    "apps.digital_twin.apps.DigitalTwinConfig",
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

# Database Configuration (Multi-engine support: sqlite | postgresql)
DB_ENGINE = os.getenv("DB_ENGINE", "sqlite").lower()

if DB_ENGINE == "postgresql":
    DB_NAME = os.getenv("DB_NAME", "texora_db")
    DB_USER = os.getenv("DB_USER", "texora_user")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
    DB_PORT = os.getenv("DB_PORT", "5432")

    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": DB_NAME,
            "USER": DB_USER,
            "PASSWORD": DB_PASSWORD,
            "HOST": DB_HOST,
            "PORT": DB_PORT,
            "CONN_MAX_AGE": 60,
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "texora_local.sqlite3",
            "OPTIONS": {
                "timeout": 60,
            },
        }
    }

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.CommonPasswordValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.NumericPasswordValidator",
    },
]

# Internationalization
LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Kolkata"
USE_I18N = True
USE_TZ = True

# Static files (CSS, JavaScript, Images)
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

# Default primary key field type
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Django REST Framework Settings
REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
        "rest_framework.renderers.BrowsableAPIRenderer",
    ],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.AllowAny",
    ],
    "EXCEPTION_HANDLER": "rest_framework.views.exception_handler",
}

# CORS Configuration
cors_raw = os.getenv(
    "CORS_ALLOWED_ORIGINS",
    "http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:50000,http://127.0.0.1:50000",
)
CORS_ALLOWED_ORIGINS = [origin.strip() for origin in cors_raw.split(",") if origin.strip()]
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOW_ALL_ORIGINS = False
