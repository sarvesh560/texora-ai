from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.factories.models import Department, ProductionLine
from apps.machines.models import Machine


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


class ProductionOrder(models.Model):
    """Customer textile production job order."""
    order_number = models.CharField(max_length=50, unique=True, help_text="e.g. ORD-2026-0891")
    client_name = models.CharField(max_length=200)
    fabric_or_yarn_spec = models.CharField(
        max_length=255, help_text="e.g. 100% Combed Cotton 40s Ring Spun / 220 GSM Single Jersey"
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
    start_date = models.DateField(null=True, blank=True)
    due_date = models.DateField(db_index=True)
    completed_at = models.DateTimeField(null=True, blank=True)
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


class ProductionBatch(models.Model):
    """Specific manufacturing run / lot linked to a production order."""
    batch_number = models.CharField(max_length=50, unique=True, help_text="e.g. BATCH-SPN-40S-001")
    production_order = models.ForeignKey(ProductionOrder, on_delete=models.CASCADE, related_name="batches")
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
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.batch_number} [{self.status}]"


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
