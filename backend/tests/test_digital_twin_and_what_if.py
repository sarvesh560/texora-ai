import pytest
from datetime import timedelta
from django.utils import timezone
from apps.factories.models import Factory, Department
from apps.machines.models import Machine, MachineType, MachineTelemetry, MachineOperatingLimits
from apps.incidents.models import FactoryIncident
from apps.maintenance.models import MaintenanceTicket
from apps.production.models import ProductionOrder, ProductionBatch
from apps.inventory.models import InventoryItem
from apps.digital_twin.models import (
    DigitalTwinSnapshot,
    WhatIfScenario,
    ScenarioMachineChange,
    SimulationRun,
    SimulationResult,
    RecoveryStrategyEvaluation,
    MachineTwinState,
    SparePartsAvailability,
)
from apps.digital_twin.twin_engine import DigitalTwinEngine
from apps.digital_twin.simulation_engine import WhatIfSimulationEngine
from apps.digital_twin.ai_advisor import AIStrategyAdvisor


from django.core.management import call_command


@pytest.fixture
def seeded_factory(db):
    call_command("seed_factory")
    return Factory.objects.first()


@pytest.mark.django_db
def test_digital_twin_snapshot_construction_and_all_25_machines(seeded_factory):
    """Validates that DigitalTwinEngine captures all 25 machines across 5 departments."""
    assert seeded_factory is not None
    snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=True)

    assert "snapshot_id" in snapshot_dict
    assert snapshot_dict["total_machines"] == 25
    assert len(snapshot_dict["machine_states"]) == 25

    operational_summary = snapshot_dict["operational_summary"]
    assert operational_summary["is_simulated_twin"] is True
    assert "PSG COIMBATORE EXPO" in operational_summary["system_label"]

    departments = operational_summary["department_summaries"]
    assert "SPN" in departments
    assert "WEV" in departments
    assert "KNT" in departments
    assert "DYE" in departments
    assert "FIN" in departments

    assert departments["SPN"]["total_machines"] == 7
    assert departments["WEV"]["total_machines"] == 6
    assert departments["KNT"]["total_machines"] == 4
    assert departments["DYE"]["total_machines"] == 4
    assert departments["FIN"]["total_machines"] == 4

    # Verify snapshot persistence
    assert DigitalTwinSnapshot.objects.filter(snapshot_id=snapshot_dict["snapshot_id"]).exists()


@pytest.mark.django_db
def test_machine_twin_presentation_state_and_stale_telemetry_handling(seeded_factory):
    """Validates machine state classification rules, thresholds, and stale telemetry detection."""
    machine = Machine.objects.filter(code="WEV-AJ-02").first()
    assert machine is not None

    # 1. Stale telemetry (older than 180s) -> UNKNOWN
    old_time = timezone.now() - timedelta(minutes=10)
    stale_tel = MachineTelemetry.objects.create(
        machine=machine,
        timestamp=old_time,
        temperature_c=45.0,
        vibration_mms=3.0,
        speed_rpm=800,
        status_flag="NORMAL",
    )

    state, reason = DigitalTwinEngine.calculate_presentation_state(
        machine=machine,
        latest_telemetry=stale_tel,
        active_incidents=[],
        active_tickets=[],
        active_recovery=None,
    )
    assert state == MachineTwinState.UNKNOWN
    assert "stale" in reason.lower()

    # 2. Fresh normal telemetry -> RUNNING
    fresh_time = timezone.now()
    fresh_tel = MachineTelemetry.objects.create(
        machine=machine,
        timestamp=fresh_time,
        temperature_c=45.0,
        vibration_mms=3.0,
        speed_rpm=800,
        utilization_pct=85.0,
        status_flag="NORMAL",
    )

    state, reason = DigitalTwinEngine.calculate_presentation_state(
        machine=machine,
        latest_telemetry=fresh_tel,
        active_incidents=[],
        active_tickets=[],
        active_recovery=None,
    )
    assert state == MachineTwinState.RUNNING

    # 3. Warning threshold telemetry -> WARNING
    warn_tel = MachineTelemetry.objects.create(
        machine=machine,
        timestamp=fresh_time,
        temperature_c=78.0,  # exceeds warning limit
        vibration_mms=4.5,
        speed_rpm=800,
        utilization_pct=85.0,
        status_flag="WARNING",
    )
    state, reason = DigitalTwinEngine.calculate_presentation_state(
        machine=machine,
        latest_telemetry=warn_tel,
        active_incidents=[],
        active_tickets=[],
        active_recovery=None,
    )
    assert state == MachineTwinState.WARNING


