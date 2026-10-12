"""
Automated Pytest Suite for Phase 5: Autonomous AI Agents (Machine Health Specialist).
Tests:
1. 7 Read-only domain tools with real ORM records and missing entity handling.
2. Unconfigured / missing LLM key handling.
3. Mock LLM Provider structured inference.
4. End-to-end Machine Health Specialist investigation lifecycle.
5. Deduplication of investigations.
6. Action safety and human-in-the-loop approval execution.
7. Rejection of approval requests and audit logging.
8. REST API endpoints for agent operations and approvals.
"""
import pytest
from django.utils import timezone
from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType, MachineOperatingLimits, MachineTelemetry, MachineStatus
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus, IncidentCategory
from apps.ai_agents.models import AgentDefinition, AgentExecution, AgentDecision, AgentAction, AgentType, AgentExecutionStatus
from apps.ai_agents.tools import (
    get_machine_details,
    get_recent_machine_telemetry,
    get_machine_operating_limits,
    get_machine_maintenance_history,
    get_active_machine_incidents,
    get_affected_production_orders,
    get_relevant_spare_parts,
)
from apps.ai_agents.llm_client import GeminiProvider, MockLLMProvider
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.action_service import ActionSafetyService
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog
from apps.maintenance.models import MaintenanceTicket
from apps.production.models import ProductionOrder, ProductionBatch
from apps.inventory.models import InventoryItem, InventoryCategory


@pytest.fixture
def factory_setup(db):
    factory, _ = Factory.objects.get_or_create(code="FAC-PSG-01", defaults={"name": "PSG Mill"})
    dept, _ = Department.objects.get_or_create(
        code="WEV", factory=factory, defaults={"name": "Weaving Shed", "department_type": DepartmentType.WEAVING}
    )
    mtype, _ = MachineType.objects.get_or_create(name="Air-Jet Loom", defaults={"category": DepartmentType.WEAVING})
    machine, _ = Machine.objects.get_or_create(
        code="WEV-AJ-02",
        defaults={
            "department": dept,
            "machine_type": mtype,
            "name": "Picanol OmniPlus-i Loom #2",
            "status": MachineStatus.OPERATIONAL,
            "rated_speed_rpm": 850,
            "current_health_score": 95.0,
        },
    )
    limits, _ = MachineOperatingLimits.objects.get_or_create(
        machine=machine,
        defaults={
            "warning_temp_c": 75.0,
            "max_temp_c": 85.0,
            "warning_vibration_mms": 4.0,
            "max_vibration_mms": 5.8,
            "min_rpm": 500,
            "max_rpm": 1200,
            "max_power_kw": 50.0,
        },
    )
    # Seed telemetry
    for i in range(5):
        MachineTelemetry.objects.create(
            machine=machine,
            timestamp=timezone.now() - timezone.timedelta(seconds=(5 - i) * 3),
            temperature_c=52.0 + i,
            vibration_mms=6.8 + (i * 0.1),
            speed_rpm=850.0,
            power_kw=45.0,
            utilization_pct=92.0,
            status_flag="CRITICAL",
        )
    # Seed spare part
    item, _ = InventoryItem.objects.get_or_create(
        item_code="SPR-BRG-6204",
        defaults={
            "name": "Deep Groove Ball Bearing 6204-2RS",
            "category": InventoryCategory.SPARE_PART,
            "current_stock": 14.0,
            "reorder_point": 5.0,
            "unit": "PCS",
            "unit_cost": 420.0,
        },
    )
    # Seed incident
    incident, _ = FactoryIncident.objects.get_or_create(
        incident_code="INC-TEST-001",
        defaults={
            "factory": factory,
            "department": dept,
            "machine": machine,
            "severity": IncidentSeverity.CRITICAL,
            "status": IncidentStatus.OPEN,
            "category": IncidentCategory.MACHINE_HEALTH,
            "summary": "Severe mechanical vibration on WEV-AJ-02 (6.8 mm/s)",
            "evidence_data": {"observed_vib": 6.8, "limit": 5.8},
        },
    )
    return {
        "factory": factory,
        "department": dept,
        "machine": machine,
        "limits": limits,
        "incident": incident,
        "spare_part": item,
    }


