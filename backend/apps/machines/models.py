from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.factories.models import Department, ProductionLine, DepartmentType


class MachineStatus(models.TextChoices):
    OPERATIONAL = "OPERATIONAL", _("Operational (Running Normal)")
    WARNING = "WARNING", _("Warning (Sub-optimal / Minor Anomaly)")
    CRITICAL = "CRITICAL", _("Critical (Severe Anomaly / Risk)")
    MAINTENANCE = "MAINTENANCE", _("Under Maintenance / Servicing")
    OFFLINE = "OFFLINE", _("Offline (Powered Down)")
    IDLE = "IDLE", _("Idle (Standby / Waiting Material)")


class MachineType(models.Model):
    """Categorizes textile machine types across spinning, weaving, knitting, dyeing, finishing."""
    category = models.CharField(
        max_length=50,
        choices=DepartmentType.choices,
        default=DepartmentType.SPINNING,
    )
    name = models.CharField(max_length=150, help_text="e.g. Ring Spinning Frame, Air Jet Loom")
    manufacturer = models.CharField(max_length=150, blank=True, default="Rieter / Toyota / Picanol")
    model_number = models.CharField(max_length=100, blank=True, default="")
    default_power_rating_kw = models.DecimalField(max_digits=8, decimal_places=2, default=45.00)
    description = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["category", "name"]

    def __str__(self):
        return f"{self.name} ({self.get_category_display()})"


class Machine(models.Model):
    """Represents a specific physical textile machine asset."""
    code = models.CharField(max_length=50, unique=True, help_text="e.g. SPN-RS-01, WEV-AJ-04")
    name = models.CharField(max_length=150)
    machine_type = models.ForeignKey(MachineType, on_delete=models.PROTECT, related_name="machines")
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="machines")
    production_line = models.ForeignKey(
        ProductionLine, on_delete=models.SET_NULL, null=True, blank=True, related_name="machines"
    )
    status = models.CharField(
        max_length=30,
        choices=MachineStatus.choices,
        default=MachineStatus.OPERATIONAL,
        db_index=True,
    )
    rated_speed_rpm = models.PositiveIntegerField(default=18000, help_text="Rated spindle / loom RPM")
    rated_capacity_units_per_hour = models.DecimalField(max_digits=10, decimal_places=2, default=50.00)
    current_health_score = models.DecimalField(
        max_digits=5, decimal_places=2, default=100.00, help_text="AI estimated health 0-100"
    )
    installation_date = models.DateField(null=True, blank=True)
    last_serviced_at = models.DateTimeField(null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["department", "code"]
        indexes = [
            models.Index(fields=["status", "department"]),
            models.Index(fields=["code"]),
        ]

    def __str__(self):
        return f"{self.code} — {self.name} [{self.get_status_display()}]"


class MachineOperatingLimits(models.Model):
    """Machine-specific sensor operating limits and anomaly threshold ranges."""
    machine = models.OneToOneField(Machine, on_delete=models.CASCADE, related_name="operating_limits")
    min_temp_c = models.FloatField(default=20.0)
    max_temp_c = models.FloatField(default=85.0)
    warning_temp_c = models.FloatField(default=75.0)
    max_vibration_mms = models.FloatField(default=5.5)
    warning_vibration_mms = models.FloatField(default=4.0)
    min_rpm = models.PositiveIntegerField(default=10000)
    max_rpm = models.PositiveIntegerField(default=22000)
    max_power_kw = models.FloatField(default=60.0)
    max_utilization_pct = models.FloatField(default=100.0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Limits for {self.machine.code} (Warn Temp: {self.warning_temp_c}C, Vib: {self.warning_vibration_mms}mm/s)"


class MachineTelemetry(models.Model):
    """High-frequency telemetry time-series storage for textile machinery."""
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="telemetry_readings")
    timestamp = models.DateTimeField(db_index=True)
    temperature_c = models.FloatField(null=True, blank=True)
    vibration_mms = models.FloatField(null=True, blank=True)
    speed_rpm = models.FloatField(null=True, blank=True)
    power_kw = models.FloatField(null=True, blank=True)
    utilization_pct = models.FloatField(null=True, blank=True)
    output_rate = models.FloatField(null=True, blank=True, help_text="Current units/kg per hour")
    operating_hours = models.FloatField(null=True, blank=True)
    status_flag = models.CharField(
        max_length=20,
        choices=[("NORMAL", "Normal"), ("WARNING", "Warning"), ("CRITICAL", "Critical")],
        default="NORMAL",
        db_index=True,
    )
    raw_sensor_data = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["machine", "-timestamp"]),
            models.Index(fields=["status_flag", "-timestamp"]),
        ]

    def __str__(self):
        return f"{self.machine.code} @ {self.timestamp.isoformat()} [{self.status_flag}]"


class MachineStateHistory(models.Model):
    """Audit trail of machine state transitions."""
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="state_history")
    previous_status = models.CharField(max_length=30, choices=MachineStatus.choices)
    new_status = models.CharField(max_length=30, choices=MachineStatus.choices)
    reason = models.TextField(blank=True, default="")
    trigger_source = models.CharField(
        max_length=50,
        choices=[("SYSTEM", "System Rule"), ("OPERATOR", "Manual Operator"), ("AI_AGENT", "Autonomous AI Agent")],
        default="SYSTEM",
    )
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)
    notes = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-timestamp"]

    def __str__(self):
        return f"{self.machine.code}: {self.previous_status} -> {self.new_status} at {self.timestamp}"
