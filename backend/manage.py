#!/usr/bin/env python
"""Django's command-line utility for administrative tasks."""
import os
import sys
from pathlib import Path
from dotenv import load_dotenv


def main():
    """Run administrative tasks."""
    # Load environment variables from .env file at backend root or workspace root
    base_dir = Path(__file__).resolve().parent
    env_file = base_dir / ".env"
    if env_file.exists():
        load_dotenv(env_file)
    else:
        root_env = base_dir.parent / ".env"
        if root_env.exists():
            load_dotenv(root_env)

    # Use development settings by default if DJANGO_SETTINGS_MODULE is not set
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.development")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed and "
            "available on your PYTHONPATH environment variable? Did you "
            "forget to activate a virtual environment?"
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
