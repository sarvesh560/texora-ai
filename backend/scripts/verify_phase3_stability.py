import os
import sys
import time
import json
import threading
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.abspath("backend"))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.development")
import django
django.setup()

from apps.machines.models import Machine, MachineTelemetry, MachineStatus
from apps.simulation.models import SimulationState, InjectedScenario, ScenarioType
from apps.simulation.engine import SimulationEngine


def run_verification():
    print("=" * 80)
    print("  TEXORA AI — PHASE 3 STABILITY & SIMULATION VERIFICATION")
    print("=" * 80)

    # 1. Check Seeding & Machine Count
    total_machines = Machine.objects.filter(is_active=True).count()
    print(f"[CHECK 1] Active Factory Machines in Database: {total_machines} machines (Expected: 25)")
    assert total_machines == 25, f"Expected 25 machines, got {total_machines}"

    # 2. Record Baseline Telemetry Count & Timestamp
    initial_count = MachineTelemetry.objects.count()
    latest_initial = MachineTelemetry.objects.order_by("-timestamp").first()
    initial_ts = latest_initial.timestamp.isoformat() if latest_initial else "None"
    initial_state = SimulationState.get_state()
    initial_ticks = initial_state.total_ticks_generated
    print(f"[CHECK 2] Baseline Telemetry Count: {initial_count} records (Total monotonic ticks: {initial_ticks})")
    print(f"          Latest Telemetry Timestamp: {initial_ts}")

    # 3. Start Simulation Engine and Run for 30 Seconds
    print("\n[CHECK 3] Starting Simulation Engine (interval: 2.0s, speed: 1.0x)...")
    engine = SimulationEngine()
    engine.start(speed_multiplier=1.0, tick_interval=2.0)
    print("          Engine worker thread is alive:", engine.is_active())
    print("          Waiting 30 seconds for live telemetry generation...")

    # During the 30 seconds, concurrently query health endpoints to verify concurrency
    health_latencies = []
    ready_latencies = []

    def ping_health():
        t0 = time.time()
        try:
            req = urllib.request.urlopen("http://127.0.0.1:8000/api/v1/health/", timeout=5)
            health_latencies.append((time.time() - t0) * 1000)
        except Exception as e:
            health_latencies.append(-1)

    def ping_ready():
        t0 = time.time()
        try:
            req = urllib.request.urlopen("http://127.0.0.1:8000/api/v1/health/readiness/", timeout=5)
            ready_latencies.append((time.time() - t0) * 1000)
        except Exception as e:
            ready_latencies.append(-1)

    # Concurrency test during the 30s window
    start_time = time.time()
    while time.time() - start_time < 30.0:
        time.sleep(2.5)
        with ThreadPoolExecutor(max_workers=5) as pool:
            for _ in range(5):
                pool.submit(ping_health)
                pool.submit(ping_ready)

    post_30s_count = MachineTelemetry.objects.count()
    latest_30s = MachineTelemetry.objects.order_by("-timestamp").first()
    ts_30s = latest_30s.timestamp.isoformat() if latest_30s else "None"
    post_state = SimulationState.get_state()
    ticks_generated = post_state.total_ticks_generated - initial_ticks

    print(f"\n[CHECK 3 RESULT] Telemetry Table Rows (with 2500 auto-pruning window): {post_30s_count} records")
    print(f"                 Total Ticks Generated: {post_state.total_ticks_generated} (+{ticks_generated} ticks in 30s)")
    print(f"                 New Latest Timestamp: {ts_30s}")
    assert ticks_generated > 0, "No new simulation ticks generated during 30s window!"
    assert ts_30s != initial_ts, "Timestamp did not advance during 30s window!"

    # 4. Check Concurrency & SQLite Locks
    valid_health = [l for l in health_latencies if l > 0]
    valid_ready = [l for l in ready_latencies if l > 0]
    avg_health_ms = sum(valid_health) / len(valid_health) if valid_health else 0
    avg_ready_ms = sum(valid_ready) / len(valid_ready) if valid_ready else 0
    failed_requests = len(health_latencies) + len(ready_latencies) - len(valid_health) - len(valid_ready)

    print(f"\n[CHECK 4] Concurrent Health Requests: {len(health_latencies)} requests | Avg Latency: {avg_health_ms:.2f}ms")
    print(f"          Concurrent Readiness Requests: {len(ready_latencies)} requests | Avg Latency: {avg_ready_ms:.2f}ms")
    print(f"          Failed / Blocked Requests: {failed_requests} (Expected: 0)")
    assert failed_requests == 0, f"Encountered {failed_requests} failed requests under load!"

    # 5. Verify Pause Operation
    print("\n[CHECK 5] Testing PAUSE operation...")
    engine.pause()
    time.sleep(1.0)
    pause_ticks_1 = SimulationState.get_state().total_ticks_generated
    time.sleep(4.0)
    pause_ticks_2 = SimulationState.get_state().total_ticks_generated
    print(f"          Ticks at pause: {pause_ticks_1} | Ticks 4s later: {pause_ticks_2}")
    assert pause_ticks_1 == pause_ticks_2, "Ticks continued generating while paused!"
    print("          [OK] Simulation successfully paused.")

    # 6. Verify Resume Operation
    print("\n[CHECK 6] Testing RESUME operation...")
    engine.resume()
    time.sleep(4.5)
    resume_ticks = SimulationState.get_state().total_ticks_generated
    print(f"          Ticks after 4.5s resume: {resume_ticks} (Delta: +{resume_ticks - pause_ticks_2})")
    assert resume_ticks > pause_ticks_2, "Ticks failed to generate upon resuming!"
    print("          [OK] Simulation successfully resumed.")

    # 7. Verify Stop Operation
    print("\n[CHECK 7] Testing STOP operation...")
    engine.stop()
    time.sleep(2.0)
    stop_ticks_1 = SimulationState.get_state().total_ticks_generated
    time.sleep(4.0)
    stop_ticks_2 = SimulationState.get_state().total_ticks_generated
    print(f"          Ticks at stop: {stop_ticks_1} | Ticks 4s later: {stop_ticks_2}")
    assert stop_ticks_1 == stop_ticks_2, "Ticks continued generating after stop!"
    print("          [OK] Simulation successfully stopped.")

    # 8. Verify Duplicate Worker Prevention
    print("\n[CHECK 8] Testing Duplicate Worker Prevention...")
    engine.start(speed_multiplier=1.0, tick_interval=3.0)
    first_thread = engine._thread
    # Attempt second start
    engine.start(speed_multiplier=2.0, tick_interval=1.0)
    second_thread = engine._thread
    assert first_thread is second_thread, "Duplicate thread spawned on second start()!"
    print("          [OK] Duplicate worker prevention verified: engine is singleton and reuses active thread.")
    engine.stop()

    # 9. Verify Scenario Injection & Physics Alteration
    print("\n[CHECK 9] Testing Scenario Injection Physics Impact...")
    loom = Machine.objects.filter(code="WEV-AJ-02").first()
    assert loom is not None

    scenario = InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code=loom.code,
        severity="CRITICAL",
        is_active=True,
        description="Verification Test: Weaving Loom Bearing Wear",
    )

    # Run discrete tick
    res = engine.run_tick()
    target_telem = MachineTelemetry.objects.filter(machine=loom).order_by("-timestamp").first()

    print(f"          Machine {loom.code} Telemetry:")
    print(f"            * Vibration:   {target_telem.vibration_mms} mm/s (Normal: ~3.2 mm/s, Warning Threshold: 4.0 mm/s)")
    print(f"            * Status Flag: {target_telem.status_flag} (Expected: CRITICAL)")
    assert target_telem.vibration_mms >= 5.5, f"Expected vibration >= 5.5 mm/s, got {target_telem.vibration_mms}"
    assert target_telem.status_flag == "CRITICAL"
    print("          [OK] Scenario injection successfully alters physics and sets CRITICAL flag.")

    # Clear scenario
    scenario.is_active = False
    scenario.save()

    print("\n" + "=" * 80)
    print("  ALL 9 PHASE 3 STABILITY & SIMULATION CHECKS PASSED (100%)")
    print("=" * 80)


if __name__ == "__main__":
    run_verification()
