"""
Phase 15 - Advanced Production Intelligence Test Suite.

Verifies:
1. Production Data Models (ProductionOrder, ProductionBatch, MachineProductionAssignment, etc.)
2. Textile routing and configurable department sequences
3. Capacity Intelligence Engine (deterministic capacity, utilization, and bottlenecks)
4. Order timeline predictions and delivery deadline risks
5. Machine breakdown fallout and alternate machine capacity discovery
6. Production Impact Agent integration and grounded reasoning
7. Production Intelligence DRF REST APIs
8. Copilot grounded production queries (targets, bottlenecks, at-risk orders, capacity)
9. Controlled simulation progression (advance, breakdown, recover)
"""

import pytest
from datetime import timedelta
from decimal import Decimal
from django.utils import timezone
from rest_framework.test import APIClient

from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType, MachineStatus
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus, IncidentCategory
from apps.production.models import (
    ProductionOrder,
    ProductionBatch,
    MachineProductionAssignment,
    ProductionProgress,
    ProductionCapacityProfile,
    ProductionBottleneck,
    ProductionImpactAssessment,
    OrderStatus,
    OrderPriority,
    DelayRiskLevel,
)
from apps.production.capacity_engine import CapacityIntelligenceEngine, DEFAULT_TEXTILE_ROUTES
from apps.production.simulation_service import ProductionSimulationService
from apps.ai_agents.production_impact_agent import ProductionImpactAgent
from apps.copilot.context_engine import FactoryContextEngine
from apps.copilot.reasoning_engine import DeterministicCopilotEngine


@pytest.fixture
def factory_setup(db):
    """Creates a realistic textile factory environment with spinning and weaving departments."""
    factory = Factory.objects.create(
        code="FAC-TEST-01",
        name="Texora Test Textile Mill",
        location="Coimbatore, India",
    )
    spn_dept = Department.objects.create(
        factory=factory,
        code="SPN",
        department_type=DepartmentType.SPINNING,
        name="Spinning Department",
    )
    wev_dept = Department.objects.create(
        factory=factory,
        code="WEV",
        department_type=DepartmentType.WEAVING,
        name="Weaving Shed",
    )

    mtype_ring = MachineType.objects.create(
        name="Ring Spinning Frame G38",
        category=DepartmentType.SPINNING,
    )
    mtype_loom = MachineType.objects.create(
        name="Air Jet Loom OmniPlus",
        category=DepartmentType.WEAVING,
    )

    # 2 Spinning machines
    spn1 = Machine.objects.create(
        code="SPN-RS-01",
        name="Ring Frame 01",
        department=spn_dept,
        machine_type=mtype_ring,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("60.00"),
    )
    spn2 = Machine.objects.create(
        code="SPN-RS-02",
        name="Ring Frame 02",
        department=spn_dept,
        machine_type=mtype_ring,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("60.00"),
    )

    # 2 Weaving looms
    wev1 = Machine.objects.create(
        code="WEV-AJ-01",
        name="Air Jet Loom 01",
        department=wev_dept,
        machine_type=mtype_loom,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("50.00"),
    )
    wev2 = Machine.objects.create(
        code="WEV-AJ-02",
        name="Air Jet Loom 02",
        department=wev_dept,
        machine_type=mtype_loom,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("50.00"),
    )

    knt_dept = Department.objects.create(
        factory=factory,
        code="KNT",
        department_type=DepartmentType.KNITTING,
        name="Knitting Division",
    )
    Machine.objects.create(
        code="KNT-CK-01",
        name="Circular Knitter 01",
        department=knt_dept,
        machine_type=mtype_loom,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("45.00"),
    )

    dye_dept = Department.objects.create(
        factory=factory,
        code="DYE",
        department_type=DepartmentType.DYEING,
        name="Dyeing & Processing",
    )
    Machine.objects.create(
        code="DYE-SF-01",
        name="Soft Flow Dye Vessel 01",
        department=dye_dept,
        machine_type=mtype_loom,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("40.00"),
    )

    fin_dept = Department.objects.create(
        factory=factory,
        code="FIN",
        department_type=DepartmentType.FINISHING,
        name="Finishing & Stenter",
    )
    Machine.objects.create(
        code="FIN-ST-01",
        name="Stenter Line 01",
        department=fin_dept,
        machine_type=mtype_loom,
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("55.00"),
    )

    return {
        "factory": factory,
        "spn_dept": spn_dept,
        "wev_dept": wev_dept,
        "knt_dept": knt_dept,
        "dye_dept": dye_dept,
        "fin_dept": fin_dept,
        "spn1": spn1,
        "spn2": spn2,
        "wev1": wev1,
        "wev2": wev2,
    }


