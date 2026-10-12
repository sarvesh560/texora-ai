"""
ASGI config for Texora AI project.
"""

import os
from pathlib import Path
from dotenv import load_dotenv
from django.core.asgi import get_asgi_application

base_dir = Path(__file__).resolve().parent.parent
env_file = base_dir / ".env"
if env_file.exists():
    load_dotenv(env_file)
else:
    root_env = base_dir.parent / ".env"
    if root_env.exists():
        load_dotenv(root_env)

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.development")

application = get_asgi_application()
