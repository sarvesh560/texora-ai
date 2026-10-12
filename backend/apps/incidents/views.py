import logging
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import viewsets, permissions, status, views, filters
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import FactoryIncident, AnomalyDetection, DetectionCheckpoint, IncidentStatus, IncidentSeverity
from .serializers import FactoryIncidentSerializer, AnomalyDetectionSerializer, DetectionCheckpointSerializer
from .detector import AnomalyDetector
from apps.machines.models import Machine, MachineTelemetry
from apps.ai_agents.models import AutonomousWorkflowRun, RecoveryCase
from apps.approvals.models import ApprovalRequest
from apps.maintenance.models import MaintenanceTicket
from apps.audit_logs.models import AuditLog

logger = logging.getLogger(__name__)


class FactoryIncidentViewSet(viewsets.ModelViewSet):
    """API for querying and managing factory incidents."""
    queryset = (
        FactoryIncident.objects.select_related("factory", "department", "machine")
        .prefetch_related("anomalies")
        .all()
    )
    serializer_class = FactoryIncidentSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "machine", "severity", "status", "category"]
    search_fields = ["incident_code", "summary", "root_cause_hypothesis"]

    @action(detail=True, methods=["get"], url_path="intelligence")
    def intelligence(self, request, pk=None):
        """Returns deep enterprise intelligence workspace data for an incident."""
        incident = self.get_object()
        machine = incident.machine

        # 1. Telemetry & Operating limits
        latest_tel = None
        telemetry_history = []
        limits_data = {}
        if machine:
            tel_qs = MachineTelemetry.objects.filter(machine=machine).order_by("-timestamp")[:20]
            if tel_qs.exists():
                latest_tel = {
                    "timestamp": tel_qs[0].timestamp.isoformat(),
                    "vibration_mms": tel_qs[0].vibration_mms,
                    "temperature_c": tel_qs[0].temperature_c,
                    "speed_rpm": tel_qs[0].speed_rpm,
                    "power_kw": tel_qs[0].power_kw,
                    "status_flag": tel_qs[0].status_flag,
                    "age_seconds": (timezone.now() - tel_qs[0].timestamp).total_seconds(),
                }
                telemetry_history = [
                    {
                        "timestamp": t.timestamp.isoformat(),
                        "vibration_mms": t.vibration_mms,
                        "temperature_c": t.temperature_c,
                        "speed_rpm": t.speed_rpm,
                        "power_kw": t.power_kw,
                    }
                    for t in reversed(tel_qs)
                ]
            limits = getattr(machine, "operating_limits", None) or getattr(machine, "limits", None)
            if limits:
                limits_data = {
                    "warning_temp_c": getattr(limits, "warning_temp_c", 75.0),
                    "max_temp_c": getattr(limits, "max_temp_c", 85.0),
                    "warning_vibration_mms": getattr(limits, "warning_vibration_mms", 4.0),
                    "max_vibration_mms": getattr(limits, "max_vibration_mms", 5.5),
                    "min_rpm": getattr(limits, "min_rpm", 500.0),
                    "max_rpm": getattr(limits, "max_rpm", 750.0),
                }

        # 2. Workflow run
        workflow_run = AutonomousWorkflowRun.objects.filter(incident=incident).order_by("-started_at").first()
        workflow_data = None
        if workflow_run:
            from apps.ai_agents.serializers import AutonomousWorkflowRunSerializer
            workflow_data = AutonomousWorkflowRunSerializer(workflow_run).data

        # 3. Recovery case
        recovery_case = RecoveryCase.objects.filter(incident=incident).order_by("-created_at").first()
        recovery_data = None
        if recovery_case:
            from apps.ai_agents.serializers import RecoveryCaseSerializer
            recovery_data = RecoveryCaseSerializer(recovery_case).data

        # 4. Approvals
        approvals = ApprovalRequest.objects.filter(incident=incident).order_by("-created_at")
        from apps.approvals.serializers import ApprovalRequestSerializer
        approvals_data = ApprovalRequestSerializer(approvals, many=True).data

        # 5. Audit logs
        from apps.audit_logs.serializers import AuditLogSerializer
        logs = AuditLog.objects.filter(
            Q(entity_id=incident.incident_code) |
            Q(changes_payload__incident_code=incident.incident_code) |
            Q(entity_id=f"REC-{recovery_case.id}" if recovery_case else "N/A")
        ).order_by("-timestamp")[:30]
        audit_data = AuditLogSerializer(logs, many=True).data

        # 6. Maintenance ticket if any
        from apps.maintenance.serializers import MaintenanceTicketSerializer
        tickets = MaintenanceTicket.objects.filter(
            Q(incident=incident) | Q(incident_reference=incident.incident_code)
        ).order_by("-created_at")
        ticket_data = MaintenanceTicketSerializer(tickets, many=True).data

        return Response({
            "incident": FactoryIncidentSerializer(incident).data,
            "machine": {
                "id": machine.id if machine else None,
                "code": machine.code if machine else None,
                "name": machine.name if machine else None,
                "department": machine.department.name if machine else None,
                "status": machine.status if machine else None,
                "rated_speed_rpm": machine.rated_speed_rpm if machine else None,
                "operating_limits": limits_data,
                "latest_telemetry": latest_tel,
                "telemetry_history": telemetry_history,
            },
            "workflow_run": workflow_data,
            "recovery_case": recovery_data,
            "recommendation_payload": workflow_run.recommendation_payload if workflow_run else (recovery_case.recommendation_payload if recovery_case else {}),
            "approval_requests": approvals_data,
            "work_orders": ticket_data,
            "audit_trail": audit_data,
        })

    @action(detail=True, methods=["post"])
    def resolve(self, request, pk=None):
        """Manually marks an incident as resolved with notes."""
        incident = self.get_object()
        notes = request.data.get("resolution_notes", "Manually marked as resolved by operator.")
        incident.status = IncidentStatus.RESOLVED
        incident.resolved_at = timezone.now()
        incident.resolution_summary = notes
        incident.save(update_fields=["status", "resolved_at", "resolution_summary"])
        return Response(FactoryIncidentSerializer(incident).data)


