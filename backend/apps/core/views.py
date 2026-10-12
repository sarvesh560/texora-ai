from datetime import datetime, timezone
import logging
from django.db import connection
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny

logger = logging.getLogger(__name__)


class HealthCheckView(APIView):
    """
    Public Health Check Endpoint.
    Returns general operational status of the Texora AI Backend API.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        return Response(
            {
                "status": "healthy",
                "service": "Texora AI Factory Operations Platform",
                "version": "1.0.0",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
            status=status.HTTP_200_OK,
        )


class ReadinessCheckView(APIView):
    """
    Database Readiness & Dependency Health Check Endpoint.
    Verifies that critical dependencies (PostgreSQL / SQLite database) are reachable.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        db_healthy = False
        db_message = "connected"

        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1;")
                row = cursor.fetchone()
                if row and row[0] == 1:
                    db_healthy = True
        except Exception as exc:
            logger.error("Database readiness check failed: %s", exc)
            db_message = "disconnected"

        response_data = {
            "status": "ready" if db_healthy else "degraded",
            "service": "Texora AI Factory Operations Platform",
            "dependencies": {
                "database": db_message,
            },
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

        http_status = status.HTTP_200_OK if db_healthy else status.HTTP_503_SERVICE_UNAVAILABLE
        return Response(response_data, status=http_status)


class WorkerHealthStatusView(APIView):
    """
    Comprehensive Background Worker & AI Subsystem Health API.
    Audits actual live daemon heartbeats, DB connectivity, Gemini provider status, and anomaly detector.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        from apps.incidents.models import WorkerHeartbeat
        from apps.ai_agents.llm_client import GeminiProvider
        import os

        # 1. Check Database
        db_connected = False
        db_err = ""
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1;")
                row = cursor.fetchone()
                if row and row[0] == 1:
                    db_connected = True
        except Exception as exc:
            db_err = str(exc)

        # 2. Check Gemini Provider
        gemini = GeminiProvider()
        gemini_configured = gemini.is_configured()
        gemini_model = gemini.model_name

        # 3. Retrieve Heartbeats
        heartbeats = {wb.worker_name: wb for wb in WorkerHeartbeat.objects.all()}

        def format_worker(name: str):
            wb = heartbeats.get(name)
            if not wb:
                return {
                    "name": name,
                    "status": "STOPPED",
                    "is_running": False,
                    "is_stale": True,
                    "last_heartbeat": None,
                    "last_execution": None,
                    "process_id": 0,
                    "processing_count": 0,
                    "last_error": "",
                    "metrics": {},
                }
            stale = wb.is_stale(max_seconds=15)
            comp_status = wb.computed_status(max_seconds=15)
            return {
                "name": name,
                "status": comp_status,
                "is_running": comp_status == "RUNNING",
                "is_stale": stale,
                "last_heartbeat": wb.last_heartbeat_at.isoformat() if wb.last_heartbeat_at else None,
                "last_execution": wb.last_execution_at.isoformat() if wb.last_execution_at else None,
                "process_id": wb.process_id,
                "processing_count": wb.processing_count,
                "last_error": wb.last_error,
                "metrics": wb.metrics,
            }

        anomaly_detector = format_worker("ANOMALY_DETECTOR")
        orchestrator = format_worker("AUTONOMOUS_ORCHESTRATOR")
        simulator = format_worker("TELEMETRY_SIMULATOR")

        # Determine aggregate system state
        all_workers_running = anomaly_detector["is_running"] and orchestrator["is_running"]
        overall_status = "RUNNING" if (db_connected and all_workers_running) else ("DEGRADED" if db_connected else "ERROR")

        return Response(
            {
                "overall_status": overall_status,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "service": "Texora AI Factory Intelligence Platform",
                "django_api": {
                    "status": "RUNNING",
                    "host": request.get_host(),
                    "environment": os.getenv("DJANGO_ENVIRONMENT", "production_ready"),
                },
                "database": {
                    "status": "CONNECTED" if db_connected else "DISCONNECTED",
                    "engine": "SQLite / PostgreSQL",
                    "error": db_err,
                },
                "gemini_provider": {
                    "status": "CONFIGURED" if gemini_configured else "UNCONFIGURED",
                    "model": gemini_model,
                    "fallback_ready": True,
                },
                "workers": {
                    "anomaly_detector": anomaly_detector,
                    "autonomous_orchestrator": orchestrator,
                    "telemetry_simulator": simulator,
                },
            },
            status=status.HTTP_200_OK,
        )
