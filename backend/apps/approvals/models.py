from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.incidents.models import FactoryIncident
from apps.ai_agents.models import AgentAction


class ApprovalStatus(models.TextChoices):
    PENDING = "PENDING", _("Pending Manager Review")
    APPROVED = "APPROVED", _("Approved by Manager")
    REJECTED = "REJECTED", _("Rejected by Manager")
    REVISION_REQUESTED = "REVISION_REQUESTED", _("Revision Requested by Manager")
    EXPIRED = "EXPIRED", _("Expired / Timeout Escalation")


class ApprovalRequest(models.Model):
    """Human-in-the-loop approval gate for high-impact or sensitive AI actions."""
    approval_code = models.CharField(max_length=50, unique=True, help_text="e.g. APR-2026-0089")
    incident = models.ForeignKey(FactoryIncident, on_delete=models.CASCADE, related_name="approval_requests")
    agent_action = models.OneToOneField(
        AgentAction, on_delete=models.SET_NULL, null=True, blank=True, related_name="approval_request"
    )
    title = models.CharField(max_length=200)
    description = models.TextField()
    requested_action = models.CharField(
        max_length=150, help_text="e.g. Machine Emergency Stop / Reroute Order ORD-0891"
    )
    risk_level = models.CharField(
        max_length=20,
        choices=[("MEDIUM", "Medium Risk"), ("HIGH", "High Risk"), ("CRITICAL", "Critical Risk")],
        default="HIGH",
    )
    status = models.CharField(
        max_length=30, choices=ApprovalStatus.choices, default=ApprovalStatus.PENDING, db_index=True
    )
    requested_by_agent = models.CharField(max_length=100, default="Production Impact Agent")
    approved_by = models.CharField(max_length=150, blank=True, default="", help_text="Manager Name / ID")
    response_notes = models.TextField(blank=True, default="")
    timeout_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.approval_code} — {self.title} [{self.get_status_display()}]"
