from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.factories.models import Factory, Department
from apps.machines.models import Machine


class IncidentSeverity(models.TextChoices):
    LOW = "LOW", _("Low (Minor Deviation)")
    MEDIUM = "MEDIUM", _("Medium (Moderate Anomaly)")
    HIGH = "HIGH", _("High (Production/Machine At Risk)")
    CRITICAL = "CRITICAL", _("Critical (Severe Stoppage / Failure Imminent)")


class IncidentStatus(models.TextChoices):
    OPEN = "OPEN", _("Open (Detected)")
    INVESTIGATING = "INVESTIGATING", _("Under Autonomous AI Investigation")
    MITIGATING = "MITIGATING", _("Action / Recovery in Progress")
    RESOLVED = "RESOLVED", _("Resolved")
    CLOSED = "CLOSED", _("Closed & Verified")


class IncidentCategory(models.TextChoices):
    MACHINE_HEALTH = "MACHINE_HEALTH", _("Machine Telemetry & Thermal/Vibration Anomaly")
    QUALITY_DEVIATION = "QUALITY_DEVIATION", _("Quality Defect Spike / CSP Loss")
    PRODUCTION_BOTTLENECK = "PRODUCTION_BOTTLENECK", _("Production Line Bottleneck")
    ENERGY_SPIKE = "ENERGY_SPIKE", _("Abnormal Energy Peak Demand")
    SAFETY = "SAFETY", _("Safety / Environmental Hazard")


class FactoryIncident(models.Model):
    """Factory operational incident detected by background monitors or AI."""
    incident_code = models.CharField(max_length=50, unique=True, help_text="e.g. INC-2026-0042")
    factory = models.ForeignKey(Factory, on_delete=models.CASCADE, related_name="incidents")
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="incidents")
    machine = models.ForeignKey(Machine, on_delete=models.SET_NULL, null=True, blank=True, related_name="incidents")
    severity = models.CharField(
        max_length=20, choices=IncidentSeverity.choices, default=IncidentSeverity.MEDIUM, db_index=True
    )
    status = models.CharField(
        max_length=30, choices=IncidentStatus.choices, default=IncidentStatus.OPEN, db_index=True
    )
    category = models.CharField(
        max_length=40, choices=IncidentCategory.choices, default=IncidentCategory.MACHINE_HEALTH
    )
    summary = models.CharField(max_length=255)
    root_cause_hypothesis = models.TextField(blank=True, default="")
    evidence_data = models.JSONField(default=dict, blank=True, help_text="Telemetry snapshots and historical context")
    detected_at = models.DateTimeField(auto_now_add=True, db_index=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolution_summary = models.TextField(blank=True, default="")
    is_autonomous_action_allowed = models.BooleanField(
        default=True, help_text="Whether AI agents may take low-risk automated action"
    )

    class Meta:
        ordering = ["-detected_at"]
        indexes = [
            models.Index(fields=["status", "severity"]),
            models.Index(fields=["machine", "status"]),
        ]

    def __str__(self):
        target = self.machine.code if self.machine else self.department.code
        return f"{self.incident_code} — {self.summary} [{target}] ({self.get_severity_display()})"


class AnomalyDetection(models.Model):
    """Granular anomaly event pinpointed by monitoring algorithms or LLM."""
    incident = models.ForeignKey(
        FactoryIncident, on_delete=models.SET_NULL, null=True, blank=True, related_name="anomalies"
    )
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="anomalies")
    telemetry_reading_id = models.BigIntegerField(null=True, blank=True)
    metric_name = models.CharField(max_length=100, help_text="e.g. temperature_c, vibration_mms, power_kw")
    observed_value = models.FloatField()
    threshold_value = models.FloatField()
    anomaly_score = models.FloatField(default=1.0, help_text="Deviation multiplier or z-score")
    confidence_pct = models.DecimalField(max_digits=5, decimal_places=2, default=95.00)
    algorithm_used = models.CharField(
        max_length=100,
        choices=[
            ("THRESHOLD_RULE", "Dynamic Threshold Rule"),
            ("STATISTICAL_ZSCORE", "Statistical Z-Score Filter"),
            ("ISOLATION_FOREST", "Isolation Forest ML"),
            ("LLM_EVALUATOR", "LLM Reasoning Evaluator"),
        ],
        default="THRESHOLD_RULE",
    )
    detected_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-detected_at"]

    def __str__(self):
        return f"Anomaly on {self.machine.code}: {self.metric_name}={self.observed_value} (Threshold: {self.threshold_value})"


class DetectionCheckpoint(models.Model):
    """Persistent processing checkpoint for the autonomous anomaly detection worker."""
    last_processed_telemetry_id = models.BigIntegerField(default=0)
    last_evaluated_at = models.DateTimeField(null=True, blank=True)
    total_telemetry_processed = models.PositiveIntegerField(default=0)
    total_anomalies_detected = models.PositiveIntegerField(default=0)
    total_incidents_created = models.PositiveIntegerField(default=0)
    is_worker_running = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    @classmethod
    def get_checkpoint(cls):
        checkpoint, _ = cls.objects.get_or_create(id=1)
        return checkpoint

    def __str__(self):
        return f"Detection Checkpoint: Last Telemetry ID #{self.last_processed_telemetry_id} ({self.total_anomalies_detected} anomalies)"


class WorkerHeartbeat(models.Model):
    """Real-time heartbeat and health registry for background worker daemons."""
    worker_name = models.CharField(max_length=64, unique=True, db_index=True)
    process_id = models.IntegerField(default=0)
    last_heartbeat_at = models.DateTimeField(auto_now=True, db_index=True)
    last_execution_at = models.DateTimeField(null=True, blank=True)
    last_error = models.TextField(blank=True, default="")
    status = models.CharField(max_length=30, default="RUNNING")  # RUNNING, STOPPED, DEGRADED, ERROR, UNKNOWN
    processing_count = models.PositiveIntegerField(default=0)
    metrics = models.JSONField(default=dict, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["worker_name"]

    @classmethod
    def record_heartbeat(
        cls,
        worker_name: str,
        process_id: int = 0,
        status: str = "RUNNING",
        last_error: str = "",
        increment_count: int = 0,
        metrics: dict = None,
    ):
        from django.utils import timezone
        now = timezone.now()
        obj, created = cls.objects.get_or_create(
            worker_name=worker_name,
            defaults={
                "process_id": process_id,
                "status": status,
                "started_at": now,
                "last_execution_at": now,
                "metrics": metrics or {},
            },
        )
        obj.process_id = process_id or obj.process_id
        obj.status = status
        obj.last_error = last_error
        obj.last_execution_at = now
        if increment_count > 0:
            obj.processing_count += increment_count
        if metrics:
            obj.metrics = metrics
        obj.save()
        return obj

    def is_stale(self, max_seconds: int = 15) -> bool:
        from django.utils import timezone
        if not self.last_heartbeat_at:
            return True
        return (timezone.now() - self.last_heartbeat_at).total_seconds() > max_seconds

    def computed_status(self, max_seconds: int = 15) -> str:
        if self.is_stale(max_seconds=max_seconds):
            return "STOPPED"
        if self.last_error:
            return "DEGRADED"
        return self.status or "RUNNING"

    def __str__(self):
        return f"Worker [{self.worker_name}] — Status: {self.computed_status()} (PID: {self.process_id})"
