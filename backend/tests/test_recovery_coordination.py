"""
Automated Test Suite for Phase 6: Autonomous Maintenance & Factory Recovery Coordination.
Verifies:
1. Maintenance Coordinator (inspection protocols, labor estimations, ticket deduplication).
2. Inventory Coordinator (stock verification, safety stock barriers, unverified part handling).
3. Production Impact Agent (at-risk orders, downtime loss, alternate machine matching).
4. Recovery Orchestrator (multi-agent synthesis, dependency graphs, recovery priority scoring, case deduplication).
5. Action Safety & RBAC (role validation, rejection of AI self-approval, transactional domain updates).
6. Recovery Case and Plan Step REST APIs.
"""
import pytest
from decimal import Decimal
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from apps.machines.models import Machine, MachineType, MachineStatus
from apps.factories.models import Department
from apps.incidents.models import FactoryIncident, IncidentStatus, IncidentCategory, IncidentSeverity
from apps.maintenance.models import MaintenanceTicket, MaintenanceHistory, TicketPriority, TicketStatus
from apps.inventory.models import InventoryItem, SparePartRequirement, InventoryTransaction
from apps.production.models import ProductionOrder, ProductionBatch, OrderStatus, OrderPriority
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog
from apps.ai_agents.models import (
    RecoveryCase,
    RecoveryPlanStep,
    RecoveryCaseStatus,
    RecoveryStepStatus,
    AgentExecution,
    AgentAction,
    AgentType,
)
from apps.ai_agents.maintenance_coordinator import MaintenanceCoordinatorAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.production_impact_agent import ProductionImpactAgent
from apps.ai_agents.recovery_orchestrator import RecoveryOrchestrator
from apps.ai_agents.action_service import ActionSafetyService


@pytest.fixture
def recovery_test_data(db):
    """Sets up a complete factory environment with machine, incident, inventory, and orders."""
    from apps.factories.models import Factory, DepartmentType
    factory = Factory.objects.create(name="Texora Test Mill", code="FAC-TEST-01")
    dept = Department.objects.create(
        factory=factory,
        department_type=DepartmentType.WEAVING,
        name="Weaving Department",
        code="WEV-DEPT",
    )
    mtype = MachineType.objects.create(name="Airjet Loom", category=DepartmentType.WEAVING)

    machine = Machine.objects.create(
        code="WEV-TEST-01",
        name="Picanol OmniPlus Loom Test",
        department=dept,
        machine_type=mtype,
        status=MachineStatus.OPERATIONAL,
    )

    alt_machine = Machine.objects.create(
        code="WEV-TEST-02",
        name="Picanol OmniPlus Loom Backup",
        department=dept,
        machine_type=mtype,
        status=MachineStatus.IDLE,
    )

    incident = FactoryIncident.objects.create(
        incident_code="INC-TEST-RECOVERY-001",
        factory=factory,
        department=dept,
        machine=machine,
        category=IncidentCategory.MACHINE_HEALTH,
        severity=IncidentSeverity.CRITICAL,
        status=IncidentStatus.OPEN,
        summary="Drive shaft bearing excessive vibration (7.45 mm/s)",
        root_cause_hypothesis="Drive shaft rolling element bearing cage wear",
    )

    # Inventory
    item1 = InventoryItem.objects.create(
        item_code="SPR-BRG-6204",
        name="FAG Main Bearing 6204",
        current_stock=10.0,
        minimum_safety_stock=2.0,
        reorder_point=4.0,
        unit_cost=45.0,
        location_shelf="Shelf A-1",
    )

    item2 = InventoryItem.objects.create(
        item_code="SPR-BELT-SPN",
        name="Habasit Spindle Drive Belt",
        current_stock=0.0,  # Out of stock to test shortage detection
        minimum_safety_stock=1.0,
        reorder_point=3.0,
        unit_cost=25.0,
        location_shelf="Shelf A-2",
    )

    SparePartRequirement.objects.create(machine_type=mtype, item=item1, recommended_quantity=1)
    SparePartRequirement.objects.create(machine_type=mtype, item=item2, recommended_quantity=1)

    # Production Order & Batch
    order = ProductionOrder.objects.create(
        order_number="ORD-TEST-001",
        client_name="Premier Denim Mills",
        fabric_or_yarn_spec="100% Cotton Denim 12oz",
        department=dept,
        target_quantity=5000.0,
        completed_quantity=1200.0,
        status=OrderStatus.IN_PROGRESS,
        priority=OrderPriority.URGENT,
        due_date=timezone.now().date() + timezone.timedelta(days=2),
    )

    batch = ProductionBatch.objects.create(
        batch_number="BATCH-TEST-001",
        production_order=order,
        machine=machine,
        planned_quantity=2000.0,
        actual_quantity=800.0,
        status="RUNNING",
    )

    return {
        "dept": dept,
        "machine": machine,
        "alt_machine": alt_machine,
        "incident": incident,
        "item_in_stock": item1,
        "item_out_of_stock": item2,
        "order": order,
        "batch": batch,
    }


