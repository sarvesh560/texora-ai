import uuid
from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.incidents.models import FactoryIncident


class AgentType(models.TextChoices):
    MACHINE_HEALTH = "MACHINE_HEALTH", _("Machine Health Diagnostic Agent")
    MAINTENANCE = "MAINTENANCE", _("Maintenance & Work Order Agent")
    PRODUCTION_IMPACT = "PRODUCTION_IMPACT", _("Production Rescheduling & Impact Agent")
    QUALITY_CONTROL = "QUALITY_CONTROL", _("Quality Assurance & CSP Optimization Agent")
    INVENTORY = "INVENTORY", _("Inventory & Spare Parts Allocation Agent")
    ENERGY = "ENERGY", _("Energy Optimization & Peak Shaving Agent")


class AgentExecutionStatus(models.TextChoices):
    STARTED = "STARTED", _("Started (Triggered)")
    RUNNING = "RUNNING", _("Running AI Reasoning Loop")
    COMPLETED = "COMPLETED", _("Completed Successfully")
    FAILED = "FAILED", _("Failed / Execution Error")
    TIMED_OUT = "TIMED_OUT", _("Timed Out")


class AgentDefinition(models.Model):
    """Specification and permission boundary for an autonomous factory AI agent."""
    agent_type = models.CharField(max_length=50, choices=AgentType.choices, unique=True)
    name = models.CharField(max_length=150)
    description = models.TextField()
    model_name = models.CharField(max_length=100, default="gemini-2.5-flash")
    is_enabled = models.BooleanField(default=True)
    permitted_actions = models.JSONField(
        default=list,
        help_text="Whitelisted backend tool names this agent is authorized to call",
    )
    sensitivity_threshold = models.DecimalField(
        max_digits=4, decimal_places=2, default=0.75, help_text="Anomaly trigger sensitivity (0.0 to 1.0)"
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.name} [{self.get_agent_type_display()}]"


