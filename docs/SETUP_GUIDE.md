# Texora AI — Setup & Developer Guide

## Prerequisites

- **Windows 11 Pro 64-bit**
- **Flutter SDK:** 3.47.2+
- **Python:** 3.14+
- **PostgreSQL:** 18.6+ (or local SQLite for lightweight development)
- **Google Chrome:** For Flutter Web debugging and Expo presentations

---

## 1. Environment Configuration

### Root & Backend `.env`

Copy `.env.example` to `backend/.env`:

```ini
DJANGO_SECRET_KEY=django-insecure-texora-ai-foundation-secret-key-change-in-production-2026
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost

# Database Engine: 'sqlite' (default for rapid local setup) or 'postgresql'
DB_ENGINE=sqlite

# PostgreSQL Configuration (used when DB_ENGINE=postgresql)
DB_NAME=texora_db
DB_USER=texora_user
DB_PASSWORD=your_secure_password
DB_HOST=127.0.0.1
DB_PORT=5432

CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:50000,http://127.0.0.1:50000
```

---

## 2. Windows PowerShell Commands Cheatsheet

### Python & Django Backend

```powershell
# 1. Activate Python virtual environment
backend\.venv\Scripts\Activate.ps1

# 2. Install dependencies
pip install -r backend\requirements\development.txt

# 3. Verify Django system checks
python backend\manage.py check

# 4. Run database migrations
python backend\manage.py migrate

# 5. Run backend pytest suite
pytest backend\tests

# 6. Start Django development server
python backend\manage.py runserver 127.0.0.1:8000
```

### PostgreSQL Database Configuration (Optional / Phase 2)

```powershell
# Run the secure, interactive database setup script
powershell -ExecutionPolicy Bypass -File backend\scripts\configure_database.ps1
```

### Flutter Web Frontend

```powershell
cd frontend

# 1. Install Flutter dependencies
flutter pub get

# 2. Analyze code for lints & errors
flutter analyze

# 3. Run Flutter widget and unit tests
flutter test

# 4. Build optimized Web bundle
flutter build web

# 5. Launch Flutter Web with Chrome
flutter run -d chrome
```
