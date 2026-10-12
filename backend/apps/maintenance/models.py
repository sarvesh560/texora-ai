from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.machines.models import Machine


class TicketPriority(models.TextChoices):
    LOW = "LOW", _("Low (Routine Check)")
    MEDIUM = "MEDIUM", _("Medium (Minor Issue)")
    HIGH = "HIGH", _("High (Impaired Performance)")
    CRITICAL = "CRITICAL", _("Critical (Machine Stoppage / Danger)")


class TicketStatus(models.TextChoices):
    CREATED = "CREATED", _("Created (Work Order Ready)")
    OPEN = "OPEN", _("Open (Created)")  # Backwards compatibility
    ASSIGNED = "ASSIGNED", _("Assigned to Technician")
    ACCEPTED = "ACCEPTED", _("Accepted by Technician")
    INSPECTION_IN_PROGRESS = "INSPECTION_IN_PROGRESS", _("Inspection In Progress")
    IN_PROGRESS = "IN_PROGRESS", _("In Progress")  # Backwards compatibility
    REPAIR_IN_PROGRESS = "REPAIR_IN_PROGRESS", _("Repair In Progress")
    PENDING_PARTS = "PENDING_PARTS", _("Pending Spare Parts")
    REPAIR_COMPLETED = "REPAIR_COMPLETED", _("Repair Completed (Awaiting Verification)")
    AWAITING_VERIFICATION = "AWAITING_VERIFICATION", _("Awaiting Recovery Verification")
    VERIFIED = "VERIFIED", _("Verified Healthy")
    RESOLVED = "RESOLVED", _("Resolved")  # Backwards compatibility
    CLOSED = "CLOSED", _("Closed & Signed Off")
    BLOCKED = "BLOCKED", _("Blocked")
    CANCELLED = "CANCELLED", _("Cancelled")
    VERIFICATION_FAILED = "VERIFICATION_FAILED", _("Recovery Verification Failed")


class VerificationStatus(models.TextChoices):
    PENDING_EVIDENCE = "PENDING_EVIDENCE", _("Pending Evidence")
    MONITORING = "MONITORING", _("Monitoring Sensor Telemetry")
    PASSED_TELEMETRY_CHECKS = "PASSED_TELEMETRY_CHECKS", _("Passed Telemetry Checks")
    FAILED = "FAILED", _("Verification Failed")
    INCONCLUSIVE = "INCONCLUSIVE", _("Inconclusive Telemetry")
    AWAITING_AUTHORIZED_SIGNOFF = "AWAITING_AUTHORIZED_SIGNOFF", _("Awaiting Authorized Sign-Off")
    VERIFIED = "VERIFIED", _("Recovery Verified")


class MaintenanceTicket(models.Model):
    """Work order ticket for machine maintenance and repair."""
    ticket_number = models.CharField(max_length=50, unique=True, help_text="e.g. MNT-2026-0089")
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="maintenance_tickets")
    incident_reference = models.CharField(
        max_length=100, blank=True, default="", db_index=True, help_text="Correlation ID with FactoryIncident"
    )
    title = models.CharField(max_length=200)
    description = models.TextField()
    priority = models.CharField(
        max_length=20, choices=TicketPriority.choices, default=TicketPriority.MEDIUM, db_index=True
    )
    status = models.CharField(
        max_length=35, choices=TicketStatus.choices, default=TicketStatus.CREATED, db_index=True
    )
    assigned_technician = models.CharField(max_length=150, blank=True, default="Mechanical Team")
    created_by_agent = models.CharField(
        max_length=100, blank=True, default="", help_text="Name of AI agent if auto-generated"
    )
    root_cause = models.TextField(blank=True, default="")
    corrective_action = models.TextField(blank=True, default="")
    parts_cost = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    labor_hours = models.DecimalField(max_digits=6, decimal_places=2, default=0.00)

    # Phase 12: AI Investigation & Technician Checklist
    ai_suspected_causes = models.JSONField(
        default=list, blank=True, help_text="List of potential causes presented as hypotheses, not confirmed diagnoses"
    )
    inspection_checklist = models.JSONField(
        default=list, blank=True, help_text="Configurable checklist items with status, measured values, and notes"
    )
    confirmed_fault = models.CharField(
        max_length=255, blank=True, default="", help_text="Physical fault confirmed by technician inspection"
    )
    fault_confirmation_notes = models.TextField(blank=True, default="")

    # Phase 12: Repair Documentation
    repair_performed = models.TextField(blank=True, default="", help_text="Detailed repair work carried out")
    parts_replaced = models.JSONField(
        default=list, blank=True, help_text="List of spare parts consumed with stock transaction correlation"
    )
    actual_repair_duration_minutes = models.PositiveIntegerField(default=0)
    remaining_issues = models.TextField(blank=True, default="", help_text="Any residual observations or pending tasks")
    repair_completed_at = models.DateTimeField(null=True, blank=True)

    # Phase 12: Post-Repair Verification & Governance
    verification_status = models.CharField(
        max_length=50,
        choices=VerificationStatus.choices,
        default=VerificationStatus.PENDING_EVIDENCE,
        db_index=True,
    )
    verification_summary = models.TextField(blank=True, default="")
    verification_data = models.JSONField(
        default=dict, blank=True, help_text="Multi-reading telemetry evaluation, baseline comparisons, and stability metrics"
    )
    authorized_signoff_by = models.CharField(max_length=150, blank=True, default="")
    authorized_signoff_at = models.DateTimeField(null=True, blank=True)
    signoff_notes = models.TextField(blank=True, default="")
    is_simulation = models.BooleanField(default=False, help_text="Whether this execution was conducted under demo simulation")

    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["status", "priority"]),
            models.Index(fields=["machine", "status"]),
            models.Index(fields=["verification_status"]),
        ]

    def __str__(self):
        return f"{self.ticket_number} — {self.title} [{self.get_status_display()}]"


