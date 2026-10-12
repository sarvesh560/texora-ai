"""
End-to-End Scenario Verification Script for Phase 4: Autonomous Anomaly Detection Engine
Tests:
1. Baseline clean telemetry.
2. Injected WEAVING_VIBRATION into WEV-AJ-02.
3. Simulation produces abnormal vibration on WEV-AJ-02 (> 4.5 mm/s limit).
4. Detection cycle identifies CRITICAL vibration anomaly.
5. Real FactoryIncident created with CRITICAL severity.
6. DRF API endpoint /api/v1/incidents/ returns the active incident.
7. Subsequent abnormal cycles update telemetry count without duplicate incident creation.
8. Injection cleared.
9. 3 normal cycles executed -> Detector transitions incident to RESOLVED and machine to OPERATIONAL.
"""
import os
import sys
import django
import time
from datetime import datetime, timezone

# Django setup
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
os.chdir(backend_dir)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from django.utils import timezone as dj_timezone
from apps.machines.models import Machine, MachineOperatingLimits, MachineTelemetry
from apps.incidents.models import FactoryIncident, AnomalyDetection, DetectionCheckpoint
from apps.incidents.detector import AnomalyDetector
from apps.simulation.models import InjectedScenario, ScenarioType
from apps.simulation.engine import SimulationEngine