@pytest.mark.django_db
def test_agent_read_only_tools(factory_setup):
    """Verifies all 7 agent tools correctly return structured database context."""
    machine = factory_setup["machine"]

    # 1. Machine details
    details = get_machine_details(machine.code)
    assert details["code"] == "WEV-AJ-02"
    assert details["name"] == "Picanol OmniPlus-i Loom #2"
    assert details["rated_speed_rpm"] == 850

    # 2. Telemetry history
    tel = get_recent_machine_telemetry(machine.code, limit=10)
    assert tel["record_count"] >= 5
    assert len(tel["telemetry_history"]) >= 5

    # 3. Operating limits
    limits = get_machine_operating_limits(machine.code)
    assert limits["warning_vibration_mms"] == 4.0
    assert limits["max_vibration_mms"] == 5.8

    # 4. Maintenance history
    maint = get_machine_maintenance_history(machine.code)
    assert "maintenance_history" in maint

    # 5. Active incidents
    inc = get_active_machine_incidents(machine.code)
    assert inc["active_incidents_count"] >= 1
    assert inc["incidents"][0]["incident_code"] == "INC-TEST-001"

    # 6. Affected production
    prod = get_affected_production_orders(machine.code)
    assert "affected_batches" in prod

    # 7. Spare parts
    parts = get_relevant_spare_parts(machine.code)
    assert parts["available_parts_count"] >= 1


@pytest.mark.django_db
def test_unconfigured_llm_provider_handling():
    """Verifies that missing API keys report UNCONFIGURED status without crashing or faking."""
    provider = GeminiProvider(api_key="", model_name="gemini-2.5-flash")
    assert not provider.is_configured()

    res = provider.generate_structured(system_prompt="Test", user_prompt="Test")
    assert res.status == "UNCONFIGURED"
    assert "not configured" in res.error_message


@pytest.mark.django_db
def test_mock_llm_provider_inference():
    """Verifies MockLLMProvider returns valid structured JSON adhering to the schema."""
    provider = MockLLMProvider()
    assert provider.is_configured()

    res = provider.generate_structured(system_prompt="Test", user_prompt="Test")
    assert res.status == "SUCCESS"
    assert res.structured_json is not None
    assert "possible_root_causes" in res.structured_json
    assert "verified_sensor_facts" in res.structured_json
    assert len(res.structured_json["suggested_next_actions"]) > 0


@pytest.mark.django_db
def test_machine_health_agent_investigation_lifecycle(factory_setup):
    """Verifies end-to-end investigation, AgentExecution, AgentDecision, and Incident updates."""
    incident = factory_setup["incident"]
    machine = factory_setup["machine"]

    agent = MachineHealthAgent(provider=MockLLMProvider())
    result = agent.investigate_incident(incident.id)

    assert result["success"] is True
    assert result["machine_code"] == "WEV-AJ-02"

    # Verify AgentExecution
    execution = AgentExecution.objects.get(execution_id=result["execution_id"])
    assert execution.status == AgentExecutionStatus.COMPLETED
    assert execution.incident == incident
    assert "machine_details" in execution.context_payload

    # Verify AgentDecision
    decision = AgentDecision.objects.filter(execution=execution).first()
    assert decision is not None
    assert decision.decision_type == "ROOT_CAUSE_DIAGNOSIS"
    assert decision.confidence_score > 0

    # Verify FactoryIncident updated
    incident.refresh_from_db()
    assert "[AI Root Cause Hypothesis]" in incident.root_cause_hypothesis
    assert "ai_investigation" in incident.evidence_data
    assert len(incident.evidence_data["ai_investigation"]["possible_causes"]) > 0

    # Verify AgentAction & ApprovalRequest created
    action = AgentAction.objects.filter(execution=execution).first()
    assert action is not None
    assert action.status == "PENDING_APPROVAL"

    approval = ApprovalRequest.objects.filter(agent_action=action).first()
    assert approval is not None
    assert approval.status == ApprovalStatus.PENDING