class AnomalyDetectionViewSet(viewsets.ModelViewSet):
    """API for granular anomaly events captured from telemetry."""
    queryset = AnomalyDetection.objects.select_related("incident", "machine", "machine__department").all()
    serializer_class = AnomalyDetectionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "incident", "metric_name", "algorithm_used"]


class DetectorStatusView(views.APIView):
    """Returns current state and statistics of the autonomous anomaly detector."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        checkpoint = DetectionCheckpoint.get_checkpoint()
        detector = AnomalyDetector()
        return Response({
            "checkpoint": DetectionCheckpointSerializer(checkpoint).data,
            "is_thread_alive": detector.is_active(),
            "active_incidents_count": FactoryIncident.objects.filter(
                status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]
            ).count(),
        })


class DetectorRunEvalView(views.APIView):
    """Triggers a single discrete evaluation cycle across new telemetry."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        batch_size = int(request.data.get("batch_size", 100))
        detector = AnomalyDetector()
        result = detector.run_cycle(batch_size=batch_size)
        checkpoint = DetectionCheckpoint.get_checkpoint()
        return Response({
            "message": "Anomaly detection cycle executed.",
            "result": result,
            "checkpoint": DetectionCheckpointSerializer(checkpoint).data,
        }, status=status.HTTP_200_OK)


class IncidentsSummaryView(views.APIView):
    """Operational summary of active incidents, severity counts, and recent anomalies."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        active_incidents = FactoryIncident.objects.filter(
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING]
        ).select_related("machine", "department").order_by("-detected_at")

        severity_counts = {
            "CRITICAL": FactoryIncident.objects.filter(severity=IncidentSeverity.CRITICAL, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]).count(),
            "HIGH": FactoryIncident.objects.filter(severity=IncidentSeverity.HIGH, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]).count(),
            "MEDIUM": FactoryIncident.objects.filter(severity=IncidentSeverity.MEDIUM, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]).count(),
            "LOW": FactoryIncident.objects.filter(severity=IncidentSeverity.LOW, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]).count(),
        }

        status_counts = {
            "OPEN": FactoryIncident.objects.filter(status=IncidentStatus.OPEN).count(),
            "INVESTIGATING": FactoryIncident.objects.filter(status=IncidentStatus.INVESTIGATING).count(),
            "MITIGATING": FactoryIncident.objects.filter(status=IncidentStatus.MITIGATING).count(),
            "RESOLVED": FactoryIncident.objects.filter(status=IncidentStatus.RESOLVED).count(),
            "CLOSED": FactoryIncident.objects.filter(status=IncidentStatus.CLOSED).count(),
        }

        recent_anomalies = AnomalyDetection.objects.select_related("machine", "incident").order_by("-detected_at")[:15]
        checkpoint = DetectionCheckpoint.get_checkpoint()

        return Response({
            "total_active_incidents": active_incidents.count(),
            "severity_breakdown": severity_counts,
            "status_breakdown": status_counts,
            "checkpoint": DetectionCheckpointSerializer(checkpoint).data,
            "active_incidents": FactoryIncidentSerializer(active_incidents, many=True).data,
            "recent_anomalies": AnomalyDetectionSerializer(recent_anomalies, many=True).data,
        })