@pytest.mark.django_db
def test_production_order_model_and_properties(factory_setup):
    """Tests ProductionOrder creation, properties, and custom textile routing."""
    wev_dept = factory_setup["wev_dept"]
    now = timezone.now().date()

    order = ProductionOrder.objects.create(
        order_number="ORD-TEST-001",
        client_name="Test Apparel Global",
        customer_po_number="PO-TAG-9901",
        fabric_or_yarn_spec="100% Combed Cotton Oxford Shirting",
        product_category="WOVEN_SHIRTING",
        department=wev_dept,
        target_quantity=Decimal("10000.00"),
        completed_quantity=Decimal("4000.00"),
        unit="METERS",
        status=OrderStatus.IN_PROGRESS,
        priority=OrderPriority.HIGH,
        routing_stages=DEFAULT_TEXTILE_ROUTES["FULL_CYCLE"],
        current_stage="Weaving Shed",
        start_date=now - timedelta(days=2),
        due_date=now + timedelta(days=5),
    )

    assert order.progress_pct == 40.0
    assert order.remaining_quantity == 6000.0
    assert len(order.routing_stages) == 6
    assert "SPN" in order.routing_stages
    assert "WEV" in order.routing_stages


@pytest.mark.django_db
def test_capacity_intelligence_department_calculations(factory_setup):
    """Tests deterministic nominal and effective department capacity calculations."""
    spn_dept = factory_setup["spn_dept"]
    wev_dept = factory_setup["wev_dept"]

    profiles = CapacityIntelligenceEngine.calculate_department_capacities()
    assert len(profiles) >= 2

    spn_prof = next(p for p in profiles if p["department_code"] == "SPN")
    # 2 machines * 60 units/hr * 24h = 2880 units/day nominal
    assert spn_prof["nominal_capacity_daily"] == 2880.0
    assert spn_prof["effective_capacity_daily"] == 2880.0
    assert spn_prof["active_machines"] == 2
    assert spn_prof["down_machines"] == 0

    wev_prof = next(p for p in profiles if p["department_code"] == "WEV")
    # 2 machines * 50 units/hr * 24h = 2400 units/day nominal
    assert wev_prof["nominal_capacity_daily"] == 2400.0


@pytest.mark.django_db
def test_order_timeline_and_delay_risk_prediction(factory_setup):
    """Tests remaining hours, projected delivery completion, and delay risk score."""
    wev_dept = factory_setup["wev_dept"]
    wev1 = factory_setup["wev1"]
    now = timezone.now().date()

    # Order with very tight due date (tomorrow) but large remaining quantity
    tight_order = ProductionOrder.objects.create(
        order_number="ORD-RUSH-001",
        client_name="Rush Client Tirupur",
        fabric_or_yarn_spec="Denim Twill",
        department=wev_dept,
        target_quantity=Decimal("5000.00"),
        completed_quantity=Decimal("500.00"),
        unit="METERS",
        status=OrderStatus.IN_PROGRESS,
        priority=OrderPriority.URGENT,
        due_date=now + timedelta(days=1),  # Due in 1 day
    )

    # Assign machine
    MachineProductionAssignment.objects.create(
        machine=wev1,
        production_order=tight_order,
        department=wev_dept,
        status="RUNNING",
    )

    risks = CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
    tight_risk = next(r for r in risks if r["order_number"] == "ORD-RUSH-001")

    # Remaining: 4500 units / 50 units/hr = 90 hours = ~4 days needed > 1 day buffer
    assert tight_risk["delay_risk_level"] in [DelayRiskLevel.HIGH, DelayRiskLevel.CRITICAL]
    assert tight_risk["estimated_delay_hours"] > 0
    assert tight_risk["delay_risk_score"] > 70.0


@pytest.mark.django_db
def test_machine_breakdown_impact_and_alternate_discovery(factory_setup):
    """Tests machine breakdown impact evaluation and compatible alternate discovery."""
    wev1 = factory_setup["wev1"]
    wev2 = factory_setup["wev2"]
    wev_dept = factory_setup["wev_dept"]

    order = ProductionOrder.objects.create(
        order_number="ORD-WEV-BREAK-01",
        client_name="Fabric International",
        fabric_or_yarn_spec="Cotton Poplin",
        department=wev_dept,
        target_quantity=Decimal("6000.00"),
        completed_quantity=Decimal("1200.00"),
        unit="METERS",
        status=OrderStatus.IN_PROGRESS,
        due_date=timezone.now().date() + timedelta(days=3),
    )
    batch = ProductionBatch.objects.create(
        batch_number="BATCH-WEV-01",
        production_order=order,
        machine=wev1,
        department=wev_dept,
        planned_quantity=Decimal("3000.00"),
        actual_quantity=Decimal("1200.00"),
        status="RUNNING",
    )

    # Impair wev1
    assessment = CapacityIntelligenceEngine.evaluate_machine_breakdown_impact(
        machine=wev1,
        estimated_downtime_hours=2.5,
    )

    # 50 units/hr * 2.5h = 125 units output at risk
    assert float(assessment.output_quantity_at_risk) == 125.0
    assert assessment.orders_affected_count == 1
    assert assessment.deterministic_loss_inr > 0
    assert len(assessment.alternate_capacities) >= 1

    # WEV-AJ-02 should be discovered as compatible alternate
    alt = assessment.alternate_capacities[0]
    assert alt["machine_code"] == wev2.code
    assert alt["capacity_fit"] == "HIGH"


