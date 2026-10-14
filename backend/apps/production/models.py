from django.db import models
from django.utils import timezone
from django.utils.translation import gettext_lazy as _
from apps.factories.models import Department, ProductionLine
from apps.machines.models import Machine
from apps.incidents.models import FactoryIncident


class OrderStatus(models.TextChoices):
    PLANNED = "PLANNED", _("Planned (Queued)")
    IN_PROGRESS = "IN_PROGRESS", _("In Progress (Active)")
    PAUSED = "PAUSED", _("Paused (Bottle-necked / Delayed)")
    COMPLETED = "COMPLETED", _("Completed")
    CANCELLED = "CANCELLED", _("Cancelled")


class OrderPriority(models.TextChoices):
    LOW = "LOW", _("Low Priority")
    MEDIUM = "MEDIUM", _("Medium Priority")
    HIGH = "HIGH", _("High Priority")
    URGENT = "URGENT", _("Urgent / Rush Order")


class DelayRiskLevel(models.TextChoices):
    LOW = "LOW", _("Low Risk (On Schedule)")
    MEDIUM = "MEDIUM", _("Medium Risk (Tight Buffer)")
    HIGH = "HIGH", _("High Risk (Imminent Delay)")
    CRITICAL = "CRITICAL", _("Critical Risk (Overdue / Stalled)")


class ProductionOrder(models.Model):
    """Customer textile production job order with routing and delay risk tracking."""
    order_number = models.CharField(max_length=50, unique=True, help_text="e.g. ORD-2026-0891")
    client_name = models.CharField(max_length=200)
    customer_po_number = models.CharField(max_length=100, blank=True, default="", help_text="Customer Purchase Order #")
    fabric_or_yarn_spec = models.CharField(
        max_length=255, help_text="e.g. 100% Combed Cotton 40s Ring Spun / 220 GSM Single Jersey"
    )
    product_category = models.CharField(
        max_length=50,
        blank=True,
        default="COMBED_YARN",
        help_text="Product grouping e.g. COMBED_YARN, GREIGE_FABRIC, FINISHED_DENIM, SINGLE_JERSEY, SHIRTING",
    )
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="production_orders")
    target_quantity = models.DecimalField(max_digits=12, decimal_places=2, help_text="Target amount")
    unit = models.CharField(
        max_length=20,
        choices=[("KG", "Kilograms"), ("METERS", "Meters"), ("PIECES", "Pieces"), ("ROLLS", "Rolls")],
        default="KG",
    )
    completed_quantity = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    status = models.CharField(max_length=30, choices=OrderStatus.choices, default=OrderStatus.PLANNED, db_index=True)
    priority = models.CharField(max_length=20, choices=OrderPriority.choices, default=OrderPriority.MEDIUM)
    
    # Textile Process Routing: e.g. ["SPN", "WEV", "DYE", "FIN", "QC", "DISPATCH"]
    routing_stages = models.JSONField(
        default=list,
        blank=True,
        help_text="Configurable sequence of department codes or stages e.g. ['SPN', 'WEV', 'DYE', 'FIN', 'QC', 'DISPATCH']",
    )
    current_stage = models.CharField(max_length=50, blank=True, default="Spinning")
    
    # Schedule & Due Date Commitments
    start_date = models.DateField(null=True, blank=True)
    due_date = models.DateField(db_index=True)
    target_delivery_date = models.DateField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    
    # Capacity Intelligence & Risk Predictions
    estimated_remaining_hours = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    projected_completion_date = models.DateField(null=True, blank=True)
    delay_risk_score = models.DecimalField(max_digits=5, decimal_places=2, default=0.00, help_text="0-100 risk score")
    delay_risk_level = models.CharField(
        max_length=20,
        choices=DelayRiskLevel.choices,
        default=DelayRiskLevel.LOW,
        db_index=True,
    )
    estimated_delay_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0.00)
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-due_date", "-priority"]

    def __str__(self):
        return f"{self.order_number} — {self.client_name} ({self.fabric_or_yarn_spec})"

    @property
    def progress_pct(self):
        if self.target_quantity and self.target_quantity > 0:
            return min(100.0, float((self.completed_quantity / self.target_quantity) * 100))
        return 0.0

    @property
    def remaining_quantity(self):
        if self.target_quantity:
            return max(0.0, float(self.target_quantity - self.completed_quantity))
        return 0.0


