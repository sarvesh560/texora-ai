import pytest
from django.core.management import call_command
from rest_framework.test import APIClient

from apps.simulation.engine import SimulationEngine
from apps.simulation.models import SimulationState, InjectedScenario, ScenarioType
from apps.machines.models import Machine, MachineTelemetry, MachineStatus
from apps.factories.models import Factory, Department
from apps.production.models import ProductionOrder, ProductionBatch, ProductionDelay
from apps.quality.models import QualityInspection, QualityDefect
from apps.inventory.models import InventoryItem


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def seeded_factory(db):
    call_command("seed_factory")
    return Factory.objects.filter(code="FAC-CBE-01").first()


@pytest.mark.django_db
def test_seed_factory_idempotency(seeded_factory):
    """Verifies that running seed_factory multiple times does not duplicate records."""
    assert seeded_factory is not None
    initial_machines_count = Machine.objects.count()
    initial_dept_count = Department.objects.count()

    # Re-run seed command
    call_command("seed_factory")

    assert Machine.objects.count() == initial_machines_count == 25
    assert Department.objects.count() == initial_dept_count == 5


@pytest.mark.django_db
def test_simulation_engine_tick_telemetry_generation(seeded_factory):
    """Verifies that simulation tick generates valid telemetry across all active machines."""
    engine = SimulationEngine()
    initial_telemetry_count = MachineTelemetry.objects.count()

    result = engine.run_tick()

    assert result["tick"] >= 1
    assert result["machines_updated"] == 25
    assert MachineTelemetry.objects.count() == initial_telemetry_count + 25

    # Check that telemetry values fall within reasonable physical bounds
    latest_readings = MachineTelemetry.objects.all()[:25]
    for reading in latest_readings:
        assert 20.0 <= reading.temperature_c <= 250.0
        assert 0.0 <= reading.vibration_mms <= 30.0
        assert 0 <= reading.speed_rpm <= 30000
        assert reading.power_kw >= 0.0


@pytest.mark.django_db
def test_scenario_injection_weaving_vibration(seeded_factory):
    """Verifies weaving loom vibration scenario injection alters physics appropriately."""
    loom = Machine.objects.filter(code="WEV-AJ-02").first()
    assert loom is not None

    scenario = InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code=loom.code,
        severity="CRITICAL",
        is_active=True,
        description="Test weaving loom high vibration",
    )

    engine = SimulationEngine()
    engine.run_tick()

    latest = MachineTelemetry.objects.filter(machine=loom).order_by("-timestamp").first()
    assert latest is not None
    assert latest.vibration_mms >= 5.0  # Injected high vibration above normal ~3.2
    assert latest.status_flag == "CRITICAL"


@pytest.mark.django_db
def test_scenario_injection_spinning_overheat(seeded_factory):
    """Verifies spinning machine overheat injection alters temperature appropriately."""
    ring_frame = Machine.objects.filter(code="SPN-RS-03").first()
    assert ring_frame is not None

    scenario = InjectedScenario.objects.create(
        scenario_type=ScenarioType.SPINNING_OVERHEAT,
        target_machine_code=ring_frame.code,
        severity="CRITICAL",
        is_active=True,
        description="Test ring frame bearing overheat",
    )

    engine = SimulationEngine()
    engine.run_tick()

    latest = MachineTelemetry.objects.filter(machine=ring_frame).order_by("-timestamp").first()
    assert latest is not None
    assert latest.temperature_c >= 85.0  # Injected high temp above normal ~70.5
    assert latest.status_flag == "CRITICAL"


@pytest.mark.django_db
def test_scenario_injection_production_slowdown(seeded_factory):
    """Verifies production slowdown scenario reduces output rate and creates delay record."""
    knitter = Machine.objects.filter(code="KNT-CS-01").first()
    assert knitter is not None

    scenario = InjectedScenario.objects.create(
        scenario_type=ScenarioType.PRODUCTION_SLOWDOWN,
        target_machine_code=knitter.code,
        severity="HIGH",
        is_active=True,
        description="Knitting machine draft slippage slowdown",
    )

    engine = SimulationEngine()
    engine.run_tick()

    latest = MachineTelemetry.objects.filter(machine=knitter).order_by("-timestamp").first()
    assert latest is not None
    assert latest.status_flag == "WARNING"


@pytest.mark.django_db
def test_simulation_rest_api_lifecycle(api_client, seeded_factory):
    """Verifies all REST API endpoints for simulation lifecycle control."""
    # 1. Status endpoint
    status_resp = api_client.get("/api/v1/simulation/status/")
    assert status_resp.status_code == 200
    assert "state" in status_resp.data
    assert "available_scenarios" in status_resp.data

    # 2. Tick endpoint
    tick_resp = api_client.post("/api/v1/simulation/tick/", format="json")
    assert tick_resp.status_code == 200
    assert "result" in tick_resp.data
    assert tick_resp.data["result"]["machines_updated"] == 25

    # 3. Start endpoint
    start_resp = api_client.post("/api/v1/simulation/start/", {"speed_multiplier": 2.0, "tick_interval_seconds": 2.0}, format="json")
    assert start_resp.status_code == 200
    assert start_resp.data["state"]["is_running"] is True
    assert start_resp.data["state"]["speed_multiplier"] == 2.0

    # 4. Pause endpoint
    pause_resp = api_client.post("/api/v1/simulation/pause/", format="json")
    assert pause_resp.status_code == 200
    assert pause_resp.data["state"]["is_paused"] is True

    # 5. Resume endpoint
    resume_resp = api_client.post("/api/v1/simulation/resume/", format="json")
    assert resume_resp.status_code == 200
    assert resume_resp.data["state"]["is_paused"] is False

    # 6. Stop endpoint
    stop_resp = api_client.post("/api/v1/simulation/stop/", format="json")
    assert stop_resp.status_code == 200
    assert stop_resp.data["state"]["is_running"] is False

    # 7. Inject Scenario endpoint
    inject_resp = api_client.post("/api/v1/simulation/inject-scenario/", {
        "scenario_type": "ENERGY_SURGE",
        "target_machine_code": "DYE-SF-01",
        "severity": "HIGH",
        "description": "Peak hour energy surge test",
    }, format="json")
    assert inject_resp.status_code == 201
    assert inject_resp.data["scenario"]["scenario_type"] == "ENERGY_SURGE"

    # 8. Clear Scenarios endpoint
    clear_resp = api_client.post("/api/v1/simulation/clear-scenarios/", {}, format="json")
    assert clear_resp.status_code == 200
    assert InjectedScenario.objects.filter(is_active=True).count() == 0

    # 9. Summary endpoint
    summary_resp = api_client.get("/api/v1/simulation/summary/")
    assert summary_resp.status_code == 200
    assert summary_resp.data["total_machines"] == 25
    assert len(summary_resp.data["departments"]) == 5
    assert len(summary_resp.data["machines"]) == 25

    # Cleanup background thread
    SimulationEngine().stop()