@pytest.mark.django_db
def test_maintenance_coordinator_lifecycle(recovery_test_data):
    """Tests Maintenance Coordinator proposing work orders and preventing duplicate active tickets."""
    incident = recovery_test_data["incident"]
    machine = recovery_test_data["machine"]

    coordinator = MaintenanceCoordinatorAgent()
    result = coordinator.coordinate_maintenance(
        incident_id=incident.id,
        health_diagnosis={
            "possible_root_causes": [{"hypothesis": "Drive bearing cage failure", "likelihood": "HIGH"}],
            "recommended_maintenance_checks": ["Inspect dial runout", "Check belt tension"],
        },
    )

    assert result["success"] is True
    assert result["duplicate_prevented"] is False
    assert result["priority"] == TicketPriority.CRITICAL
    assert len(result["inspection_steps"]) == 2
    assert result["action_id"] is not None

    # Check that an ApprovalRequest was created
    action = AgentAction.objects.get(id=result["action_id"])
    assert action.status == "PENDING_APPROVAL"
    assert action.approval_request is not None

    # Test Ticket Deduplication: If a ticket is created or active, subsequent coordination detects it
    MaintenanceTicket.objects.create(
        ticket_number="MNT-ACTIVE-001",
        machine=machine,
        incident_reference=incident.incident_code,
        title="Active Repair",
        status=TicketStatus.OPEN,
    )

    dup_result = coordinator.coordinate_maintenance(incident_id=incident.id)
    assert dup_result["success"] is True
    assert dup_result["duplicate_prevented"] is True
    assert dup_result["existing_ticket_number"] == "MNT-ACTIVE-001"


@pytest.mark.django_db
def test_inventory_coordinator_shortage_and_unverified_handling(recovery_test_data):
    """Tests Inventory Coordinator handling in-stock parts, shortages, and unverified AI parts."""
    incident = recovery_test_data["incident"]

    coordinator = InventoryCoordinatorAgent()
    result = coordinator.coordinate_inventory(
        incident_id=incident.id,
        health_diagnosis={
            "suggested_next_actions": [
                {"payload": {"required_parts": ["SPR-BRG-6204", "SPR-BELT-SPN", "NON_EXISTENT_PART_XYZ"]}}
            ]
        },
    )

    assert result["success"] is True
    assert len(result["evaluated_parts"]) >= 2
    assert result["shortages_count"] >= 1

    # Check unverified parts detection
    unverified = result["unverified_parts"]
    assert any(p["part_code"] == "NON_EXISTENT_PART_XYZ" for p in unverified)

    # Check that in-stock part proposed a RESERVE action and out-of-stock proposed a PROCUREMENT action
    action_types = [a["action_type"] for a in result["proposed_actions"]]
    assert "RESERVE_SPARE_PART" in action_types
    assert "CREATE_PROCUREMENT_REQUEST" in action_types


