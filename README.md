# Texora AI — Autonomous Textile Factory Operations Platform

Texora AI is an autonomous, multi-agent AI operations platform designed for smart textile factories. The platform continuously monitors machine telemetry, detects operational anomalies, automatically initiates multi-agent investigations, executes permitted corrective backend actions, requests managerial approvals for sensitive workflows, and provides a real-time command center interface.

---

## Architecture Overview

- **Frontend:** Flutter Web (Material 3, Desktop-first responsive layout, minimal white-and-navy executive theme)
- **Backend:** Python 3.14 + Django 5.2 + Django REST Framework
- **Database:** PostgreSQL (with SQLite support for isolated local development)
- **AI Agent System:** Multi-agent autonomous orchestrator with tool-calling capabilities and durable execution logging

---

## Repository Structure

```text
C:\Users\projects\texora-ai\
├── backend\
│   ├── apps\
│   │   └── core\                 # Core application & health endpoints
│   ├── config\
│   │   ├── settings\             # Modular settings (base, development, production)
│   │   ├── urls.py
│   │   ├── asgi.py
│   │   └── wsgi.py
│   ├── requirements\             # Dependencies (base, development, production)
│   ├── scripts\                  # Database setup & maintenance utilities
│   ├── tests\                    # Backend test suite (pytest)
│   ├── manage.py
│   └── .env.example
├── frontend\
│   ├── lib\
│   │   ├── core\                 # Themes, colors, app config
│   │   ├── data\                 # Models & API service
│   │   ├── presentation\         # Screens & widgets
│   │   └── main.dart
│   └── test\
├── docs\
│   ├── ENVIRONMENT_REPORT.md
│   ├── ARCHITECTURE.md
│   ├── SETUP_GUIDE.md
│   └── DEVELOPMENT_PROGRESS.md
├── .gitignore
└── README.md
```

---

## Quick Start (Local Development)

### 1. Backend Setup (Django)

```powershell
# Activate Python virtual environment
backend\.venv\Scripts\Activate.ps1

# Run system checks and migrations
python backend\manage.py check
python backend\manage.py migrate

# Run automated tests
pytest backend\tests

# Start Django Development Server (127.0.0.1:8000)
python backend\manage.py runserver 127.0.0.1:8000
```

### 2. Frontend Setup (Flutter Web)

```powershell
cd frontend

# Fetch dependencies & analyze
flutter pub get
flutter analyze
flutter test

# Run Flutter Web in Chrome
flutter run -d chrome
```

---

## API Health Check Endpoints

- **General API Health:** `GET http://127.0.0.1:8000/api/v1/health/`
- **Database Readiness:** `GET http://127.0.0.1:8000/api/v1/health/readiness/`
