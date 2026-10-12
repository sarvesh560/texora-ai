import pytest
from django.core.management import call_command
from django.utils import timezone
from rest_framework.test import APIClient

from apps.machines.models import Machine, MachineTelemetry, MachineStatus
from apps.factories.models import Factory, Department
from apps.incidents.models import (
    FactoryIncident,
    AnomalyDetection,
    DetectionCheckpoint,
    IncidentSeverity,
    IncidentStatus,
    IncidentCategory,
)
from apps.incidents.detector import AnomalyDetector
from apps.simulation.engine import SimulationEngine
from apps.simulation.models import InjectedScenario, ScenarioType


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def seeded_factory(db):
    call_command("seed_factory")
    return Factory.objects.filter(code="FAC-CBE-01").first()


@pytest.mark.django_db
def test_detection_checkpoint_initialization_and_advancement(seeded_factory):
    """Verifies that checkpoint initializes and advances monotonically as new telemetry is processed."""
    checkpoint = DetectionCheckpoint.get_checkpoint()
    assert checkpoint is not None
    initial_last_id = checkpoint.last_processed_telemetry_id

    # Generate 1 simulation tick (25 records)
    sim_engine = SimulationEngine()
    sim_engine.run_tick()

    detector = AnomalyDetector()
    res = detector.run_cycle(batch_size=100)

    assert res["evaluated_records"] == 25
    checkpoint.refresh_from_db()
    assert checkpoint.last_processed_telemetry_id > initial_last_id
    assert checkpoint.total_telemetry_processed == 25


@pytest.mark.django_db
def test_vibration_anomaly_detection_and_incident_creation(seeded_factory):
    """Verifies that sustained excessive vibration triggers AnomalyDetection and FactoryIncident."""
    loom = Machine.objects.filter(code="WEV-AJ-02").first()
    assert loom is not None
    limits = loom.operating_limits

    # Inject weaving vibration scenario and run simulation tick
    InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code=loom.code,
        severity="CRITICAL",
        is_active=True,
        description="Loom bearing failure vibration",
    )

    sim_engine = SimulationEngine()
    sim_engine.run_tick()

    detector = AnomalyDetector()
    res = detector.run_cycle(batch_size=100)

    assert res["anomalies_detected"] >= 1
    assert res["incidents_created"] >= 1

    # Verify incident
    incident = FactoryIncident.objects.filter(machine=loom, status=IncidentStatus.OPEN).first()
    assert incident is not None
    assert incident.category == IncidentCategory.MACHINE_HEALTH
    assert incident.severity == IncidentSeverity.CRITICAL
    assert "vibration" in incident.summary.lower()
    assert len(incident.anomalies.all()) >= 1

    # Verify anomaly record
    anomaly = incident.anomalies.first()
    assert anomaly.metric_name == "vibration_mms"
    assert anomaly.observed_value >= limits.max_vibration_mms


@pytest.mark.django_db
def test_incident_deduplication_on_repeated_anomalies(seeded_factory):
    """Verifies that multiple consecutive abnormal ticks update existing incident without creating duplicates."""
    ring_frame = Machine.objects.filter(code="SPN-RS-03").first()
    assert ring_frame is not None

    InjectedScenario.objects.create(
        scenario_type=ScenarioType.SPINNING_OVERHEAT,
        target_machine_code=ring_frame.code,
        severity="CRITICAL",
        is_active=True,
        description="Ring frame spindle bearing thermal runaway",
    )

    sim_engine = SimulationEngine()
    detector = AnomalyDetector()

    # Tick 1 -> Creates incident
    sim_engine.run_tick()
    res1 = detector.run_cycle(batch_size=100)
    assert res1["incidents_created"] == 1
    assert FactoryIncident.objects.filter(machine=ring_frame, status=IncidentStatus.OPEN).count() == 1

    # Tick 2 -> Updates existing incident (NO duplicate)
    sim_engine.run_tick()
    res2 = detector.run_cycle(batch_size=100)
    assert res2["incidents_created"] == 0
    assert res2["incidents_updated"] == 1
    assert FactoryIncident.objects.filter(machine=ring_frame, status=IncidentStatus.OPEN).count() == 1

    # Tick 3 -> Updates existing incident (NO duplicate)
    sim_engine.run_tick()
    res3 = detector.run_cycle(batch_size=100)
    assert res3["incidents_created"] == 0
    assert res3["incidents_updated"] == 1
    assert FactoryIncident.objects.filter(machine=ring_frame, status=IncidentStatus.OPEN).count() == 1

    incident = FactoryIncident.objects.filter(machine=ring_frame, status=IncidentStatus.OPEN).first()
    evidence_history = incident.evidence_data.get("anomaly_history", [])
    assert len(evidence_history) == 3