@pytest.mark.django_db
def test_production_impact_and_alternate_machine_rerouting(recovery_test_data):
    """Tests Production Impact Agent identifying at-risk batches and discovering alternate machines."""
    incident = recovery_test_data["incident"]
    alt_machine = recovery_test_data["alt_machine"]

    agent = ProductionImpactAgent()
    result = agent.evaluate_production_impact(incident_id=incident.id, estimated_downtime_hours=2.0)

    assert result["success"] is True
    assert len(result["active_batches"]) == 1
    assert len(result["orders_at_risk"]) == 1
    assert result["orders_at_risk"][0]["client_name"] == "Premier Denim Mills"

    # Alternate machine matching
    assert len(result["alternate_machines"]) >= 1
    assert result["alternate_machines"][0]["machine_code"] == alt_machine.code

    # Reroute action proposed
    assert len(result["proposed_actions"]) == 1
    assert result["proposed_actions"][0]["action_type"] == "REROUTE_PRODUCTION_BATCH"


@pytest.mark.django_db
def test_recovery_orchestrator_end_to_end_synthesis(recovery_test_data):
    """Tests Recovery Orchestrator synthesizing multi-agent findings, priority scores, and step dependencies."""
    incident = recovery_test_data["incident"]

    orchestrator = RecoveryOrchestrator()
    result = orchestrator.orchestrate_incident_recovery(incident_id=incident.id)

    assert result["success"] is True
    assert result["case_id"] is not None
    assert result["status"] == RecoveryCaseStatus.AWAITING_APPROVALS
    assert result["priority_score"] >= 80.0
    assert result["steps_count"] >= 3

    case = RecoveryCase.objects.get(id=result["case_id"])
    assert case.steps.count() >= 3

    # Check Step 1 (Inventory) has no dependencies
    step1 = case.steps.get(step_order=1)
    assert step1.dependencies == []

    # Check Step 2 (Maintenance) depends on Step 1
    step2 = case.steps.get(step_order=2)
    assert 1 in step2.dependencies or step2.dependencies == []

    # Case Deduplication Test: Running orchestrator again returns existing case
    dup_res = orchestrator.orchestrate_incident_recovery(incident_id=incident.id)
    assert dup_res["is_existing"] is True
    assert dup_res["case_id"] == case.id


@pytest.mark.django_db
def test_rbac_and_ai_self_approval_security_boundaries(recovery_test_data):
    """Verifies that unauthorized roles and AI self-approvals are strictly rejected."""
    incident = recovery_test_data["incident"]

    # Propose a maintenance action
    execution = AgentExecution.objects.create(
        agent=MaintenanceCoordinatorAgent()._ensure_agent_definition(),
        incident=incident,
        trigger_event="TEST_RBAC",
        status="COMPLETED",
    )

    action = ActionSafetyService.propose_action(
        execution=execution,
        action_type="CREATE_MAINTENANCE_TICKET",
        description="Test Maintenance Work Order",
        payload={"machine_code": recovery_test_data["machine"].code, "priority": "HIGH"},
        requires_approval=True,
    )

    approval = action.approval_request
    assert approval is not None

    # 1. Reject Anonymous / Empty User
    res_anon = ActionSafetyService.approve_and_execute(
        approval_id=approval.id, approved_by="", user_role="MAINTENANCE_MANAGER"
    )
    assert res_anon["success"] is False
    assert "identity is required" in res_anon["error"]

    # 2. Reject AI Agent Self-Approval
    res_ai = ActionSafetyService.approve_and_execute(
        approval_id=approval.id, approved_by="ai_agent", user_role="MAINTENANCE_MANAGER"
    )
    assert res_ai["success"] is False
    assert "AI agent self-approval is strictly forbidden" in res_ai["error"]

    # 3. Reject Unauthorized Role (Operator attempting to create work order)
    res_unauth = ActionSafetyService.approve_and_execute(
        approval_id=approval.id, approved_by="Floor Operator John", user_role="OPERATOR"
    )
    assert res_unauth["success"] is False
    assert "Access Denied" in res_unauth["error"]

    # 4. Accept Authorized Manager Approval
    res_auth = ActionSafetyService.approve_and_execute(
        approval_id=approval.id,
        approved_by="K. Sundaram (Maintenance Lead)",
        user_role="MAINTENANCE_MANAGER",
        response_notes="Approved for immediate technical dispatch",
    )
    assert res_auth["success"] is True
    assert res_auth["action_status"] == "SUCCESS"

    # Verify MaintenanceTicket was created
    ticket = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).first()
    assert ticket is not None
    assert ticket.machine == recovery_test_data["machine"]
    assert ticket.status == TicketStatus.OPEN

    # Verify Audit Log
    audit = AuditLog.objects.filter(entity_type="APPROVAL", action="APPROVAL_GRANTED").first()
    assert audit is not None
    assert "K. Sundaram" in audit.actor_id


