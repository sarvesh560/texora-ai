from rest_framework import serializers
from .models import (
    AgentDefinition,
    AgentExecution,
    AgentDecision,
    AgentAction,
    RecoveryCase,
    RecoveryPlanStep,
    AutonomousWorkflowRun,
)
from apps.approvals.models import ApprovalRequest


class AgentDecisionSerializer(serializers.ModelSerializer):
    decision_type_display = serializers.CharField(source="get_decision_type_display", read_only=True)

    class Meta:
        model = AgentDecision
        fields = "__all__"


class AgentActionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AgentAction
        fields = "__all__"


class AgentExecutionSerializer(serializers.ModelSerializer):
    agent_name = serializers.CharField(source="agent.name", read_only=True)
    agent_type = serializers.CharField(source="agent.agent_type", read_only=True)
    decisions = AgentDecisionSerializer(many=True, read_only=True)
    actions = AgentActionSerializer(many=True, read_only=True)

    class Meta:
        model = AgentExecution
        fields = "__all__"


class AgentDefinitionSerializer(serializers.ModelSerializer):
    agent_type_display = serializers.CharField(source="get_agent_type_display", read_only=True)

    class Meta:
        model = AgentDefinition
        fields = "__all__"


class RecoveryPlanStepSerializer(serializers.ModelSerializer):
    approval_id = serializers.IntegerField(source="approval_request.id", read_only=True, default=None)
    approval_code = serializers.CharField(source="approval_request.approval_code", read_only=True, default=None)
    approval_status = serializers.CharField(source="approval_request.status", read_only=True, default=None)
    approval_title = serializers.CharField(source="approval_request.title", read_only=True, default=None)
    action_status = serializers.CharField(source="agent_action.status", read_only=True, default=None)
    action_payload = serializers.JSONField(source="agent_action.tool_input", read_only=True, default=dict)

    class Meta:
        model = RecoveryPlanStep
        fields = "__all__"


class RecoveryCaseSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)
    department_name = serializers.CharField(source="machine.department.name", read_only=True, default="Manufacturing")
    incident_code = serializers.CharField(source="incident.incident_code", read_only=True)
    incident_severity = serializers.CharField(source="incident.severity", read_only=True)
    incident_summary = serializers.CharField(source="incident.summary", read_only=True)
    what_if_scenario_code = serializers.CharField(source="what_if_scenario.scenario_id", read_only=True, default=None)
    steps = RecoveryPlanStepSerializer(many=True, read_only=True)
    pending_approvals_count = serializers.IntegerField(read_only=True)
    is_all_steps_completed = serializers.BooleanField(read_only=True)

    class Meta:
        model = RecoveryCase
        fields = "__all__"


class AutonomousWorkflowRunSerializer(serializers.ModelSerializer):
    incident_code = serializers.CharField(source="incident.incident_code", read_only=True)
    machine_code = serializers.CharField(source="incident.machine.code", read_only=True)
    machine_name = serializers.CharField(source="incident.machine.name", read_only=True)
    department_name = serializers.CharField(source="incident.department.name", read_only=True)
    recovery_case_code = serializers.CharField(source="recovery_case.case_code", read_only=True, default=None)
    approval_code = serializers.CharField(source="approval_request.approval_code", read_only=True, default=None)
    approval_status = serializers.CharField(source="approval_request.status", read_only=True, default=None)
    what_if_scenario_id = serializers.CharField(source="what_if_scenario.scenario_id", read_only=True, default=None)

    class Meta:
        model = AutonomousWorkflowRun
        fields = "__all__"