class ProductionBatch(models.Model):
    """Specific manufacturing run / lot linked to a production order and machine asset."""
    batch_number = models.CharField(max_length=50, unique=True, help_text="e.g. BATCH-SPN-40S-001")
    production_order = models.ForeignKey(ProductionOrder, on_delete=models.CASCADE, related_name="batches")
    department = models.ForeignKey(Department, on_delete=models.SET_NULL, null=True, blank=True, related_name="batches")
    stage_name = models.CharField(max_length=100, blank=True, default="Processing")
    machine = models.ForeignKey(Machine, on_delete=models.SET_NULL, null=True, blank=True, related_name="batches")
    planned_quantity = models.DecimalField(max_digits=10, decimal_places=2)
    actual_quantity = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    defect_quantity = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    status = models.CharField(
        max_length=30,
        choices=[
            ("STAGED", "Staged"),
            ("RUNNING", "Running"),
            ("PAUSED", "Paused"),
            ("COMPLETED", "Completed"),
            ("REJECTED", "Rejected"),
        ],
        default="STAGED",
    )
    effective_speed_pct = models.DecimalField(max_digits=5, decimal_places=2, default=100.00)
    target_completion_date = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.batch_number} [{self.status}]"

    @property
    def progress_pct(self):
        if self.planned_quantity and self.planned_quantity > 0:
            return min(100.0, float((self.actual_quantity / self.planned_quantity) * 100))
        return 0.0


class ProductionSchedule(models.Model):
    """Machine assignment calendar for factory shifts."""
    production_order = models.ForeignKey(ProductionOrder, on_delete=models.CASCADE, related_name="schedules")
    production_line = models.ForeignKey(ProductionLine, on_delete=models.CASCADE, related_name="schedules")
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="schedules")
    scheduled_start = models.DateTimeField()
    scheduled_end = models.DateTimeField()
    shift = models.CharField(
        max_length=30,
        choices=[
            ("SHIFT_1", "Morning Shift (06:00 - 14:00)"),
            ("SHIFT_2", "Evening Shift (14:00 - 22:00)"),
            ("SHIFT_3", "Night Shift (22:00 - 06:00)"),
        ],
        default="SHIFT_1",
    )
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f"Schedule: {self.machine.code} for {self.production_order.order_number} ({self.shift})"


class MachineProductionAssignment(models.Model):
    """Active or planned binding between a machine asset and production order/batch."""
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="production_assignments")
    production_order = models.ForeignKey(ProductionOrder, on_delete=models.CASCADE, related_name="machine_assignments")
    production_batch = models.ForeignKey(
        ProductionBatch, on_delete=models.CASCADE, null=True, blank=True, related_name="machine_assignments"
    )
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="machine_assignments")
    stage_name = models.CharField(max_length=100, default="Production")
    status = models.CharField(
        max_length=30,
        choices=[
            ("ASSIGNED", "Assigned (Scheduled)"),
            ("RUNNING", "Running (In Production)"),
            ("COMPLETED", "Completed"),
            ("INTERRUPTED", "Interrupted (Machine Breakdown / Hold)"),
            ("CANCELLED", "Cancelled / Rerouted"),
        ],
        default="ASSIGNED",
    )
    shift = models.CharField(max_length=30, default="SHIFT_1")
    assigned_at = models.DateTimeField(auto_now_add=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    planned_run_hours = models.DecimalField(max_digits=8, decimal_places=2, default=8.00)
    actual_run_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0.00)
    speed_override_rpm = models.PositiveIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-assigned_at"]

    def __str__(self):
        return f"{self.machine.code} -> {self.production_order.order_number} [{self.status}]"


class ProductionProgress(models.Model):
    """Continuous or shift-level production output checkpoint for orders and lines."""
    production_order = models.ForeignKey(ProductionOrder, on_delete=models.CASCADE, related_name="progress_records")
    production_batch = models.ForeignKey(
        ProductionBatch, on_delete=models.SET_NULL, null=True, blank=True, related_name="progress_records"
    )
    machine = models.ForeignKey(Machine, on_delete=models.SET_NULL, null=True, blank=True, related_name="progress_records")
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="progress_records")
    stage_name = models.CharField(max_length=100, default="Production")
    recorded_at = models.DateTimeField(auto_now_add=True, db_index=True)
    quantity_produced = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    cumulative_quantity = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    scrap_or_defect_quantity = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    efficiency_pct = models.DecimalField(max_digits=5, decimal_places=2, default=100.00)
    stage_status = models.CharField(max_length=30, default="IN_PROGRESS")
    notes = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-recorded_at"]

    def __str__(self):
        return f"Progress: {self.production_order.order_number} +{self.quantity_produced} ({self.stage_name})"