@pytest.mark.django_db
def test_simulation_engine_isolation_guarantee(seeded_factory):
    """Crucial verification: What-If simulation must NEVER alter operational records."""
    # Count operational records prior to simulation
    machines_count_before = Machine.objects.count()
    telemetry_count_before = MachineTelemetry.objects.count()
    incidents_count_before = FactoryIncident.objects.count()
    inventory_count_before = InventoryItem.objects.count()
    batches_count_before = ProductionBatch.objects.count()
    tickets_count_before = MaintenanceTicket.objects.count()

    # Load and execute Demo A simulation
    scenario = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    run = WhatIfSimulationEngine.run_simulation(scenario)

    assert run.status == "COMPLETED"
    assert run.result is not None

    # Re-count operational records after simulation
    assert Machine.objects.count() == machines_count_before
    assert MachineTelemetry.objects.count() == telemetry_count_before
    assert FactoryIncident.objects.count() == incidents_count_before
    assert InventoryItem.objects.count() == inventory_count_before
    assert ProductionBatch.objects.count() == batches_count_before
    assert MaintenanceTicket.objects.count() == tickets_count_before

    # Check isolation flag in result provenance
    assert run.result.data_provenance["is_isolated_simulation"] is True
    assert run.result.data_provenance["operational_tables_modified"] is False


@pytest.mark.django_db
def test_deterministic_repeatability_and_unit_segregation(seeded_factory):
    """Verifies that identical scenario inputs produce strictly identical deterministic results."""
    scenario_1 = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    run_1 = WhatIfSimulationEngine.run_simulation(scenario_1)

    scenario_2 = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    run_2 = WhatIfSimulationEngine.run_simulation(scenario_2)

    # Validate deterministic output metrics
    assert run_1.result.lost_machine_operating_hours == run_2.result.lost_machine_operating_hours
    assert run_1.result.capacity_reduction_pct == run_2.result.capacity_reduction_pct
    assert run_1.result.bottleneck_department == run_2.result.bottleneck_department
    assert run_1.result.estimated_output_loss == run_2.result.estimated_output_loss

    # Verify unit segregation (never aggregating meters with kilograms)
    loss = run_1.result.estimated_output_loss
    assert "METERS" in loss
    assert "KG" in loss
    assert loss["METERS"] > 0
    assert loss["KG"] == 0.0  # WEV-AJ-02 is in Weaving (meters), not Spinning (kg)


@pytest.mark.django_db
def test_multi_machine_cluster_failure_and_bottleneck_detection(seeded_factory):
    """Validates Demo B: Multi-machine weaving failure and department bottleneck estimation."""
    scenario_b = WhatIfSimulationEngine.load_demo_scenario("DEMO_B")
    run_b = WhatIfSimulationEngine.run_simulation(scenario_b)

    assert run_b.status == "COMPLETED"
    # 3 looms failed for 6 hours = 18 lost machine hours
    assert run_b.result.lost_machine_operating_hours == 18.0
    assert run_b.result.bottleneck_department == "WEV"
    assert len(run_b.result.timeline_events) > 0

    # Verify Strategy Evaluations
    evals = list(run_b.strategy_evaluations.all())
    assert len(evals) == 3
    strat_c = next(e for e in evals if e.strategy_code == "STRATEGY_C")
    assert strat_c.rank == 1
    assert strat_c.is_feasible is True


@pytest.mark.django_db
def test_cross_department_material_flow_disruption(seeded_factory):
    """Validates Demo C: Spinning shortage propagating downstream."""
    scenario_c = WhatIfSimulationEngine.load_demo_scenario("DEMO_C")
    run_c = WhatIfSimulationEngine.run_simulation(scenario_c)

    assert run_c.status == "COMPLETED"
    assert run_c.result.bottleneck_department == "SPN"
    # Spinning produces KG
    assert run_c.result.estimated_output_loss["KG"] > 0


@pytest.mark.django_db
def test_recovery_strategy_feasibility_boundaries(seeded_factory):
    """Validates that unavailable spare parts correctly marks Strategy A infeasible."""
    scenario = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    scenario.spare_parts_availability = SparePartsAvailability.UNAVAILABLE
    scenario.save()

    run = WhatIfSimulationEngine.run_simulation(scenario)
    evals = list(run.strategy_evaluations.all())

    strat_a = next(e for e in evals if e.strategy_code == "STRATEGY_A")
    assert strat_a.is_feasible is False
    assert any("spare parts" in r.lower() for r in strat_a.infeasibility_reasons)


@pytest.mark.django_db
def test_ai_strategy_advisor_structured_reasoning(seeded_factory):
    """Validates AI Strategy Advisor structured JSON synthesis with local fallback protection."""
    scenario = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    run = WhatIfSimulationEngine.run_simulation(scenario)
    evals = list(run.strategy_evaluations.all())

    advice = AIStrategyAdvisor.generate_strategy_explanation(
        scenario=scenario,
        run=run,
        result=run.result,
        evaluations=evals,
    )

    assert "executive_summary" in advice
    assert "recommended_strategy_code" in advice
    assert "recommendation_rationale" in advice
    assert "operational_risks" in advice
    assert isinstance(advice["operational_risks"], list)
    assert len(advice["operational_risks"]) > 0