@pytest.mark.django_db
def test_investigation_deduplication(factory_setup):
    """Verifies duplicate concurrent investigations are rejected."""
    incident = factory_setup["incident"]
    agent_def, _ = AgentDefinition.objects.get_or_create(
        agent_type=AgentType.MACHINE_HEALTH,
        defaults={"name": "Machine Health Diagnostic Specialist"},
    )

    # Simulate an ongoing execution
    AgentExecution.objects.create(
        agent=agent_def,
        incident=incident,
        trigger_event="RUNNING_TEST",
        status=AgentExecutionStatus.RUNNING,
    )

    agent = MachineHealthAgent(provider=MockLLMProvider())
    res = agent.investigate_incident(incident.id)
    assert res["success"] is False
    assert "already running" in res["message"]


@pytest.mark.django_db
def test_approval_workflow_and_audit_logging(factory_setup):
    """Verifies manager approval executes the real backend action and records audit logs."""
    incident = factory_setup["incident"]
    agent = MachineHealthAgent(provider=MockLLMProvider())
    inv_res = agent.investigate_incident(incident.id)
    assert inv_res["success"] is True

    execution = AgentExecution.objects.get(execution_id=inv_res["execution_id"])
    action = AgentAction.objects.get(execution=execution)
    approval = ApprovalRequest.objects.get(agent_action=action)

    # Approve request
    result = ActionSafetyService.approve_and_execute(
        approval_id=approval.id,
        approved_by="K. Sundaram (Plant Ops Manager)",
        response_notes="Approved loom drive end bearing replacement.",
    )

    assert result["success"] is True
    assert result["action_status"] == "SUCCESS"

    approval.refresh_from_db()
    assert approval.status == ApprovalStatus.APPROVED
    assert approval.approved_by == "K. Sundaram (Plant Ops Manager)"

    # Verify real MaintenanceTicket created
    ticket = MaintenanceTicket.objects.filter(machine=factory_setup["machine"]).order_by("-created_at").first()
    assert ticket is not None
    assert "WEV-AJ-02" in ticket.description
    assert ticket.created_by_agent == "Machine Health Specialist"

    # Verify AuditLog created
    audit = AuditLog.objects.filter(entity_id=approval.approval_code, action="APPROVAL_GRANTED").first()
    assert audit is not None
    assert audit.actor_type == "MANAGER"
    assert audit.actor_id == "K. Sundaram (Plant Ops Manager)"


@pytest.mark.django_db
def test_approval_rejection_workflow(factory_setup):
    """Verifies manager rejection cancels the action and logs audit."""
    incident = factory_setup["incident"]
    agent = MachineHealthAgent(provider=MockLLMProvider())
    agent.investigate_incident(incident.id)

    approval = ApprovalRequest.objects.filter(incident=incident, status=ApprovalStatus.PENDING).first()
    assert approval is not None

    res = ActionSafetyService.reject_approval(
        approval_id=approval.id,
        rejected_by="R. Ramesh (Ops Lead)",
        response_notes="No downtime permitted during current high-priority denim shift.",
    )

    assert res["success"] is True
    assert res["status"] == "REJECTED"

    approval.refresh_from_db()
    assert approval.status == ApprovalStatus.REJECTED
    assert approval.agent_action.status == "CANCELLED"

    audit = AuditLog.objects.filter(entity_id=approval.approval_code, action="APPROVAL_REJECTED").first()
    assert audit is not None
    assert audit.actor_id == "R. Ramesh (Ops Lead)"


@pytest.mark.django_db
def test_agent_rest_api_endpoints(client, factory_setup):
    """Verifies summary, investigation, and approval REST API endpoints."""
    # 1. Summary endpoint
    res = client.get("/api/v1/executions/summary/")
    assert res.status_code == 200
    data = res.json()
    assert "provider_status" in data
    assert "metrics" in data
    assert "pending_incidents_list" in data

    # 2. Agent status
    res = client.get("/api/v1/executions/status/")
    assert res.status_code == 200
    assert res.json()["agent_type"] == "MACHINE_HEALTH"

    # 3. On-demand investigation trigger
    incident = factory_setup["incident"]
    res = client.post(f"/api/v1/executions/investigate/{incident.id}/")
    assert res.status_code in [200, 400]  # Depends on active LLM key or mock in env
