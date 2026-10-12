from django.db import models
from django.utils.translation import gettext_lazy as _


class AuditLog(models.Model):
    """Immutable audit trail for every operational, maintenance, and AI decision."""
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)
    entity_type = models.CharField(
        max_length=50,
        choices=[
            ("MACHINE", "Machine"),
            ("TICKET", "Maintenance Ticket"),
            ("ORDER", "Production Order"),
            ("BATCH", "Production Batch"),
            ("INCIDENT", "Factory Incident"),
            ("AGENT", "AI Agent Execution"),
            ("APPROVAL", "Manager Approval"),
            ("INVENTORY", "Inventory Item"),
        ],
        db_index=True,
    )
    entity_id = models.CharField(max_length=100, db_index=True)
    action = models.CharField(
        max_length=50,
        choices=[
            ("CREATE", "Entity Created"),
            ("UPDATE", "Entity Updated"),
            ("STATUS_CHANGE", "Status Changed"),
            ("TELEMETRY_ANOMALY", "Anomaly Flagged"),
            ("AI_AGENT_ACTION", "Autonomous Action Executed"),
            ("APPROVAL_GRANTED", "Approval Granted"),
            ("APPROVAL_REJECTED", "Approval Rejected"),
        ],
    )
    actor_type = models.CharField(
        max_length=30,
        choices=[
            ("SYSTEM", "Automated Background Daemon"),
            ("AI_AGENT", "Autonomous AI Agent"),
            ("OPERATOR", "Floor Operator"),
            ("MANAGER", "Factory Manager"),
        ],
        default="SYSTEM",
    )
    actor_id = models.CharField(max_length=150, default="system_daemon")
    changes_payload = models.JSONField(default=dict, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    description = models.TextField()

    class Meta:
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["entity_type", "entity_id"]),
            models.Index(fields=["actor_type", "-timestamp"]),
        ]

    def __str__(self):
        return f"Audit: [{self.entity_type}:{self.entity_id}] {self.action} by {self.actor_id} at {self.timestamp}"