class ProductionCapacityProfile(models.Model):
    """Factory department capacity snapshot and utilization intelligence."""
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="capacity_profiles")
    period_date = models.DateField(default=timezone.now, db_index=True)
    shift = models.CharField(max_length=30, default="ALL_DAY")
    total_machines_count = models.PositiveIntegerField(default=0)
    active_machines_count = models.PositiveIntegerField(default=0)
    down_machines_count = models.PositiveIntegerField(default=0)
    nominal_capacity_units = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    effective_capacity_units = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    allocated_capacity_units = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    actual_produced_units = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    utilization_pct = models.DecimalField(max_digits=5, decimal_places=2, default=0.00)
    downtime_loss_units = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    bottleneck_severity = models.CharField(
        max_length=30,
        choices=[("NORMAL", "Normal"), ("MODERATE", "Moderate"), ("SEVERE", "Severe"), ("CRITICAL", "Critical")],
        default="NORMAL",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-period_date", "department"]
        unique_together = ("department", "period_date", "shift")

    def __str__(self):
        return f"Capacity: {self.department.code} on {self.period_date} ({self.utilization_pct}%)"


class ProductionBottleneck(models.Model):
    """Detected production bottleneck identifying overloaded or stalled factory stages."""
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="bottlenecks")
    machine = models.ForeignKey(Machine, on_delete=models.SET_NULL, null=True, blank=True, related_name="bottlenecks")
    identified_at = models.DateTimeField(auto_now_add=True, db_index=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    severity = models.CharField(
        max_length=20,
        choices=[("LOW", "Low"), ("MEDIUM", "Medium"), ("HIGH", "High"), ("CRITICAL", "Critical")],
        default="MEDIUM",
    )
    bottleneck_type = models.CharField(
        max_length=50,
        choices=[
            ("MACHINE_DOWNTIME", "Machine Breakdown / Critical Alarm"),
            ("CAPACITY_OVERLOAD", "Capacity Overload / High Utilization"),
            ("QUALITY_REJECT_BACKLOG", "Quality Rejection Spike"),
            ("STAGE_STARVATION", "Upstream Material Starvation"),
            ("MAINTENANCE_HOLD", "Scheduled Maintenance Interruption"),
        ],
        default="CAPACITY_OVERLOAD",
    )
    primary_cause = models.TextField()
    affected_orders_count = models.PositiveIntegerField(default=0)
    estimated_delay_impact_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0.00)
    throughput_deficit_units_per_hour = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    is_active = models.BooleanField(default=True, db_index=True)

    class Meta:
        ordering = ["-is_active", "-identified_at"]

    def __str__(self):
        return f"Bottleneck: {self.department.code} - {self.get_bottleneck_type_display()} [{self.severity}]"


class ProductionImpactAssessment(models.Model):
    """
    Deterministic & AI-assisted operational impact assessment on production orders
    triggered by machine breakdown, critical incidents, or downtime events.
    """
    assessment_code = models.CharField(max_length=50, unique=True, help_text="e.g. PIA-20261013-001")
    incident = models.ForeignKey(
        FactoryIncident,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="production_impact_assessments",
    )
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="production_impact_assessments")
    assessed_at = models.DateTimeField(auto_now_add=True, db_index=True)
    estimated_downtime_hours = models.DecimalField(max_digits=8, decimal_places=2, default=1.50)
    output_quantity_at_risk = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    orders_affected_count = models.PositiveIntegerField(default=0)
    affected_orders = models.JSONField(default=list, blank=True)
    affected_batches = models.JSONField(default=list, blank=True)
    alternate_capacities = models.JSONField(default=list, blank=True)
    overall_delay_risk = models.CharField(
        max_length=20,
        choices=DelayRiskLevel.choices,
        default=DelayRiskLevel.MEDIUM,
    )
    ai_explanation = models.TextField(blank=True, default="")
    deterministic_loss_inr = models.DecimalField(max_digits=14, decimal_places=2, default=0.00)
    recommendations = models.JSONField(default=list, blank=True)
    is_latest = models.BooleanField(default=True, db_index=True)

    class Meta:
        ordering = ["-assessed_at"]

    def __str__(self):
        return f"{self.assessment_code} on {self.machine.code} ({self.overall_delay_risk})"


class ProductionOutput(models.Model):
    """Recorded batch output from a machine at regular intervals."""
    production_batch = models.ForeignKey(ProductionBatch, on_delete=models.CASCADE, related_name="outputs")
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="outputs")
    timestamp = models.DateTimeField(auto_now_add=True)
    quantity_produced = models.DecimalField(max_digits=10, decimal_places=2)
    unit = models.CharField(max_length=20, default="KG")
    scrap_quantity = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    operator_notes = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-timestamp"]


class ProductionDelay(models.Model):
    """Recorded delay or bottleneck impact event on production orders."""
    production_order = models.ForeignKey(ProductionOrder, on_delete=models.CASCADE, related_name="delays")
    production_batch = models.ForeignKey(ProductionBatch, on_delete=models.SET_NULL, null=True, blank=True)
    machine = models.ForeignKey(Machine, on_delete=models.SET_NULL, null=True, blank=True)
    delay_reason = models.CharField(
        max_length=50,
        choices=[
            ("MACHINE_BREAKDOWN", "Machine Breakdown / Alarm"),
            ("QUALITY_ISSUE", "Quality Rejection / Off-spec"),
            ("MATERIAL_SHORTAGE", "Yarn / Raw Material Shortage"),
            ("POWER_FAILURE", "Power Grid / Energy Interruption"),
            ("OPERATOR_UNAVAILABLE", "Operator Shortage"),
        ],
    )
    estimated_delay_minutes = models.PositiveIntegerField(default=60)
    impact_summary = models.TextField()
    recorded_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-recorded_at"]

    def __str__(self):
        return f"Delay: {self.production_order.order_number} ({self.get_delay_reason_display()})"