@pytest.mark.django_db
def test_production_impact_agent_grounded_execution(factory_setup):
    """Tests ProductionImpactAgent invocation with deterministic engine grounding."""
    wev1 = factory_setup["wev1"]
    wev_dept = factory_setup["wev_dept"]

    incident = FactoryIncident.objects.create(
        incident_code="INC-TEST-PROD-01",
        factory=factory_setup["factory"],
        department=wev_dept,
        machine=wev1,
        severity=IncidentSeverity.CRITICAL,
        category=IncidentCategory.MACHINE_HEALTH,
        summary="Thermal excursion on main loom drive motor",
    )

    agent = ProductionImpactAgent()
    res = agent.evaluate_production_impact(
        incident_id=incident.id,
        estimated_downtime_hours=2.0,
    )

    assert res["success"] is True
    assert "assessment_code" in res
    assert res["estimated_loss_units"] == 100.0  # 50 units/hr * 2h
    assert res["deterministic_loss_inr"] > 0
    assert "ai_output" in res
    assert "production_disruption_explanation" in res["ai_output"]


@pytest.mark.django_db
def test_production_intelligence_drf_endpoints(factory_setup):
    """Tests DRF endpoints for overview, orders, capacities, bottlenecks, and timeline."""
    client = APIClient()

    # Seed baseline
    ProductionSimulationService.seed_production_baseline()

    # 1. Overview
    r_ov = client.get("/api/v1/production/overview/")
    assert r_ov.status_code == 200
    assert "metrics" in r_ov.data
    assert "department_capacities" in r_ov.data
    assert r_ov.data["metrics"]["total_orders"] >= 6

    # 2. Orders list
    r_ord = client.get("/api/v1/production/orders/")
    assert r_ord.status_code == 200
    orders_data = r_ord.data if isinstance(r_ord.data, list) else r_ord.data.get("results", [])
    assert len(orders_data) >= 6

    # 3. At-risk orders
    r_risk = client.get("/api/v1/production/orders/at-risk/")
    assert r_risk.status_code == 200

    # 4. Department Capacity
    r_cap = client.get("/api/v1/production/department-capacity/")
    assert r_cap.status_code == 200
    assert len(r_cap.data) >= 2

    # 5. Bottlenecks
    r_bot = client.get("/api/v1/production/bottlenecks/")
    assert r_bot.status_code == 200

    # 6. Timeline
    r_time = client.get("/api/v1/production/timeline/")
    assert r_time.status_code == 200
    assert len(r_time.data) >= 6


@pytest.mark.django_db
def test_copilot_grounded_production_queries(factory_setup):
    """Tests Factory AI Copilot grounded answers for production questions."""
    ProductionSimulationService.seed_production_baseline()

    ctx = {
        "production_overview": FactoryContextEngine.get_production_overview(),
        "orders_at_risk": FactoryContextEngine.get_orders_at_risk(),
        "production_bottlenecks": FactoryContextEngine.get_production_bottlenecks(),
    }

    # 1. Production target
    r1 = DeterministicCopilotEngine.generate_grounded_response(
        "What is today's production target?", ctx
    )
    assert "Production Target" in r1["answer"]
    assert len(r1["facts"]) >= 2

    # 2. Orders at risk
    r2 = DeterministicCopilotEngine.generate_grounded_response(
        "Which orders are at risk of delay?", ctx
    )
    assert "Delivery Risk" in r2["answer"] or "Delivery Deadline" in r2["answer"]

    # 3. Department bottleneck
    r3 = DeterministicCopilotEngine.generate_grounded_response(
        "Which department is the production bottleneck?", ctx
    )
    assert "Bottleneck" in r3["answer"]

    # 4. Available capacity
    r4 = DeterministicCopilotEngine.generate_grounded_response(
        "How much production capacity is available?", ctx
    )
    assert "Capacity" in r4["answer"]


@pytest.mark.django_db
def test_simulation_progression_and_breakdown_recovery(factory_setup):
    """Tests advancing production, injecting machine breakdown, and recovery."""
    ProductionSimulationService.seed_production_baseline()

    wev1 = factory_setup["wev1"]

    # 1. Advance production
    adv_res = ProductionSimulationService.advance_production(hours=2.0)
    assert adv_res["success"] is True
    assert adv_res["total_units_produced"] > 0

    # 2. Inject breakdown
    bk_res = ProductionSimulationService.inject_machine_breakdown(
        machine_code=wev1.code, estimated_downtime_hours=3.0
    )
    assert bk_res["success"] is True
    wev1.refresh_from_db()
    assert wev1.status == MachineStatus.CRITICAL

    # 3. Recover machine
    rec_res = ProductionSimulationService.recover_machine(machine_code=wev1.code)
    assert rec_res["success"] is True
    wev1.refresh_from_db()
    assert wev1.status == MachineStatus.OPERATIONAL
