"""
Phase 11: Commercial Showcase, Live AI Agent Operations & Complete Workflow Verification Tests.
Verifies:
1. Operations Overview API (/api/v1/ai-agents/operations-overview/)
2. Audit Details API (/api/v1/ai-agents/audit-details/<exec_id>/)
3. Incident 12-Stage Workflow Timeline API (/api/v1/autonomous/incident-workflow/<id>/)
4. Business Impact Intelligence API (/api/v1/autonomous/business-impact/<id>/)
5. Expo Demo Status API (/api/v1/autonomous/demo-status/)
6. Controlled Expo Demo Scenario Execution (execute_expo_demo)
7. Manager Approval Safety & Inventory Stock Isolation
"""
import pytest
from rest_framework.test import APIClient
from decimal import Decimal

from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType, MachineStatus, MachineOperatingLimits
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.inventory.models import InventoryTransaction
from apps.ai_agents.models import (
    AgentDefinition,
    AgentExecution,
    AgentType,
    AutonomousWorkflowStage,
)
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator


@pytest.fixture
def phase11_setup(db):
    factory = Factory.objects.create(name="Texora PSG Expo Mill", code="TEX-PSG-01", location="Coimbatore")
    weaving_dept = Department.objects.create(
        factory=factory, name="Weaving Shed", code="WEV", department_type=DepartmentType.WEAVING
    )
    mtype = MachineType.objects.create(
        name="Air Jet Loom",
        category=DepartmentType.WEAVING,
        manufacturer="Toyota",
        model_number="JAT810",
        default_power_rating_kw=Decimal("7.50"),
    )
    machine = Machine.objects.create(
        code="WEV-AJ-02",
        name="Toyota Air-Jet Loom #02",
        machine_type=mtype,
        department=weaving_dept,
        status=MachineStatus.OPERATIONAL,
        rated_speed_rpm=800,
        rated_capacity_units_per_hour=Decimal("45.0"),
    )
    limits = MachineOperatingLimits.objects.create(
        machine=machine,
        min_temp_c=20.0,
        max_temp_c=80.0,
        warning_temp_c=70.0,
        max_vibration_mms=4.5,
        warning_vibration_mms=3.5,
        min_rpm=400,
        max_rpm=950,
        max_power_kw=9.0,
    )
    # Ensure agent definitions exist
    for atype in [AgentType.MACHINE_HEALTH, AgentType.MAINTENANCE, AgentType.INVENTORY, AgentType.PRODUCTION_IMPACT]:
        AgentDefinition.objects.get_or_create(
            agent_type=atype,
            defaults={
                "name": f"{atype.replace('_', ' ').title()} Specialist",
                "description": "Industrial intelligence agent.",
                "model_name": "deterministic-engine",
                "is_enabled": True,
            }
        )
    return {
        "factory": factory,
        "department": weaving_dept,
        "machine": machine,
        "limits": limits,
    }


@pytest.mark.django_db
def test_operations_overview_api(phase11_setup):
    """Verify /api/v1/ai-agents/operations-overview/ returns 4 specialist agents and metrics."""
    client = APIClient()
    response = client.get("/api/v1/ai-agents/operations-overview/")
    assert response.status_code == 200
    data = response.json()
    assert "overall_metrics" in data
    assert "worker_heartbeats" in data
    assert "specialist_agents" in data

    agents = data["specialist_agents"]
    assert len(agents) == 4
    agent_types = [a["agent_type"] for a in agents]
    assert "MACHINE_HEALTH" in agent_types
    assert "MAINTENANCE" in agent_types
    assert "INVENTORY" in agent_types
    assert "PRODUCTION_IMPACT" in agent_types


@pytest.mark.django_db
def test_audit_details_api(phase11_setup):
    """Verify /api/v1/ai-agents/audit-details/<exec_id>/ returns sanitized execution trace."""
    agent_def = AgentDefinition.objects.get(agent_type=AgentType.MACHINE_HEALTH)
    execution = AgentExecution.objects.create(
        agent=agent_def,
        trigger_event="SCHEDULED_CYCLE",
        status="COMPLETED",
        context_payload={"machine_id": phase11_setup["machine"].id, "vibration": 3.2},
        execution_summary="Normal bearing temperature",
    )

    client = APIClient()
    response = client.get(f"/api/v1/ai-agents/audit-details/{execution.id}/")
    assert response.status_code == 200
    data = response.json()
    assert data["agent_type"] == "MACHINE_HEALTH"
    assert data["status"] == "COMPLETED"
    assert "api_key" not in str(data).lower()
    assert "secret" not in str(data).lower()


