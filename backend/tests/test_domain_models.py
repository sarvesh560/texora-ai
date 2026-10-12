import pytest
from datetime import datetime, timezone, timedelta
from apps.factories.models import Factory, Department, ProductionLine, DepartmentType
from apps.machines.models import MachineType, Machine, MachineOperatingLimits, MachineTelemetry, MachineStatus
from apps.production.models import ProductionOrder, ProductionBatch, OrderStatus, OrderPriority
from apps.maintenance.models import MaintenanceTicket, TicketPriority, TicketStatus
from apps.quality.models import QualityInspection, QualityDefect, DefectType
from apps.inventory.models import InventoryItem, InventoryTransaction, InventoryCategory
from apps.energy.models import EnergyReading
from apps.incidents.models import FactoryIncident, AnomalyDetection, IncidentSeverity, IncidentStatus
from apps.ai_agents.models import AgentDefinition, AgentExecution, AgentDecision, AgentAction, AgentType
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog


@pytest.mark.django_db
def test_factory_and_machine_hierarchy():
    """Verify Factory -> Department -> ProductionLine -> Machine hierarchy."""
    factory = Factory.objects.create(name="Texora Mills #1", code="FAC-TEX-01")
    spinning = Department.objects.create(
        factory=factory,
        department_type=DepartmentType.SPINNING,
        name="Spinning Unit A",
        code="SPN-01",
    )
    line = ProductionLine.objects.create(
        department=spinning,
        name="Ring Frame Line 1",
        code="SPN-L1",
        target_capacity_units_per_hour=1500.0,
    )
    m_type = MachineType.objects.create(
        category=DepartmentType.SPINNING,
        name="Ring Spinning Frame G38",
        manufacturer="Rieter",
        model_number="G38-Compact",
    )
    machine = Machine.objects.create(
        code="SPN-RS-01",
        name="Rieter Ring Frame #1",
        machine_type=m_type,
        department=spinning,
        production_line=line,
        status=MachineStatus.OPERATIONAL,
        rated_speed_rpm=19500,
    )
    limits = MachineOperatingLimits.objects.create(
        machine=machine,
        warning_temp_c=72.0,
        max_temp_c=85.0,
        warning_vibration_mms=3.8,
        max_vibration_mms=5.5,
    )

    assert machine.department.factory == factory
    assert machine.operating_limits == limits
    assert str(machine) == "SPN-RS-01 — Rieter Ring Frame #1 [Operational (Running Normal)]"


@pytest.mark.django_db
def test_production_and_maintenance_lifecycle():
    """Verify Production Orders and Maintenance Tickets linked to machines."""
    factory = Factory.objects.create(name="Texora Mills", code="FAC-01")
    weaving = Department.objects.create(
        factory=factory, department_type=DepartmentType.WEAVING, name="Weaving Shed", code="WEV-01"
    )
    m_type = MachineType.objects.create(
        category=DepartmentType.WEAVING, name="Air Jet Loom OmniPlus-i", manufacturer="Picanol"
    )
    machine = Machine.objects.create(
        code="WEV-AJ-01", name="Picanol Loom #1", machine_type=m_type, department=weaving
    )

    # Create Production Order & Batch
    order = ProductionOrder.objects.create(
        order_number="ORD-2026-W001",
        client_name="Apex Apparels Ltd",
        fabric_or_yarn_spec="220 GSM Cotton Twill",
        department=weaving,
        target_quantity=5000.00,
        completed_quantity=2500.00,
        due_date=datetime.now(timezone.utc).date() + timedelta(days=7),
    )
    assert order.progress_pct == 50.0

    batch = ProductionBatch.objects.create(
        batch_number="BATCH-W001-A",
        production_order=order,
        machine=machine,
        planned_quantity=2500.00,
        actual_quantity=2480.00,
        defect_quantity=20.00,
    )
    assert batch.production_order == order

    # Create Maintenance Ticket
    ticket = MaintenanceTicket.objects.create(
        ticket_number="MNT-2026-0012",
        machine=machine,
        incident_reference="INC-2026-0005",
        title="Weft Insertion Nozzle Pressure Drop",
        description="Air pressure drop detected on main nozzle",
        priority=TicketPriority.HIGH,
        status=TicketStatus.OPEN,
        created_by_agent="Machine Health Agent",
    )
    assert ticket.machine == machine
    assert ticket.created_by_agent == "Machine Health Agent"


@pytest.mark.django_db
def test_autonomous_ai_and_approval_correlation():
    """Verify Incident -> AgentExecution -> AgentAction -> ApprovalRequest correlation."""
    factory = Factory.objects.create(name="Texora Factory", code="FAC-02")
    dyeing = Department.objects.create(
        factory=factory, department_type=DepartmentType.DYEING, name="Dyeing House", code="DYE-01"
    )
    m_type = MachineType.objects.create(
        category=DepartmentType.DYEING, name="Soft Flow Dyeing Vessel", manufacturer="Fongs"
    )
    machine = Machine.objects.create(
        code="DYE-SF-01", name="Fongs Soft Flow #1", machine_type=m_type, department=dyeing
    )

    incident = FactoryIncident.objects.create(
        incident_code="INC-2026-0089",
        factory=factory,
        department=dyeing,
        machine=machine,
        severity=IncidentSeverity.HIGH,
        status=IncidentStatus.INVESTIGATING,
        summary="Dye bath temperature ramp rate failure (Delta T > 4.5C)",
    )

    agent_def = AgentDefinition.objects.create(
        agent_type=AgentType.MACHINE_HEALTH,
        name="Machine Health Agent",
        description="Monitors telemetry and diagnoses thermal/mechanical faults",
        permitted_actions=["create_maintenance_ticket", "throttle_machine_speed"],
    )

    execution = AgentExecution.objects.create(
        agent=agent_def,
        incident=incident,
        trigger_event="DYE_TEMP_RAMP_DEVIATION",
        context_payload={"temp_c": 128.5, "target_c": 135.0},
    )

    decision = AgentDecision.objects.create(
        execution=execution,
        decision_type="ROOT_CAUSE_DIAGNOSIS",
        rationale="Steam modulating valve stuck at 40% open position",
        confidence_score=94.50,
        risk_level="HIGH",
        requires_human_approval=True,
    )

    action = AgentAction.objects.create(
        execution=execution,
        idempotency_key=f"ACTION_DYE_VALVE_{incident.incident_code}",
        action_name="emergency_valve_bypass",
        tool_name="dispatch_valve_bypass",
        status="PENDING_APPROVAL",
    )

    approval = ApprovalRequest.objects.create(
        approval_code="APR-2026-0033",
        incident=incident,
        agent_action=action,
        title="Approve Steam Valve Manual Bypass",
        description="Bypasses automatic controller to prevent batch shade ruining",
        risk_level="HIGH",
        status=ApprovalStatus.PENDING,
    )

    assert approval.incident == incident
    assert approval.agent_action == action
    assert decision.requires_human_approval is True