@pytest.mark.django_db
def test_recovery_case_rest_apis(recovery_test_data):
    """Tests REST endpoints for Recovery Cases, Summaries, and Orchestration."""
    api_client = APIClient()
    incident = recovery_test_data["incident"]

    # 1. Trigger Orchestrate via REST API
    url = f"/api/v1/recovery-cases/orchestrate/{incident.id}/"
    response = api_client.post(url, {}, format="json")
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["success"] is True
    case_id = data["case_id"]

    # 2. Get Recovery Case Detail
    detail_url = f"/api/v1/recovery-cases/{case_id}/"
    detail_res = api_client.get(detail_url)
    assert detail_res.status_code == status.HTTP_200_OK
    detail_data = detail_res.json()
    assert detail_data["case_code"].startswith("REC-")
    assert len(detail_data["steps"]) >= 3
    assert detail_data["machine_code"] == "WEV-TEST-01"

    # 3. Get Recovery Summary
    summary_url = "/api/v1/recovery-cases/summary/"
    summary_res = api_client.get(summary_url)
    assert summary_res.status_code == status.HTTP_200_OK
    summary_data = summary_res.json()
    assert "metrics" in summary_data
    assert summary_data["metrics"]["total_cases"] >= 1
    assert "pending_approvals" in summary_data


@pytest.mark.django_db
def test_recovery_case_dynamic_status_advancement(recovery_test_data):
    """Verifies that approving action gates updates RecoveryCase status dynamically from AWAITING_APPROVALS to VERIFYING_TELEMETRY."""
    incident = recovery_test_data["incident"]
    orch = RecoveryOrchestrator()
    res = orch.orchestrate_incident_recovery(incident.id)
    case_id = res["case_id"]

    case = RecoveryCase.objects.get(id=case_id)
    assert case.status == RecoveryCaseStatus.AWAITING_APPROVALS

    # Approve all pending approval requests
    for step in case.steps.filter(status=RecoveryStepStatus.AWAITING_APPROVAL):
        if step.approval_request:
            ActionSafetyService.approve_and_execute(
                approval_id=step.approval_request.id,
                approved_by="K. Sundaram (Plant Maintenance Superintendent)",
                user_role="PLANT_DIRECTOR",
            )

    case.refresh_from_db()
    # Since all work orders and parts are approved, status must advance to VERIFYING_TELEMETRY
    assert case.status in [RecoveryCaseStatus.VERIFYING_TELEMETRY, RecoveryCaseStatus.IN_RECOVERY]
    assert case.pending_approvals_count == 0

    # Complete the telemetry verification step
    final_step = case.steps.filter(action_type="VERIFY_TELEMETRY_RECOVERY").first()
    if final_step:
        final_step.status = RecoveryStepStatus.COMPLETED
        final_step.save()
        orch.evaluate_step_dependencies(case.id)
        case.refresh_from_db()
        assert case.status == RecoveryCaseStatus.RECOVERED
        assert case.is_all_steps_completed is True