class AgentExecution(models.Model):
    """Durable log of an individual agent reasoning and tool execution run."""
    execution_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False, db_index=True)
    agent = models.ForeignKey(AgentDefinition, on_delete=models.CASCADE, related_name="executions")
    incident = models.ForeignKey(
        FactoryIncident, on_delete=models.SET_NULL, null=True, blank=True, related_name="agent_executions"
    )
    trigger_event = models.CharField(max_length=150, help_text="e.g. BEARING_TEMP_SPIKE on SPN-RS-01")
    status = models.CharField(
        max_length=30, choices=AgentExecutionStatus.choices, default=AgentExecutionStatus.STARTED, db_index=True
    )
    context_payload = models.JSONField(default=dict, blank=True, help_text="Input evidence provided to LLM")
    execution_summary = models.TextField(blank=True, default="")
    token_count = models.PositiveIntegerField(default=0)
    latency_ms = models.PositiveIntegerField(default=0)
    started_at = models.DateTimeField(auto_now_add=True, db_index=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-started_at"]

    def __str__(self):
        return f"Execution {self.execution_id} ({self.agent.name}) [{self.status}]"


class AgentDecision(models.Model):
    """Structured conclusion or operational verdict determined by an agent."""
    execution = models.ForeignKey(AgentExecution, on_delete=models.CASCADE, related_name="decisions")
    decision_type = models.CharField(
        max_length=50,
        choices=[
            ("ROOT_CAUSE_DIAGNOSIS", "Root Cause Diagnosis"),
            ("MAINTENANCE_DISPATCH", "Maintenance Ticket Dispatch"),
            ("PRODUCTION_REROUTE", "Production Order Rerouting"),
            ("SPEED_THROTTLE", "Machine Speed Throttle"),
            ("INVENTORY_RESERVE", "Spare Parts Reservation"),
            ("APPROVAL_ESCALATION", "Manager Approval Escalation"),
        ],
    )
    rationale = models.TextField(help_text="Detailed chain of thought and evidence correlation")
    confidence_score = models.DecimalField(max_digits=5, decimal_places=2, default=90.00)
    risk_level = models.CharField(
        max_length=20, choices=[("LOW", "Low Risk"), ("MEDIUM", "Medium Risk"), ("HIGH", "High Risk")], default="LOW"
    )
    requires_human_approval = models.BooleanField(default=False)
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-timestamp"]

    def __str__(self):
        return f"Decision: {self.get_decision_type_display()} (Risk: {self.risk_level})"


class AgentAction(models.Model):
    """Tool invocation executed or scheduled by an AI agent."""
    execution = models.ForeignKey(AgentExecution, on_delete=models.CASCADE, related_name="actions")
    idempotency_key = models.CharField(
        max_length=255, unique=True, help_text="Prevents duplicate action executions for same incident"
    )
    action_name = models.CharField(max_length=150, help_text="e.g. create_maintenance_ticket")
    tool_name = models.CharField(max_length=100)
    tool_input = models.JSONField(default=dict)
    tool_output = models.JSONField(default=dict, blank=True)
    status = models.CharField(
        max_length=30,
        choices=[
            ("PENDING_APPROVAL", "Pending Human Approval"),
            ("EXECUTING", "Executing Backend Action"),
            ("SUCCESS", "Executed Successfully"),
            ("FAILED", "Execution Failed"),
            ("CANCELLED", "Cancelled / Rejected"),
        ],
        default="SUCCESS",
        db_index=True,
    )
    executed_at = models.DateTimeField(auto_now_add=True)
    error_message = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-executed_at"]

    def __str__(self):
        return f"Action: {self.action_name} [{self.status}] (Key: {self.idempotency_key})"


class RecoveryCaseStatus(models.TextChoices):
    ANALYZING = "ANALYZING", _("Analyzing & Coordinating Agents")
    PLAN_READY = "PLAN_READY", _("Recovery Plan Ready")
    AWAITING_APPROVALS = "AWAITING_APPROVALS", _("Awaiting Manager Approvals")
    IN_RECOVERY = "IN_RECOVERY", _("In Recovery / Executing Work Orders")
    VERIFYING_TELEMETRY = "VERIFYING_TELEMETRY", _("Verifying Post-Repair Telemetry")
    RECOVERED = "RECOVERED", _("Fully Recovered & Operational")
    CANCELLED = "CANCELLED", _("Cancelled / Superceded")


class AutonomousWorkflowStage(models.TextChoices):
    NEW_INCIDENT = "NEW_INCIDENT", _("New Incident Detected")
    INVESTIGATION_PENDING = "INVESTIGATION_PENDING", _("Investigation Pending")
    AI_INVESTIGATING = "AI_INVESTIGATING", _("Gemini AI Health Specialist Investigating")
    INVESTIGATION_COMPLETED = "INVESTIGATION_COMPLETED", _("AI Investigation Completed")
    COORDINATING_AGENTS = "COORDINATING_AGENTS", _("Coordinating Multi-Agent Experts")
    RECOVERY_PLAN_READY = "RECOVERY_PLAN_READY", _("Multi-Agent Recovery Plan Ready")
    SIMULATION_PENDING = "SIMULATION_PENDING", _("Digital Twin Simulation Pending")
    SIMULATING_STRATEGIES = "SIMULATING_STRATEGIES", _("Simulating Recovery Strategies (A, B, C)")
    RECOMMENDATION_READY = "RECOMMENDATION_READY", _("Autonomous Recommendation Ready")
    AWAITING_MANAGER_APPROVAL = "AWAITING_MANAGER_APPROVAL", _("Awaiting Manager Approval")
    APPROVED = "APPROVED", _("Approved by Manager")
    REJECTED = "REJECTED", _("Rejected by Manager")
    REVISION_REQUESTED = "REVISION_REQUESTED", _("Revision Requested by Manager")
    RECOVERY_COORDINATION = "RECOVERY_COORDINATION", _("Executing Authorized Work Orders")
    AWAITING_VERIFICATION = "AWAITING_VERIFICATION", _("Awaiting Technician Repair & Telemetry Verification")
    VERIFIED_RECOVERED = "VERIFIED_RECOVERED", _("Verified Recovered & Nominal")
    VERIFICATION_FAILED = "VERIFICATION_FAILED", _("Recovery Verification Failed")
    FAILED = "FAILED", _("Pipeline Execution Failed")


class RecoveryStepStatus(models.TextChoices):
    PENDING_DEPENDENCY = "PENDING_DEPENDENCY", _("Pending Prior Step Completion")
    AWAITING_APPROVAL = "AWAITING_APPROVAL", _("Awaiting Manager Approval")
    APPROVED = "APPROVED", _("Approved by Manager")
    EXECUTING = "EXECUTING", _("Executing Action")
    COMPLETED = "COMPLETED", _("Completed Successfully")
    REJECTED = "REJECTED", _("Rejected by Manager")
    SKIPPED = "SKIPPED", _("Skipped")


class RecoveryCase(models.Model):
    """Correlated multi-agent factory recovery case resolving an operational incident."""
    case_code = models.CharField(max_length=50, unique=True, db_index=True, help_text="e.g. REC-20261008-001")
    incident = models.ForeignKey(FactoryIncident, on_delete=models.CASCADE, related_name="recovery_cases")
    machine = models.ForeignKey("machines.Machine", on_delete=models.CASCADE, related_name="recovery_cases")
    status = models.CharField(
        max_length=30, choices=RecoveryCaseStatus.choices, default=RecoveryCaseStatus.ANALYZING, db_index=True
    )
    priority = models.CharField(max_length=20, default="HIGH")
    priority_score = models.DecimalField(
        max_digits=5, decimal_places=2, default=85.00, help_text="Evidence-based priority (0.00-100.00)"
    )
    target_resolution_hours = models.DecimalField(max_digits=5, decimal_places=2, default=2.00)
    estimated_downtime_hours = models.DecimalField(max_digits=5, decimal_places=2, default=1.50)
    health_diagnosis = models.JSONField(default=dict, blank=True)
    maintenance_recommendation = models.JSONField(default=dict, blank=True)
    inventory_assessment = models.JSONField(default=dict, blank=True)
    production_impact_assessment = models.JSONField(default=dict, blank=True)
    summary = models.TextField(blank=True, default="")
    
    # Phase 9 Autonomous What-If & Strategy Links
    what_if_scenario = models.ForeignKey(
        "digital_twin.WhatIfScenario", on_delete=models.SET_NULL, null=True, blank=True, related_name="recovery_cases"
    )
    recommended_strategy = models.CharField(max_length=50, blank=True, default="STRATEGY_A")
    selected_strategy = models.CharField(max_length=50, blank=True, default="")
    recommendation_payload = models.JSONField(default=dict, blank=True)
    workflow_run_id = models.CharField(max_length=100, blank=True, default="")
    autonomous_stage = models.CharField(max_length=50, default=AutonomousWorkflowStage.AWAITING_MANAGER_APPROVAL)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    recovered_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Recovery Case {self.case_code} on {self.machine.code} [{self.status}]"

    @property
    def pending_approvals_count(self):
        return self.steps.filter(status=RecoveryStepStatus.AWAITING_APPROVAL).count()

    @property
    def is_all_steps_completed(self):
        total = self.steps.count()
        if total == 0:
            return False
        completed = self.steps.filter(status=RecoveryStepStatus.COMPLETED).count()
        return total == completed


class AutonomousWorkflowRun(models.Model):
    """End-to-end autonomous factory intelligence execution tracking pipeline."""
    workflow_id = models.CharField(max_length=64, unique=True, db_index=True, help_text="e.g. WF-20261009-XXXX")
    incident = models.ForeignKey(FactoryIncident, on_delete=models.CASCADE, related_name="workflow_runs")
    recovery_case = models.ForeignKey(RecoveryCase, on_delete=models.SET_NULL, null=True, blank=True, related_name="workflow_runs")
    what_if_scenario = models.ForeignKey(
        "digital_twin.WhatIfScenario", on_delete=models.SET_NULL, null=True, blank=True, related_name="workflow_runs"
    )
    approval_request = models.ForeignKey(
        "approvals.ApprovalRequest", on_delete=models.SET_NULL, null=True, blank=True, related_name="workflow_runs"
    )
    current_stage = models.CharField(
        max_length=50, choices=AutonomousWorkflowStage.choices, default=AutonomousWorkflowStage.NEW_INCIDENT, db_index=True
    )
    status = models.CharField(max_length=30, default="RUNNING", db_index=True)  # RUNNING, PAUSED_FOR_APPROVAL, COMPLETED, FAILED
    recommended_strategy = models.CharField(max_length=50, blank=True, default="STRATEGY_A")
    selected_strategy = models.CharField(max_length=50, blank=True, default="")
    recommendation_payload = models.JSONField(default=dict, blank=True)
    stage_history = models.JSONField(default=list, blank=True)
    error_message = models.TextField(blank=True, default="")
    retry_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Workflow {self.workflow_id} on {self.incident.incident_code} [{self.current_stage}]"


class RecoveryPlanStep(models.Model):
    """Individual action step in an orchestrated factory recovery workflow."""
    recovery_case = models.ForeignKey(RecoveryCase, on_delete=models.CASCADE, related_name="steps")
    step_order = models.PositiveIntegerField(default=1)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, default="")
    agent_type = models.CharField(max_length=50, default="MAINTENANCE")
    action_type = models.CharField(max_length=100, default="CREATE_MAINTENANCE_TICKET")
    agent_action = models.ForeignKey(AgentAction, on_delete=models.SET_NULL, null=True, blank=True, related_name="recovery_steps")
    approval_request = models.ForeignKey(
        "approvals.ApprovalRequest", on_delete=models.SET_NULL, null=True, blank=True, related_name="recovery_steps"
    )
    status = models.CharField(
        max_length=30, choices=RecoveryStepStatus.choices, default=RecoveryStepStatus.PENDING_DEPENDENCY, db_index=True
    )
    dependencies = models.JSONField(default=list, blank=True, help_text="List of step_orders that must complete before this step")
    output_payload = models.JSONField(default=dict, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["step_order"]
        unique_together = [("recovery_case", "step_order")]

    def __str__(self):
        return f"Step {self.step_order}: {self.title} [{self.status}]"