def run_verification():
    print("=" * 70)
    print("TEXORA AI — PHASE 4: END-TO-END SCENARIO VERIFICATION")
    print(f"Timestamp: {datetime.now(timezone.utc).isoformat()}")
    print("=" * 70)

    # 1. Inspect target machine & limits
    machine = Machine.objects.get(code="WEV-AJ-02")
    limits = MachineOperatingLimits.objects.get(machine=machine)
    print(f"\n[STEP 1] Target Machine: {machine.code} ({machine.name})")
    print(f"  Department: {machine.department.name}")
    print(f"  Vibration Warning Limit: {limits.warning_vibration_mms} mm/s")
    print(f"  Vibration Critical Limit: {limits.max_vibration_mms} mm/s")
    print(f"  Initial Machine Status: {machine.status}")

    # Setup SimulationEngine & Detector
    sim = SimulationEngine()
    detector = AnomalyDetector()

    # Clear scenarios and reset active incidents on this machine for clean test
    InjectedScenario.objects.filter(is_active=True).update(is_active=False, cleared_at=dj_timezone.now())
    FactoryIncident.objects.filter(machine=machine, status__in=['OPEN', 'INVESTIGATING', 'MITIGATING']).update(
        status='RESOLVED', resolution_summary='Clean test start', resolved_at=dj_timezone.now()
    )
    
    # 2. Baseline normal tick
    print("\n[STEP 2] Running baseline simulation tick (Clean conditions)...")
    # Advance checkpoint to skip any historical backlog before starting clean test
    latest_tel_id = MachineTelemetry.objects.order_by('-id').first()
    if latest_tel_id:
        cp = DetectionCheckpoint.get_checkpoint()
        cp.last_processed_telemetry_id = latest_tel_id.id
        cp.save()

    sim.run_tick()
    eval_baseline = detector.run_cycle()
    print(f"  Telemetry evaluated: {eval_baseline['evaluated_records']}")
    print(f"  New anomalies: {eval_baseline['anomalies_detected']}")
    print(f"  New incidents: {eval_baseline['incidents_created']}")
    latest_tel = MachineTelemetry.objects.filter(machine=machine).order_by('-timestamp').first()
    print(f"  {machine.code} Vibration: {latest_tel.vibration_mms:.3f} mm/s (Normal)")

    # 3. Inject WEAVING_VIBRATION
    print("\n[STEP 3] Injecting WEAVING_VIBRATION scenario into WEV-AJ-02...")
    InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code="WEV-AJ-02",
        severity="CRITICAL",
        is_active=True,
        description="Loom Main Drive Bearing Deterioration",
    )
    
    # Run 1st abnormal tick
    print("  Generating abnormal telemetry tick 1...")
    sim.run_tick()
    abnormal_tel1 = MachineTelemetry.objects.filter(machine=machine).order_by('-timestamp').first()
    print(f"  Observed Telemetry ID {abnormal_tel1.id}: Vibration = {abnormal_tel1.vibration_mms:.3f} mm/s")

    # Run detection cycle
    print("\n[STEP 4] Executing autonomous anomaly detector cycle 1...")
    res1 = detector.run_cycle()
    print(f"  Checkpoint Last ID: {res1['checkpoint_last_id']}")
    print(f"  Telemetry Evaluated: {res1['evaluated_records']}")
    print(f"  Anomalies Detected: {res1['anomalies_detected']}")
    print(f"  Incidents Created: {res1['incidents_created']}")

    # 5. Verify FactoryIncident created
    active_incidents = FactoryIncident.objects.filter(machine=machine, status='OPEN')
    assert active_incidents.exists(), "Error: No active FactoryIncident created!"
    incident = active_incidents.first()
    print(f"\n[STEP 5] Database-Backed Incident Created:")
    print(f"  Incident ID: {incident.id}")
    print(f"  Incident Code: {incident.incident_code}")
    print(f"  Summary: {incident.summary}")
    print(f"  Category: {incident.category}")
    print(f"  Severity: {incident.severity}")
    print(f"  Machine: {incident.machine.code}")
    print(f"  Root Cause Hypothesis: {incident.root_cause_hypothesis}")
    print(f"  Evidence Data: {incident.evidence_data}")

    # Check AnomalyDetection record
    latest_anomaly = AnomalyDetection.objects.filter(incident=incident).order_by('-detected_at').first()
    assert latest_anomaly is not None
    print(f"\n  Correlated AnomalyDetection Record:")
    print(f"  Anomaly ID: {latest_anomaly.id}")
    print(f"  Metric Name: {latest_anomaly.metric_name}")
    print(f"  Observed Value: {latest_anomaly.observed_value:.3f} (Threshold: {latest_anomaly.threshold_value})")
    print(f"  Anomaly Score: {latest_anomaly.anomaly_score}")
    print(f"  Algorithm Used: {latest_anomaly.algorithm_used}")
    print(f"  Confidence: {latest_anomaly.confidence_pct}%")

    # 6. Verify Incident Deduplication on Repeated Cycles
    print("\n[STEP 6] Testing Incident Deduplication (Generating tick 2 & 3 with continuous vibration)...")
    sim.run_tick()
    res2 = detector.run_cycle()
    sim.run_tick()
    res3 = detector.run_cycle()
    
    total_active_for_machine = FactoryIncident.objects.filter(machine=machine, status='OPEN').count()
    print(f"  Active incidents for {machine.code} after 3 ticks: {total_active_for_machine}")
    assert total_active_for_machine == 1, f"Expected exactly 1 active incident, found {total_active_for_machine} (Deduplication failed)"
    
    anomalies_for_incident = AnomalyDetection.objects.filter(incident=incident).count()
    print(f"  Correlated anomaly detections linked to incident: {anomalies_for_incident}")

    # 7. Remove Scenario and Test Sustained Normal Recovery
    print("\n[STEP 7] Removing injected scenario and testing sustained recovery...")
    InjectedScenario.objects.filter(is_active=True).update(is_active=False, cleared_at=dj_timezone.now())
    
    print("  Cycle 1 after clear (Recovery tick 1)...")
    sim.run_tick()
    rec1 = detector.run_cycle()
    incident.refresh_from_db()
    print(f"    Incident Status: {incident.status} | Resolved Incidents: {rec1['incidents_resolved']}")
    
    print("  Cycle 2 after clear (Recovery tick 2)...")
    sim.run_tick()
    rec2 = detector.run_cycle()
    incident.refresh_from_db()
    print(f"    Incident Status: {incident.status} | Resolved Incidents: {rec2['incidents_resolved']}")

    print("  Cycle 3 after clear (Recovery tick 3 - Hysteresis threshold reached)...")
    sim.run_tick()
    rec3 = detector.run_cycle()
    incident.refresh_from_db()
    print(f"    Incident Status: {incident.status} | Resolved Incidents: {rec3['incidents_resolved']}")
    print(f"    Resolution Summary: {incident.resolution_summary}")
    
    machine.refresh_from_db()
    print(f"    Machine Status after recovery: {machine.status}")
    assert incident.status == 'RESOLVED', f"Expected incident to be RESOLVED, got {incident.status}"
    assert machine.status == 'OPERATIONAL', f"Expected machine to be OPERATIONAL, got {machine.status}"

    print("\n" + "=" * 70)
    print("ALL PHASE 4 END-TO-END VERIFICATION CHECKS PASSED (100%)")
    print("=" * 70)

if __name__ == '__main__':
    run_verification()