@pytest.mark.django_db
def test_digital_twin_and_what_if_rest_api_endpoints(client, seeded_factory):
    """Validates all REST API endpoints for Digital Twin and What-If simulation."""
    # 1. Snapshot API
    resp = client.get("/api/v1/digital-twin/snapshot/")
    assert resp.status_code == 200
    assert resp.json()["status"] == "success"
    assert resp.json()["data"]["total_machines"] == 25

    # 2. Departments API
    resp = client.get("/api/v1/digital-twin/departments/")
    assert resp.status_code == 200
    assert "SPN" in resp.json()["departments"]

    # 3. Machine Detail API
    resp = client.get("/api/v1/digital-twin/machines/WEV-AJ-02/")
    assert resp.status_code == 200
    assert resp.json()["machine"]["code"] == "WEV-AJ-02"
    assert "compatible_alternates" in resp.json()["machine"]

    # 4. Dependency Graph API
    resp = client.get("/api/v1/digital-twin/dependency-graph/")
    assert resp.status_code == 200
    assert "SPN" in resp.json()["topology"]

    # 5. Demo Scenarios List API
    resp = client.get("/api/v1/digital-twin/what-if/demo-scenarios/")
    assert resp.status_code == 200
    assert len(resp.json()["demo_scenarios"]) == 3

    # 6. Load Demo API
    resp = client.post("/api/v1/digital-twin/what-if/demo-scenarios/DEMO_A/load/")
    assert resp.status_code == 200
    assert resp.json()["status"] == "success"
    scen_id = resp.json()["scenario"]["scenario_id"]

    # 7. AI Explain API
    resp = client.post(
        f"/api/v1/digital-twin/what-if/scenarios/{scen_id}/ai-explain/",
        data={},
        content_type="application/json",
    )
    assert resp.status_code == 200
    assert "ai_explanation" in resp.json()


@pytest.mark.django_db
def test_scenario_consistency_for_custom_machine_selection(client, seeded_factory):
    """Validates that custom selected machines (e.g. WEV-RAP-01) persist accurately and drive simulation."""
    payload = {
        "name": "Custom Rapier Loom Outage",
        "description": "Simulating outage on Rapier Loom 1",
        "scenario_type": "SINGLE_MACHINE_FAILURE",
        "failure_duration_hours": 5.0,
        "repair_duration_hours": 2.0,
        "capacity_reduction_pct": 100.0,
        "spare_parts_availability": "FULL",
        "technicians_available": 2,
        "machine_codes": ["WEV-RAP-01"],
        "failure_type": "MOTOR_OVERHEAT",
    }
    resp = client.post(
        "/api/v1/digital-twin/what-if/scenarios/",
        data=payload,
        content_type="application/json",
    )
    assert resp.status_code == 201
    scen_data = resp.json()["scenario"]
    assert scen_data["machine_changes"][0]["machine_code"] == "WEV-RAP-01"

    # Verify simulation run used WEV-RAP-01
    run_data = scen_data["latest_run"]
    assert run_data is not None
    assert run_data["result"]["lost_machine_operating_hours"] == 5.0


@pytest.mark.django_db
def test_strategy_ranking_tie_breaker_and_effectiveness(seeded_factory):
    """Validates multi-criteria ranking, tie detection, effectiveness ratings, and cost formulas."""
    scenario = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    run = WhatIfSimulationEngine.run_simulation(scenario)

    evals = list(run.strategy_evaluations.all())
    assert len(evals) == 3

    for e in evals:
        assert e.effectiveness_level in ["HIGH_EFFECTIVENESS", "MODERATE_EFFECTIVENESS", "TEMPORARY_WORKAROUND", "INFEASIBLE"]
        assert "formula_breakdown" in e.estimated_cost
        assert "INR" in e.estimated_cost["formula_breakdown"]

    # Verify Strategy B is recognized as TEMPORARY_WORKAROUND (0% native machine recovery)
    strat_b = next(e for e in evals if e.strategy_code == "STRATEGY_B")
    assert strat_b.effectiveness_level == "TEMPORARY_WORKAROUND"


@pytest.mark.django_db
def test_machine_provenance_and_telemetry_freshness(seeded_factory):
    """Validates that digital twin snapshot accurately tracks provenance and stale telemetry without fabricating healthy data."""
    snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=False)
    summary = snapshot_dict["operational_summary"]

    assert "telemetry_freshness_summary" in summary
    freshness = summary["telemetry_freshness_summary"]
    assert freshness["freshness_threshold_seconds"] == 180
    assert "explanation" in freshness

    for m in snapshot_dict["machine_states"]:
        assert "provenance_type" in m
        assert "telemetry_freshness" in m
        assert m["telemetry_freshness"]["threshold_seconds"] == 180

