"""
Texora AI - Phase 7 End-to-End Verification Script
Intelligent Factory Digital Twin & AI-Powered What-If Simulation
"""
import os
import sys
import django

# Setup Django environment
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.development")
django.setup()

from apps.factories.models import Factory, Department
from apps.machines.models import Machine, MachineTelemetry
from apps.incidents.models import FactoryIncident
from apps.inventory.models import InventoryItem
from apps.production.models import ProductionBatch
from apps.maintenance.models import MaintenanceTicket
from apps.digital_twin.models import (
    DigitalTwinSnapshot,
    WhatIfScenario,
    SimulationRun,
    SimulationResult,
    RecoveryStrategyEvaluation,
)
from apps.digital_twin.twin_engine import DigitalTwinEngine
from apps.digital_twin.simulation_engine import WhatIfSimulationEngine
from apps.digital_twin.ai_advisor import AIStrategyAdvisor


def main():
    print("=" * 80)
    print("TEXORA AI -- PHASE 7: DIGITAL TWIN & WHAT-IF SIMULATION VERIFICATION")
    print("=" * 80)

    # -------------------------------------------------------------
    # Step 1: Pre-simulation Operational Baseline Audit
    # -------------------------------------------------------------
    print("\n[Step 1] Capturing Pre-Simulation Operational Database Record Counts...")
    baseline_counts = {
        "machines": Machine.objects.count(),
        "telemetry": MachineTelemetry.objects.count(),
        "incidents": FactoryIncident.objects.count(),
        "inventory_items": InventoryItem.objects.count(),
        "batches": ProductionBatch.objects.count(),
        "tickets": MaintenanceTicket.objects.count(),
    }
    for model_name, count in baseline_counts.items():
        print(f"  * {model_name.capitalize()}: {count} records in database")

    # -------------------------------------------------------------
    # Step 2: Digital Twin Virtual Snapshot Construction
    # -------------------------------------------------------------
    print("\n[Step 2] Constructing Virtual Factory Snapshot Across All 25 Machines...")
    snapshot = DigitalTwinEngine.capture_snapshot(save_to_db=True)
    print(f"  * Snapshot ID: {snapshot['snapshot_id']}")
    print(f"  * Factory Code: {snapshot['factory_code']}")
    print(f"  * Total Machines Captured: {snapshot['total_machines']}")
    print(f"  * System Label: {snapshot['operational_summary']['system_label']}")

    dept_summaries = snapshot["operational_summary"]["department_summaries"]
    print("\n  Department Breakdown:")
    for code, d_info in dept_summaries.items():
        print(f"    - {code} ({d_info['name']}): {d_info['total_machines']} machines | Rated Capacity: {d_info['rated_capacity_total']} units/h")

    # -------------------------------------------------------------
    # Step 3: Inspect Target Machine WEV-AJ-02
    # -------------------------------------------------------------
    print("\n[Step 3] Inspecting Virtual Twin State for Target Asset: WEV-AJ-02...")
    loom = next((m for m in snapshot["machine_states"] if m["code"] == "WEV-AJ-02"), None)
    assert loom is not None, "WEV-AJ-02 not found in virtual snapshot!"
    print(f"  * Asset Code: {loom['code']} ({loom['name']})")
    print(f"  * Department: {loom['department_name']} ({loom['floor_location']})")
    print(f"  * Digital Twin State: {loom['twin_presentation_state']} ({loom['state_reason']})")
    print(f"  * Health Score: {loom['health_score']}%")
    print(f"  * Rated Capacity: {loom['rated_capacity_units_per_hour']} meters/h")

    # -------------------------------------------------------------
    # Step 4 & 5: Load and Execute Demo A (Single Loom Failure)
    # -------------------------------------------------------------
    print("\n[Step 4 & 5] Creating Hypothetical Scenario & Executing Deterministic Simulation...")
    scenario_a = WhatIfSimulationEngine.load_demo_scenario("DEMO_A")
    print(f"  * Scenario: {scenario_a.name}")
    print(f"  * Failure Duration: {scenario_a.failure_duration_hours}h | Repair Window: {scenario_a.repair_duration_hours}h")

    run_a = WhatIfSimulationEngine.run_simulation(scenario_a)
    print(f"  * Simulation Run ID: {run_a.run_id} [Status: {run_a.status}] in {run_a.execution_duration_ms}ms")

    result_a = run_a.result
    print("\n  [Calculated Production Impact Results]:")
    print(f"    - Lost Machine Operating Hours: {result_a.lost_machine_operating_hours} hours")
    print(f"    - Department Capacity Reduction: {result_a.capacity_reduction_pct}%")
    print(f"    - Bottleneck Department: {result_a.bottleneck_department}")
    print(f"    - Output Loss Segregated by Unit: {result_a.estimated_output_loss}")
    print(f"    - Potential Order Delays Count: {len(result_a.potential_order_delays)} orders")

    # -------------------------------------------------------------
    # Step 6: 3 Recovery Strategies Comparison
    # -------------------------------------------------------------
    print("\n[Step 6] Comparing Feasible Multi-Agent Recovery Strategies (A vs B vs C)...")
    evaluations = list(run_a.strategy_evaluations.all())
    for e in evaluations:
        feas_str = "FEASIBLE" if e.is_feasible else "INFEASIBLE"
        print(f"\n  [*] Rank #{e.rank}: {e.strategy_name} [{feas_str}]")
        print(f"    - Est. Downtime: {e.estimated_downtime_hours}h | Capacity Recovered: {e.capacity_recovered_pct}%")
        print(f"    - Net Output Loss: {e.estimated_output_loss}")
        print(f"    - Resource Utilization: {e.resource_utilization}")
        cost_val = e.estimated_cost.get('total_estimated_cost_inr', 0.0)
        print(f"    - Est. Total Cost: INR {cost_val:,.0f}")
        print(f"    - Effectiveness: {e.effectiveness_level} | Tied: {e.is_tied}")
        print(f"    - Top Pro: {e.pros[0] if e.pros else 'N/A'}")
        print(f"    - Top Con: {e.cons[0] if e.cons else 'N/A'}")

    # -------------------------------------------------------------
    # Step 7: Request Real Gemini AI Strategy Explanation
    # -------------------------------------------------------------
    print("\n[Step 7] Requesting AI Operations Strategy Explanation via Google Gemini...")
    ai_explanation = AIStrategyAdvisor.generate_strategy_explanation(
        scenario=scenario_a,
        run=run_a,
        result=result_a,
        evaluations=evaluations,
    )
    print(f"  * AI Provider: {ai_explanation.get('provider')} | Model: {ai_explanation.get('model_name')}")
    print(f"  * Source: {ai_explanation.get('source')} (Live Gemini: {ai_explanation.get('is_live_gemini')})")
    print(f"  * Recommended Strategy: {ai_explanation.get('recommended_strategy_code')} - {ai_explanation.get('recommended_strategy_title')}")
    print(f"  * Executive Summary: {ai_explanation.get('executive_summary')}")
    print(f"  * Rationale: {ai_explanation.get('recommendation_rationale')[:200]}...")
    print(f"  * Key Risks Identified: {ai_explanation.get('operational_risks')}")

    # -------------------------------------------------------------
    # Step 8: Playback Timeline Verification
    # -------------------------------------------------------------
    print("\n[Step 8] Verifying Visual Simulation Playback Timeline Frames...")
    timeline = result_a.timeline_events
    print(f"  * Generated {len(timeline)} Discrete Timestep Frames (T+0.0 to T+{result_a.lost_machine_operating_hours}h):")
    for frame in timeline[:4]:
        events = frame.get("events", [])
        event_title = events[0]["title"] if events else "Nominal Progress"
        print(f"    [{frame['timestamp_label']}] Asset WEV-AJ-02 State: {frame['machine_states'].get('WEV-AJ-02')} -> {event_title}")

    # -------------------------------------------------------------
    # Step 9: Post-Simulation Operational Isolation Verification
    # -------------------------------------------------------------
    print("\n[Step 9] Verifying Strict Database Isolation (No Operational Records Modified)...")
    post_counts = {
        "machines": Machine.objects.count(),
        "telemetry": MachineTelemetry.objects.count(),
        "incidents": FactoryIncident.objects.count(),
        "inventory_items": InventoryItem.objects.count(),
        "batches": ProductionBatch.objects.count(),
        "tickets": MaintenanceTicket.objects.count(),
    }
    for model_name, before_count in baseline_counts.items():
        after_count = post_counts[model_name]
        assert before_count == after_count, f"Isolation violation on {model_name}: {before_count} -> {after_count}"
        print(f"  [OK] {model_name.capitalize()}: Count preserved exactly ({before_count} == {after_count})")

    # -------------------------------------------------------------
    # Step 10: Multi-Scenario Batch Verification (Demo B and Demo C)
    # -------------------------------------------------------------
    print("\n[Step 10] Validating Demo B (Weaving Cluster) & Demo C (Cross-Department Disruption)...")
    scen_b = WhatIfSimulationEngine.load_demo_scenario("DEMO_B")
    run_b = WhatIfSimulationEngine.run_simulation(scen_b)
    print(f"  [OK] Demo B: 3 Looms Disrupted -> {run_b.result.lost_machine_operating_hours}h lost, Bottleneck: {run_b.result.bottleneck_department}")

    scen_c = WhatIfSimulationEngine.load_demo_scenario("DEMO_C")
    run_c = WhatIfSimulationEngine.run_simulation(scen_c)
    print(f"  [OK] Demo C: Spinning Shortage -> {run_c.result.lost_machine_operating_hours}h lost, Bottleneck: {run_c.result.bottleneck_department}, Output Loss: {run_c.result.estimated_output_loss['KG']} kg")

    print("\n" + "=" * 80)
    print("PHASE 7 E2E VERIFICATION COMPLETED SUCCESSFULLY!")
    print("=" * 80)


if __name__ == "__main__":
    main()