class WorkOrderTransition(models.Model):
    """Immutable audit log of each lifecycle transition in a maintenance work order."""
    ticket = models.ForeignKey(MaintenanceTicket, on_delete=models.CASCADE, related_name="transitions")
    actor = models.CharField(max_length=150)
    actor_role = models.CharField(max_length=100, default="Technician")
    previous_state = models.CharField(max_length=50)
    new_state = models.CharField(max_length=50)
    incident_reference = models.CharField(max_length=100, blank=True, default="")
    reason = models.TextField(blank=True, default="")
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)
    audit_record_id = models.PositiveIntegerField(null=True, blank=True)

    class Meta:
        ordering = ["-timestamp"]

    def __str__(self):
        return f"Transition {self.ticket.ticket_number}: {self.previous_state} -> {self.new_state} by {self.actor}"


class WorkOrderAttachment(models.Model):
    """Photo or diagnostic attachment for inspection and repair evidence."""
    ticket = models.ForeignKey(MaintenanceTicket, on_delete=models.CASCADE, related_name="attachments")
    file_name = models.CharField(max_length=255)
    file_type = models.CharField(max_length=100, default="image/jpeg")
    file_size_bytes = models.PositiveIntegerField(default=0)
    file_url = models.CharField(max_length=500, blank=True, default="")
    caption = models.TextField(blank=True, default="")
    uploaded_by = models.CharField(max_length=150, default="Technician")
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-uploaded_at"]

    def __str__(self):
        return f"Attachment {self.file_name} on {self.ticket.ticket_number}"


class MaintenanceActivity(models.Model):
    """Specific repair task performed within a maintenance ticket."""
    ticket = models.ForeignKey(MaintenanceTicket, on_delete=models.CASCADE, related_name="activities")
    activity_type = models.CharField(
        max_length=50,
        choices=[
            ("INSPECTION", "Diagnostic Inspection"),
            ("REPLACEMENT", "Part Replacement"),
            ("LUBRICATION", "Bearing / Gear Lubrication"),
            ("CALIBRATION", "Sensor / Alignment Calibration"),
            ("CLEANING", "Fluff / Lint Deep Cleaning"),
        ],
        default="INSPECTION",
    )
    description = models.TextField()
    performed_by = models.CharField(max_length=150)
    duration_minutes = models.PositiveIntegerField(default=30)
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-timestamp"]


class MaintenanceHistory(models.Model):
    """Archived record of all historical machine service events."""
    machine = models.ForeignKey(Machine, on_delete=models.CASCADE, related_name="maintenance_history")
    ticket = models.ForeignKey(MaintenanceTicket, on_delete=models.SET_NULL, null=True, blank=True)
    maintenance_type = models.CharField(
        max_length=50,
        choices=[
            ("PREVENTIVE", "Preventive Schedule"),
            ("CORRECTIVE", "Corrective Repair"),
            ("EMERGENCY", "Emergency Stoppage"),
            ("PREDICTIVE_AI", "Predictive AI Triggered"),
        ],
    )
    summary = models.TextField()
    date_performed = models.DateTimeField()
    total_cost = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    downtime_minutes = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-date_performed"]

    def __str__(self):
        return f"{self.machine.code} Service ({self.date_performed.strftime('%Y-%m-%d')})"