@pytest.mark.django_db
def test_sustained_normal_recovery_lifecycle(seeded_factory):
    """Verifies that sustained normal telemetry over 3 cycles resolves active incident."""
    loom = Machine.objects.filter(code="WEV-AJ-02").first()
    scenario = InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code=loom.code,
        severity="CRITICAL",
        is_active=True,
        description="Loom vibration",
    )

    sim_engine = SimulationEngine()
    detector = AnomalyDetector()

    # Create active incident with abnormal telemetry
    sim_engine.run_tick()
    detector.run_cycle()

    incident = FactoryIncident.objects.filter(machine=loom, status=IncidentStatus.OPEN).first()
    assert incident is not None

    # Clear scenario and simulate 3 normal ticks
    scenario.is_active = False
    scenario.save()

    for _ in range(3):
        sim_engine.run_tick()
        detector.run_cycle()

    # Verify incident transitioned to RESOLVED
    incident.refresh_from_db()
    assert incident.status == IncidentStatus.RESOLVED
    assert incident.resolved_at is not None
    assert "recovery" in incident.resolution_summary.lower()

    # Verify machine returned to OPERATIONAL
    loom.refresh_from_db()
    assert loom.status == MachineStatus.OPERATIONAL


@pytest.mark.django_db
def test_incident_rest_apis(api_client, seeded_factory):
    """Verifies REST endpoints for detector status, summary, and incident resolution."""
    # 1. Detector status
    status_resp = api_client.get("/api/v1/incidents/detector-status/")
    assert status_resp.status_code == 200
    assert "checkpoint" in status_resp.data

    # 2. Run manual evaluation
    eval_resp = api_client.post("/api/v1/incidents/run-eval/", {"batch_size": 50}, format="json")
    assert eval_resp.status_code == 200
    assert "result" in eval_resp.data

    # 3. Inject and detect to create an incident
    loom = Machine.objects.filter(code="WEV-AJ-02").first()
    InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code=loom.code,
        is_active=True,
    )
    SimulationEngine().run_tick()
    AnomalyDetector().run_cycle()

    # 4. Summary endpoint
    summary_resp = api_client.get("/api/v1/incidents/summary/")
    assert summary_resp.status_code == 200
    assert summary_resp.data["total_active_incidents"] >= 1
    assert "severity_breakdown" in summary_resp.data
    assert len(summary_resp.data["active_incidents"]) >= 1

    # 5. List incidents
    inc_list_resp = api_client.get("/api/v1/incidents/")
    assert inc_list_resp.status_code == 200
    assert len(inc_list_resp.data["results"] if "results" in inc_list_resp.data else inc_list_resp.data) >= 1

    # 6. Manual resolve action
    inc_id = summary_resp.data["active_incidents"][0]["id"]
    resolve_resp = api_client.post(f"/api/v1/incidents/{inc_id}/resolve/", {
        "resolution_notes": "Operator inspected bearings and confirmed lubrication applied."
    }, format="json")
    assert resolve_resp.status_code == 200
    assert resolve_resp.data["status"] == "RESOLVED"