@pytest.mark.django_db
def test_incident_workflow_12_stages_api(phase11_setup):
    """Verify /api/v1/autonomous/incident-workflow/<id>/ produces all 12 stages."""
    machine = phase11_setup["machine"]
    incident = FactoryIncident.objects.create(
        incident_code="INC-TEST-001",
        summary="Abnormal Vibration Detected",
        root_cause_hypothesis="High vibration on loom",
        machine=machine,
        department=machine.department,
        factory=machine.department.factory,
        severity=IncidentSeverity.CRITICAL,
        status=IncidentStatus.INVESTIGATING,
    )

    client = APIClient()
    response = client.get(f"/api/v1/autonomous/incident-workflow/{incident.id}/")
    assert response.status_code == 200
    data = response.json()
    assert "stages" in data
    assert data["incident"]["id"] == incident.id
    assert len(data["stages"]) == 12

    # Verify stage order and keys
    stage_keys = [s["stage_key"] for s in data["stages"]]
    expected_keys = [
        "TELEMETRY_RECEIVED",
        "ABNORMALITY_DETECTED",
        "INCIDENT_CREATED",
        "MACHINE_HEALTH_INVESTIGATION",
        "MAINTENANCE_COORDINATION",
        "INVENTORY_COORDINATION",
        "PRODUCTION_IMPACT_ANALYSIS",
        "DIGITAL_TWIN_EVALUATION",
        "RECOVERY_RECOMMENDATION",
        "MANAGER_APPROVAL",
        "AUTHORIZED_ACTION",
        "RECOVERY_VERIFICATION",
    ]
    assert stage_keys == expected_keys
    # Stage 3 (Incident Created) should be COMPLETED since incident exists
    assert data["stages"][2]["status"] == "COMPLETED"


@pytest.mark.django_db
def test_business_impact_api(phase11_setup):
    """Verify /api/v1/autonomous/business-impact/<id>/ returns financial calculations."""
    machine = phase11_setup["machine"]
    incident = FactoryIncident.objects.create(
        incident_code="INC-TEST-002",
        summary="Bearing Overheating",
        root_cause_hypothesis="Temperature surge on loom",
        machine=machine,
        department=machine.department,
        factory=machine.department.factory,
        severity=IncidentSeverity.HIGH,
        status=IncidentStatus.INVESTIGATING,
    )

    client = APIClient()
    response = client.get(f"/api/v1/autonomous/business-impact/{incident.id}/")
    assert response.status_code == 200
    data = response.json()
    assert "kpis" in data
    assert "strategy_comparison" in data
    assert len(data["strategy_comparison"]) >= 3
    # Check that net risk avoided is non-negative
    assert data["kpis"]["net_financial_risk_avoided_inr"] >= 0


@pytest.mark.django_db
def test_demo_status_api():
    """Verify /api/v1/autonomous/demo-status/ reports readiness."""
    client = APIClient()
    response = client.get("/api/v1/autonomous/demo-status/")
    assert response.status_code == 200
    data = response.json()
    assert "can_trigger" in data
    assert "demo_scenario_name" in data


@pytest.mark.django_db
def test_execute_expo_demo_scenario(phase11_setup):
    """Verify execute_expo_demo creates an end-to-end incident, runs agents, and preserves approval gate."""
    orchestrator = AutonomousFactoryOrchestrator()
    result = orchestrator.execute_expo_demo()

    # The autonomous pipeline runs up to manager approval gate
    assert result["status"] in [AutonomousWorkflowStage.AWAITING_MANAGER_APPROVAL, "success"]
    assert "incident_id" in result
    incident_id = result["incident_id"]

    incident = FactoryIncident.objects.get(id=incident_id)
    assert incident.machine.code == "WEV-AJ-02"
    assert incident.evidence_data.get("is_simulation_demo") is True or incident.evidence_data.get("data_source") == "CONTROLLED_SIMULATION_DEMO"

    # Check that approval request was generated
    approvals = ApprovalRequest.objects.filter(incident=incident)
    assert approvals.exists()
    approval = approvals.first()
    assert approval.status == ApprovalStatus.PENDING

    # Check inventory safety: warehouse parts must NOT be deducted while approval is PENDING
    stock_deductions = InventoryTransaction.objects.filter(
        reference_number=incident.incident_code,
        transaction_type="DEDUCT"
    )
    assert not stock_deductions.exists()
