import uuid
from django.db import models
from django.utils.translation import gettext_lazy as _


class CopilotRole(models.TextChoices):
    USER = "user", _("User")
    ASSISTANT = "assistant", _("Assistant")
    SYSTEM = "system", _("System")


class CopilotSession(models.Model):
    """
    Database-backed conversation session for Factory AI Copilot.
    Preserves active machine and incident focus across multi-turn follow-ups.
    """
    session_id = models.CharField(max_length=64, unique=True, db_index=True)
    title = models.CharField(max_length=200, default="Factory Consultation")
    active_machine_code = models.CharField(
        max_length=50, blank=True, default="", db_index=True, help_text="Focused machine context"
    )
    active_incident_code = models.CharField(
        max_length=50, blank=True, default="", db_index=True, help_text="Focused incident context"
    )
    context_state = models.JSONField(
        default=dict, blank=True, help_text="Contextual thread memory and tracked entities"
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self):
        return f"Session {self.session_id}: {self.title}"


class CopilotMessage(models.Model):
    """
    Individual message turn in a Copilot conversation session with evidence grounding,
    categorized reasoning elements (facts, estimates, recommendations), and provenance tracking.
    """
    session = models.ForeignKey(CopilotSession, on_delete=models.CASCADE, related_name="messages")
    role = models.CharField(max_length=20, choices=CopilotRole.choices, default=CopilotRole.USER)
    content = models.TextField()

    # Grounded reasoning components
    facts = models.JSONField(default=list, blank=True, help_text="Verified facts from DB records")
    estimates = models.JSONField(default=list, blank=True, help_text="Statistical / AI estimates")
    recommendations = models.JSONField(default=list, blank=True, help_text="Actionable suggestions")
    references = models.JSONField(
        default=list, blank=True, help_text="Referenced entity chips (machine, incident, ticket)"
    )
    evidence_records = models.JSONField(
        default=list, blank=True, help_text="Bounded excerpts of DB records used as evidence"
    )
    missing_evidence = models.TextField(blank=True, default="", help_text="Explanation of missing data")

    # Simulation safety disclosures
    is_simulated = models.BooleanField(
        default=True, help_text="Whether underlying telemetry/records are simulated"
    )
    simulation_disclosure = models.TextField(
        blank=True,
        default="Data Notice: Telemetry and operational events are simulated factory demonstration data.",
    )

    # Provider & Model Provenance
    provider = models.CharField(max_length=50, default="groq")
    model = models.CharField(max_length=100, default="qwen/qwen3.8-27b")
    latency_ms = models.PositiveIntegerField(default=0)
    reasoning_source = models.CharField(max_length=50, default="GROQ_LIVE")

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        return f"[{self.role.upper()}] {self.session.session_id} @ {self.created_at.strftime('%H:%M:%S')}"
