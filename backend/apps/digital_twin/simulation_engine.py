import time
import uuid
from typing import Any
from apps.factories.models import Department
from apps.machines.models import Machine
from apps.production.models import ProductionOrder, ProductionBatch
from apps.inventory.models import InventoryItem
from .models import (
    DigitalTwinSnapshot,
    WhatIfScenario,
    ScenarioMachineChange,
    SimulationRun,
    SimulationResult,
    RecoveryStrategyEvaluation,
    MachineTwinState,
    SparePartsAvailability,
    RecoveryStrategyType,
)
from .twin_engine import DigitalTwinEngine


class WhatIfSimulationEngine:
    """Isolated, deterministic What-If simulation engine for the simulated textile factory."""

    COMPATIBILITY_GROUPS = {
        "WEAVING_AIR_JET": ["WEV-AJ-01", "WEV-AJ-02", "WEV-AJ-03", "WEV-AJ-04"],
        "WEAVING_RAPIER": ["WEV-RAP-01", "WEV-WARP-01"],
        "SPINNING_RING": ["SPN-RS-01", "SPN-RS-02", "SPN-RS-03"],
        "SPINNING_PREP": ["SPN-CARD-01", "SPN-DRAW-01"],
        "SPINNING_WIND": ["SPN-WND-01", "SPN-WND-02"],
        "KNITTING_CIRCULAR": ["KNT-CS-01", "KNT-CS-02", "KNT-DBL-01"],
        "KNITTING_FLAT": ["KNT-FLAT-01"],
        "DYEING_SOFT_FLOW": ["DYE-SF-01", "DYE-SF-02", "DYE-THIES-01"],
        "DYEING_PACKAGE": ["DYE-PKG-01"],
        "FINISHING_INSPECT": ["FIN-INSP-01", "FIN-INSP-02"],
        "FINISHING_TREAT": ["FIN-COMP-01", "FIN-STNT-01"],
    }

    DEPARTMENT_UNITS = {
        "SPN": "KG",
        "WEV": "METERS",
        "KNT": "KG",
        "DYE": "METERS",
        "FIN": "METERS",
    }

    # Downstream material flow mapping
    FACTORY_DEPENDENCY_GRAPH = {
        "SPN": {
            "name": "Spinning Department",
            "unit": "KG/h",
            "downstream": ["WEV", "KNT"],
            "buffer_hours": 3.0,
            "yarn_to_fabric_ratio": 0.25,  # kg yarn per meter woven fabric
        },
        "WEV": {
            "name": "Weaving Shed",
            "unit": "METERS/h",
            "downstream": ["DYE"],
            "buffer_hours": 4.0,
        },
        "KNT": {
            "name": "Knitting Division",
            "unit": "KG/h",
            "downstream": ["DYE"],
            "buffer_hours": 3.0,
        },
        "DYE": {
            "name": "Dyeing & Chemical Processing",
            "unit": "METERS/h",
            "downstream": ["FIN"],
            "buffer_hours": 2.5,
        },
        "FIN": {
            "name": "Finishing & Packaging",
            "unit": "METERS/h",
            "downstream": [],
            "buffer_hours": 0.0,
        },
    }

    @classmethod
    def get_compatible_alternates(cls, machine_code: str) -> list[str]:
        """Finds compatible alternate machines in the same processing tier."""
        for group, machines in cls.COMPATIBILITY_GROUPS.items():
            if machine_code in machines:
                return [m for m in machines if m != machine_code]
        return []

    @classmethod
    def run_simulation(cls, scenario: WhatIfScenario) -> SimulationRun:
        """Executes a fully deterministic simulation run without altering operational tables."""
        start_time = time.time()

        # 1. Create SimulationRun record
        run = SimulationRun.objects.create(
            scenario=scenario,
            status="STARTED",
        )

        try:
            # 2. Extract baseline snapshot
            snapshot_dict = None
            if scenario.baseline_snapshot:
                snapshot_dict = {
                    "total_machines": scenario.baseline_snapshot.total_machines,
                    "operational_summary": scenario.baseline_snapshot.operational_summary,
                    "machine_states": scenario.baseline_snapshot.machine_states,
                }
            else:
                snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=False)

            baseline_machines = {m["code"]: m for m in snapshot_dict.get("machine_states", [])}

            # 3. Calculate baseline capacities per department
            baseline_capacity_per_hour = {}
            for dept_code, unit in cls.DEPARTMENT_UNITS.items():
                dept_machines = [m for m in baseline_machines.values() if m.get("department_code") == dept_code]
                total_cap = sum(float(m.get("rated_capacity_units_per_hour", 50.0)) for m in dept_machines)
                baseline_capacity_per_hour[dept_code] = round(total_cap, 2)

            # Ensure all department codes in baseline snapshot are included
            for m in baseline_machines.values():
                d_code = m.get("department_code")
                if d_code and d_code not in baseline_capacity_per_hour:
                    dept_machines = [bm for bm in baseline_machines.values() if bm.get("department_code") == d_code]
                    total_cap = sum(float(bm.get("rated_capacity_units_per_hour", 50.0)) for bm in dept_machines)
                    baseline_capacity_per_hour[d_code] = round(total_cap, 2)

            # 4. Apply hypothetical changes
            machine_changes = list(scenario.machine_changes.all())
            target_failed_codes = [mc.machine_code for mc in machine_changes]
            if not target_failed_codes:
                # Default fallback target if none specified
                target_failed_codes = ["WEV-AJ-02"]

            failure_duration = float(scenario.failure_duration_hours or 4.0)
            repair_duration = min(float(scenario.repair_duration_hours or 3.0), failure_duration)
            cap_reduction_pct = float(scenario.capacity_reduction_pct or 100.0)

            # 5. Calculate direct machine losses
            lost_machine_hours = round(len(target_failed_codes) * failure_duration, 2)
            total_nominal_capacity = sum(baseline_capacity_per_hour.values())

            # Unit-segregated output loss calculations
            estimated_output_loss = {"METERS": 0.0, "KG": 0.0, "PIECES": 0.0}
            simulated_capacity_per_hour = dict(baseline_capacity_per_hour)
            dept_loss_pct = {}

            affected_departments = set()
            for code in target_failed_codes:
                m_info = baseline_machines.get(code, {})
                dept_code = m_info.get("department_code", "WEV")
                affected_departments.add(dept_code)
                rated_cap = float(m_info.get("rated_capacity_units_per_hour", 50.0))
                unit = cls.DEPARTMENT_UNITS.get(dept_code, "METERS")

                loss_per_hour = rated_cap * (cap_reduction_pct / 100.0)
                current_cap = simulated_capacity_per_hour.get(dept_code, rated_cap)
                simulated_capacity_per_hour[dept_code] = max(
                    0.0, round(current_cap - loss_per_hour, 2)
                )

                # Total loss over failure duration
                output_loss_for_machine = round(loss_per_hour * failure_duration, 2)
                estimated_output_loss[unit] = round(estimated_output_loss.get(unit, 0.0) + output_loss_for_machine, 2)

            # Determine bottleneck department (highest capacity loss %)
            bottleneck_department = "WEV"
            max_dept_drop_pct = 0.0
            for d_code, base_cap in baseline_capacity_per_hour.items():
                if base_cap > 0:
                    sim_cap = simulated_capacity_per_hour.get(d_code, base_cap)
                    drop_pct = ((base_cap - sim_cap) / base_cap) * 100.0
                    dept_loss_pct[d_code] = round(drop_pct, 2)
                    if drop_pct > max_dept_drop_pct:
                        max_dept_drop_pct = drop_pct
                        bottleneck_department = d_code

            overall_capacity_reduction_pct = round(max_dept_drop_pct, 2)

            # 6. Alternate machine utilization & rerouting feasibility
            alternate_machine_utilization = []
            for code in target_failed_codes:
                m_info = baseline_machines.get(code, {})
                alternates = [a for a in cls.get_compatible_alternates(code) if a not in target_failed_codes]
                for alt_code in alternates:
                    alt_m = baseline_machines.get(alt_code, {})
                    # Calculate available headroom (assume 80% baseline load -> 20% headroom available)
                    alt_rated = float(alt_m.get("rated_capacity_units_per_hour", 50.0))
                    available_headroom = round(alt_rated * 0.25, 2)  # up to 25% surge/overtime absorption
                    alternate_machine_utilization.append({
                        "failed_machine": code,
                        "alternate_machine": alt_code,
                        "alternate_name": alt_m.get("name", alt_code),
                        "department": alt_m.get("department_code", "WEV"),
                        "rated_capacity": alt_rated,
                        "absorbable_capacity_per_hour": available_headroom,
                        "unit": cls.DEPARTMENT_UNITS.get(alt_m.get("department_code", "WEV"), "METERS"),
                        "is_operational": alt_m.get("twin_presentation_state") in ["RUNNING", "IDLE"],
                    })

            # 7. Potential Order Delays
            potential_order_delays = []
            active_batches = ProductionBatch.objects.filter(
                machine__code__in=target_failed_codes, status__in=["RUNNING", "STAGED"]
            ).select_related("production_order")

            if active_batches.exists():
                for b in active_batches:
                    po = b.production_order
                    delay_hours = round(failure_duration * 1.2, 1)
                    potential_order_delays.append({
                        "order_number": po.order_number if po else f"ORD-{b.batch_number}",
                        "client_name": po.client_name if po else "Coimbatore Mills Ltd",
                        "batch_number": b.batch_number,
                        "machine_code": b.machine.code if b.machine else "WEV-AJ-02",
                        "target_quantity": float(po.target_quantity) if po else 5000.0,
                        "unit": po.unit if po else "METERS",
                        "estimated_delay_hours": delay_hours,
                        "due_date": po.due_date.isoformat() if po and po.due_date else "2026-10-15",
                        "risk_level": "HIGH" if delay_hours > 6.0 else "MEDIUM",
                    })
            else:
                # Seeded deterministic demo delay impact if no live active batch attached to machine
                for code in target_failed_codes:
                    potential_order_delays.append({
                        "order_number": f"ORD-2026-{code.replace('-', '')[:8]}",
                        "client_name": "Premier Cotton Exports & Apparel",
                        "batch_number": f"BATCH-{code}-001",
                        "machine_code": code,
                        "target_quantity": 4200.0,
                        "unit": cls.DEPARTMENT_UNITS.get(code.split("-")[0], "METERS"),
                        "estimated_delay_hours": round(failure_duration * 1.1, 1),
                        "due_date": "2026-10-14",
                        "risk_level": "HIGH" if failure_duration >= 4.0 else "MEDIUM",
                    })

            # 8. Timeline Event Frames Generation (for Playback Mode)
            timeline_events = cls._generate_simulation_timeline(
                failure_duration=failure_duration,
                repair_duration=repair_duration,
                target_failed_codes=target_failed_codes,
                bottleneck_dept=bottleneck_department,
                baseline_machines=baseline_machines,
                spare_parts=scenario.spare_parts_availability,
                technicians=scenario.technicians_available,
            )

            # 9. Evaluate 3 Recovery Strategies
            strategy_evaluations = cls._evaluate_strategies(
                scenario=scenario,
                target_failed_codes=target_failed_codes,
                baseline_machines=baseline_machines,
                failure_duration=failure_duration,
                repair_duration=repair_duration,
                cap_reduction_pct=cap_reduction_pct,
                alternate_machines=alternate_machine_utilization,
                estimated_output_loss=estimated_output_loss,
            )

            # 10. Persist SimulationResult
            data_provenance = {
                "engine": "Texora What-If Deterministic Multi-Agent Simulation Engine v7.0",
                "is_isolated_simulation": True,
                "operational_tables_modified": False,
                "baseline_snapshot_id": scenario.baseline_snapshot.snapshot_id if scenario.baseline_snapshot else "DYNAMIC",
                "tested_at": timezone_now_iso(),
                "assumptions": {
                    "nominal_shift_hours": scenario.shift_duration_hours,
                    "reroute_capacity_ceiling_pct": 25.0,
                    "spare_parts_condition": scenario.spare_parts_availability,
                    "technician_pool": scenario.technicians_available,
                },
            }

            sim_result = SimulationResult.objects.create(
                run=run,
                baseline_capacity_per_hour=baseline_capacity_per_hour,
                simulated_capacity_per_hour=simulated_capacity_per_hour,
                lost_machine_operating_hours=lost_machine_hours,
                capacity_reduction_pct=overall_capacity_reduction_pct,
                estimated_output_loss=estimated_output_loss,
                potential_order_delays=potential_order_delays,
                bottleneck_department=bottleneck_department,
                alternative_machine_utilization=alternate_machine_utilization,
                timeline_events=timeline_events,
                data_provenance=data_provenance,
            )

            # Save Strategy Evaluations
            for se_data in strategy_evaluations:
                RecoveryStrategyEvaluation.objects.create(
                    run=run,
                    strategy_code=se_data["strategy_code"],
                    strategy_name=se_data["strategy_name"],
                    is_feasible=se_data["is_feasible"],
                    effectiveness_level=se_data.get("effectiveness_level", "HIGH_EFFECTIVENESS"),
                    infeasibility_reasons=se_data["infeasibility_reasons"],
                    estimated_downtime_hours=se_data["estimated_downtime_hours"],
                    capacity_recovered_pct=se_data["capacity_recovered_pct"],
                    estimated_output_loss=se_data["estimated_output_loss"],
                    unmitigated_baseline_loss=se_data.get("unmitigated_baseline_loss", estimated_output_loss),
                    volume_protected_units=se_data.get("volume_protected_units", {}),
                    recovery_time_hours=se_data["recovery_time_hours"],
                    resource_utilization=se_data["resource_utilization"],
                    estimated_cost=se_data["estimated_cost"],
                    rank=se_data["rank"],
                    is_tied=se_data.get("is_tied", False),
                    tie_breaker_note=se_data.get("tie_breaker_note", ""),
                    pros=se_data["pros"],
                    cons=se_data["cons"],
                )

            run.status = "COMPLETED"
            run.execution_duration_ms = int((time.time() - start_time) * 1000)
            run.save(update_fields=["status", "execution_duration_ms"])

            return run

        except Exception as e:
            run.status = "FAILED"
            run.error_message = str(e)
            run.execution_duration_ms = int((time.time() - start_time) * 1000)
            run.save(update_fields=["status", "error_message", "execution_duration_ms"])
            raise

    @classmethod
    def _generate_simulation_timeline(
        cls,
        failure_duration: float,
        repair_duration: float,
        target_failed_codes: list[str],
        bottleneck_dept: str,
        baseline_machines: dict,
        spare_parts: str,
        technicians: int,
    ) -> list[dict]:
        """Generates fine-grained chronological playback event frames from T+0.0 to T+Recovery."""
        frames = []
        max_time = max(failure_duration, repair_duration + 1.0)
        step_interval = 0.5
        current_t = 0.0

        while current_t <= max_time + 0.01:
            frame_machines = {}
            for code, m in baseline_machines.items():
                frame_machines[code] = m.get("twin_presentation_state", "RUNNING")

            events = []
            if current_t == 0.0:
                for code in target_failed_codes:
                    frame_machines[code] = "CRITICAL"
                events.append({
                    "event_type": "DISRUPTION_TRIGGERED",
                    "title": f"Hypothetical failure on {', '.join(target_failed_codes)}",
                    "severity": "CRITICAL",
                    "description": f"Machines transitioned to CRITICAL state in {bottleneck_dept} department.",
                })
            elif current_t == 0.5:
                for code in target_failed_codes:
                    frame_machines[code] = "UNDER_MAINTENANCE"
                events.append({
                    "event_type": "DIAGNOSTIC_AND_DISPATCH",
                    "title": "Machine Health Agent & Maintenance Dispatch",
                    "severity": "WARNING",
                    "description": f"Maintenance technician dispatched. Spare parts verification: {spare_parts}.",
                })
            elif current_t == 1.0:
                events.append({
                    "event_type": "PRODUCTION_REROUTE_EVALUATION",
                    "title": "Production Reroute & Buffer Activation",
                    "severity": "INFO",
                    "description": "Downstream buffers activated. Compatible alternate looms evaluated for absorption.",
                })
            elif current_t == repair_duration:
                for code in target_failed_codes:
                    frame_machines[code] = "WARNING"
                events.append({
                    "event_type": "REPAIR_COMPLETED_TESTING",
                    "title": "Mechanical Repair Complete — Telemetry Burn-in",
                    "severity": "INFO",
                    "description": f"Work orders executed on {', '.join(target_failed_codes)}. Initiating post-repair telemetry verification.",
                })
            elif current_t >= repair_duration + 0.5 and current_t <= failure_duration:
                for code in target_failed_codes:
                    frame_machines[code] = "RUNNING"
                events.append({
                    "event_type": "CAPACITY_RESTORED",
                    "title": "Telemetry Nominal — Machine Restored",
                    "severity": "SUCCESS",
                    "description": f"{', '.join(target_failed_codes)} operating within nominal envelope. Normal dispatch resumed.",
                })

            frames.append({
                "timestep_hours": round(current_t, 1),
                "timestamp_label": f"T + {int(current_t):02d}:{int((current_t % 1) * 60):02d}h",
                "machine_states": frame_machines,
                "disrupted_target_machines": target_failed_codes,
                "events": events,
                "is_disrupted": current_t < (repair_duration + 0.5),
            })
            current_t += step_interval

        return frames

    @classmethod
    def _evaluate_strategies(
        cls,
        scenario: WhatIfScenario,
        target_failed_codes: list[str],
        baseline_machines: dict,
        failure_duration: float,
        repair_duration: float,
        cap_reduction_pct: float,
        alternate_machines: list[dict],
        estimated_output_loss: dict,
    ) -> list[dict]:
        """Evaluates and ranks Strategies A, B, and C with feasibility boundaries, cost formulas, and tie detection."""
        candidates = []
        spare_parts = scenario.spare_parts_availability
        technicians = int(scenario.technicians_available or 2)
        required_techs = max(1, len(target_failed_codes))
        unmitigated_loss = dict(estimated_output_loss)

        # -------------------------------------------------------------
        # Strategy A: Repair Affected Machine First
        # -------------------------------------------------------------
        strat_a_feasible = True
        strat_a_infeasible_reasons = []
        if spare_parts == SparePartsAvailability.UNAVAILABLE:
            strat_a_feasible = False
            strat_a_infeasible_reasons.append("Required critical spare parts out of stock in warehouse.")
        if technicians < required_techs:
            strat_a_feasible = False
            strat_a_infeasible_reasons.append(f"Requires {required_techs} technicians, but only {technicians} available.")

        strat_a_downtime = repair_duration if strat_a_feasible else failure_duration * 1.5
        strat_a_cap_recovered = 100.0 if strat_a_feasible else 0.0

        strat_a_loss = {}
        strat_a_saved = {}
        for unit, total_loss in unmitigated_loss.items():
            mitigated = round(total_loss * (repair_duration / max(0.1, failure_duration)), 2)
            strat_a_loss[unit] = mitigated
            strat_a_saved[unit] = round(max(0.0, total_loss - mitigated), 2)

        labor_cost_a = required_techs * strat_a_downtime * 750.0
        parts_cost_a = len(target_failed_codes) * 4500.0
        penalty_cost_a = sum(strat_a_loss.values()) * 18.0
        total_cost_a = labor_cost_a + parts_cost_a + penalty_cost_a

        candidates.append({
            "strategy_code": RecoveryStrategyType.STRATEGY_A,
            "strategy_name": "Strategy A - Immediate Prioritized Repair",
            "is_feasible": strat_a_feasible,
            "effectiveness_level": "HIGH_EFFECTIVENESS" if strat_a_feasible else "INFEASIBLE",
            "infeasibility_reasons": strat_a_infeasible_reasons,
            "estimated_downtime_hours": round(strat_a_downtime, 2),
            "capacity_recovered_pct": strat_a_cap_recovered,
            "unmitigated_baseline_loss": unmitigated_loss,
            "estimated_output_loss": strat_a_loss,
            "volume_protected_units": strat_a_saved,
            "recovery_time_hours": round(strat_a_downtime + 0.5, 2),
            "resource_utilization": {
                "technicians_assigned": required_techs,
                "technicians_available": technicians,
                "spare_parts_status": spare_parts,
            },
            "estimated_cost": {
                "labor_cost_inr": labor_cost_a,
                "spare_parts_cost_inr": parts_cost_a,
                "production_loss_penalty_inr": penalty_cost_a,
                "total_estimated_cost_inr": total_cost_a,
                "currency": "INR",
                "formula_breakdown": f"({required_techs} Tech * {strat_a_downtime}h * ₹750/h) + ({len(target_failed_codes)} Part Kit * ₹4,500) + ({sum(strat_a_loss.values()):.1f} units * ₹18/unit penalty) = ₹{total_cost_a:,.0f} INR",
                "assumptions": {
                    "hourly_technician_rate_inr": 750.0,
                    "spare_part_kit_cost_inr": 4500.0,
                    "production_penalty_per_unit_inr": 18.0,
                },
            },
            "pros": [
                "Restores native machine assets to full nominal baseline",
                "Avoids setup / re-creeling overhead on alternate looms",
                "Maintains exact yarn lot traceability on original machine",
            ],
            "cons": [
                "Zero output mitigation during active repair window",
                "High sensitivity to spare parts availability",
                "Downtime bottleneck directly delays attached production order",
            ],
        })

        # -------------------------------------------------------------
        # Strategy B: Shift Eligible Production to Compatible Alternates
        # -------------------------------------------------------------
        strat_b_feasible = len(alternate_machines) > 0
        strat_b_infeasible_reasons = []
        if not strat_b_feasible:
            strat_b_infeasible_reasons.append("No compatible alternate machines found in the same department.")

        total_absorbable_rate = sum(
            m["absorbable_capacity_per_hour"] for m in alternate_machines if m["is_operational"]
        )
        total_lost_rate = sum(
            float(baseline_machines.get(c, {}).get("rated_capacity_units_per_hour", 50.0)) for c in target_failed_codes
        )
        absorbed_ratio = min(0.75, (total_absorbable_rate / max(1.0, total_lost_rate))) if total_lost_rate > 0 else 0.0

        strat_b_loss = {}
        strat_b_saved = {}
        for unit, total_loss in unmitigated_loss.items():
            mitigated = round(total_loss * (1.0 - absorbed_ratio), 2)
            strat_b_loss[unit] = mitigated
            strat_b_saved[unit] = round(max(0.0, total_loss - mitigated), 2)

        setup_cost_b = len(alternate_machines) * 2000.0
        ot_cost_b = len(alternate_machines) * failure_duration * 300.0
        penalty_cost_b = sum(strat_b_loss.values()) * 18.0
        total_cost_b = setup_cost_b + ot_cost_b + penalty_cost_b

        candidates.append({
            "strategy_code": RecoveryStrategyType.STRATEGY_B,
            "strategy_name": "Strategy B - Shift Production to Compatible Alternates",
            "is_feasible": strat_b_feasible,
            "effectiveness_level": "TEMPORARY_WORKAROUND" if strat_b_feasible else "INFEASIBLE",
            "infeasibility_reasons": strat_b_infeasible_reasons,
            "estimated_downtime_hours": round(failure_duration, 2),
            "capacity_recovered_pct": round(absorbed_ratio * 100.0, 1),
            "unmitigated_baseline_loss": unmitigated_loss,
            "estimated_output_loss": strat_b_loss,
            "volume_protected_units": strat_b_saved,
            "recovery_time_hours": round(failure_duration, 2),
            "resource_utilization": {
                "alternate_machines_engaged": len(alternate_machines),
                "rerouted_headroom_units_per_hour": round(total_absorbable_rate, 2),
                "technicians_assigned": 0,
            },
            "estimated_cost": {
                "setup_retooling_cost_inr": setup_cost_b,
                "overtime_labor_inr": ot_cost_b,
                "production_loss_penalty_inr": penalty_cost_b,
                "total_estimated_cost_inr": total_cost_b,
                "currency": "INR",
                "formula_breakdown": f"({len(alternate_machines)} Alt Machines * ₹2,000 Setup) + ({len(alternate_machines)} * {failure_duration}h * ₹300/h Overtime) + ({sum(strat_b_loss.values()):.1f} units * ₹18/unit penalty) = ₹{total_cost_b:,.0f} INR",
                "assumptions": {
                    "setup_retooling_cost_per_alt_inr": 2000.0,
                    "overtime_rate_per_hour_inr": 300.0,
                    "production_penalty_per_unit_inr": 18.0,
                },
            },
            "pros": [
                "Keeps high-priority customer order moving immediately",
                "Does not require immediate technician intervention or spare parts",
                "Leverages available machine headroom across factory floor",
            ],
            "cons": [
                "Leaves original failed machine in unrecovered state (0% asset recovery)",
                "Consumes reserve capacity buffer on alternate machines",
                "Minor setup time required for beam / yarn package changeover",
            ],
        })

        # -------------------------------------------------------------
        # Strategy C: Hybrid Prioritized Repair & Partial Rerouting (Recommended)
        # -------------------------------------------------------------
        strat_c_feasible = (spare_parts != SparePartsAvailability.UNAVAILABLE) and (len(alternate_machines) > 0)
        strat_c_infeasible_reasons = []
        if spare_parts == SparePartsAvailability.UNAVAILABLE:
            strat_c_infeasible_reasons.append("Spare parts unavailable for repair arm of hybrid strategy.")
        if len(alternate_machines) == 0:
            strat_c_infeasible_reasons.append("No alternate machines for rerouting arm.")

        strat_c_downtime = repair_duration
        strat_c_loss = {}
        strat_c_saved = {}
        for unit, total_loss in unmitigated_loss.items():
            base_repair_loss = total_loss * (repair_duration / max(0.1, failure_duration))
            mitigated_loss = base_repair_loss * (1.0 - (absorbed_ratio * 0.7)) if absorbed_ratio > 0 else base_repair_loss
            strat_c_loss[unit] = round(max(0.0, mitigated_loss), 2)
            strat_c_saved[unit] = round(max(0.0, total_loss - strat_c_loss[unit]), 2)

        labor_cost_c = required_techs * strat_c_downtime * 750.0
        parts_cost_c = len(target_failed_codes) * 4500.0
        setup_cost_c = len(alternate_machines) * 1200.0
        penalty_cost_c = sum(strat_c_loss.values()) * 18.0
        total_cost_c = labor_cost_c + parts_cost_c + setup_cost_c + penalty_cost_c

        candidates.append({
            "strategy_code": RecoveryStrategyType.STRATEGY_C,
            "strategy_name": "Strategy C - Hybrid Prioritized Repair & Rerouting (Recommended)",
            "is_feasible": strat_c_feasible,
            "effectiveness_level": "HIGH_EFFECTIVENESS" if strat_c_feasible else "INFEASIBLE",
            "infeasibility_reasons": strat_c_infeasible_reasons,
            "estimated_downtime_hours": round(strat_c_downtime, 2),
            "capacity_recovered_pct": 100.0 if strat_c_feasible else 50.0,
            "unmitigated_baseline_loss": unmitigated_loss,
            "estimated_output_loss": strat_c_loss,
            "volume_protected_units": strat_c_saved,
            "recovery_time_hours": round(strat_c_downtime + 0.5, 2),
            "resource_utilization": {
                "technicians_assigned": required_techs,
                "alternate_machines_engaged": len(alternate_machines),
                "spare_parts_status": spare_parts,
            },
            "estimated_cost": {
                "labor_cost_inr": labor_cost_c,
                "spare_parts_cost_inr": parts_cost_c,
                "setup_retooling_cost_inr": setup_cost_c,
                "production_loss_penalty_inr": penalty_cost_c,
                "total_estimated_cost_inr": total_cost_c,
                "currency": "INR",
                "formula_breakdown": f"({required_techs} Tech * {strat_c_downtime}h * ₹750/h) + ({len(target_failed_codes)} Part Kit * ₹4,500) + ({len(alternate_machines)} Alt * ₹1,200 Retooling) + ({sum(strat_c_loss.values()):.1f} units * ₹18/unit penalty) = ₹{total_cost_c:,.0f} INR",
                "assumptions": {
                    "hourly_technician_rate_inr": 750.0,
                    "spare_part_kit_cost_inr": 4500.0,
                    "setup_retooling_cost_per_alt_inr": 1200.0,
                    "production_penalty_per_unit_inr": 18.0,
                },
            },
            "pros": [
                "Lowest net production output loss among all strategies",
                "Fastest path to complete factory baseline recovery",
                "Shields critical customer delivery dates from disruption",
            ],
            "cons": [
                "Requires simultaneous coordination of maintenance staff and production scheduler",
                "Moderate setup overhead on alternate machines for temporary volume",
            ],
        })

        # -------------------------------------------------------------
        # Deterministic Multi-Objective Ranking & Tie Resolution Logic
        # -------------------------------------------------------------
        # Sort key: 
        # 1. Feasibility (feasible first)
        # 2. Estimated output loss (lower production loss is better)
        # 3. Estimated downtime hours (lower downtime is better)
        # 4. Total estimated cost in INR (lower financial cost is better)
        def sort_key(s):
            total_loss_val = sum(s["estimated_output_loss"].values())
            total_cost_val = s["estimated_cost"].get("total_estimated_cost_inr", 0.0)
            return (
                not s["is_feasible"],
                round(total_loss_val, 2),
                round(s["estimated_downtime_hours"], 2),
                round(total_cost_val, 2),
            )

        candidates.sort(key=sort_key)

        current_rank = 1
        for i, cand in enumerate(candidates):
            if i == 0:
                cand["rank"] = 1
                cand["is_tied"] = False
                cand["tie_breaker_note"] = ""
            else:
                prev = candidates[i - 1]
                prev_loss = sum(prev["estimated_output_loss"].values())
                curr_loss = sum(cand["estimated_output_loss"].values())
                prev_cost = prev["estimated_cost"].get("total_estimated_cost_inr", 0.0)
                curr_cost = cand["estimated_cost"].get("total_estimated_cost_inr", 0.0)
                
                loss_diff = abs(curr_loss - prev_loss)
                time_diff = abs(cand["estimated_downtime_hours"] - prev["estimated_downtime_hours"])
                cost_diff = abs(curr_cost - prev_cost)

                # Only consider tied if feasible status, downtime, output loss, AND cost are all identical within 0.01
                if (cand["is_feasible"] == prev["is_feasible"] 
                    and time_diff < 0.01 
                    and loss_diff < 0.01 
                    and cost_diff < 0.01):
                    cand["rank"] = prev["rank"]
                    cand["is_tied"] = True
                    prev["is_tied"] = True
                    tie_note = f"Tied on all primary metrics ({curr_loss:.1f} units loss, {cand['estimated_downtime_hours']}h downtime, ₹{curr_cost:,.0f} cost)."
                    cand["tie_breaker_note"] = tie_note
                    prev["tie_breaker_note"] = tie_note
                else:
                    current_rank += 1
                    cand["rank"] = current_rank
                    cand["is_tied"] = False
                    cand["tie_breaker_note"] = ""

        return candidates

    @classmethod
    def load_demo_scenario(cls, demo_code: str) -> WhatIfScenario:
        """Loads and prepares one of the 3 canonical Expo Demonstration Scenarios."""
        snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=True)
        snapshot_obj = DigitalTwinSnapshot.objects.get(id=snapshot_dict["id"])

        if demo_code == "DEMO_A":
            scenario, _ = WhatIfScenario.objects.update_or_create(
                demo_code="DEMO_A",
                defaults={
                    "scenario_id": f"SCEN-DEMO-A-{uuid.uuid4().hex[:6].upper()}",
                    "name": "Demo A — Single Loom Failure (WEV-AJ-02)",
                    "description": "Hypothetical critical main bearing failure on Air Jet Loom WEV-AJ-02. Compares immediate repair vs rerouting to WEV-AJ-01.",
                    "scenario_type": "SINGLE_MACHINE_FAILURE",
                    "baseline_snapshot": snapshot_obj,
                    "failure_duration_hours": 4.0,
                    "repair_duration_hours": 2.5,
                    "capacity_reduction_pct": 100.0,
                    "spare_parts_availability": "FULL",
                    "technicians_available": 2,
                    "demand_variation_pct": 0.0,
                    "shift_duration_hours": 8.0,
                    "selected_strategy": "ALL_COMPARISON",
                    "is_demo_scenario": True,
                },
            )
            scenario.machine_changes.all().delete()
            ScenarioMachineChange.objects.create(
                scenario=scenario,
                machine_code="WEV-AJ-02",
                simulated_state="CRITICAL",
                failure_type="MAIN_BEARING_SEIZURE",
                capacity_loss_pct=100.0,
            )
            return scenario

        elif demo_code == "DEMO_B":
            scenario, _ = WhatIfScenario.objects.update_or_create(
                demo_code="DEMO_B",
                defaults={
                    "scenario_id": f"SCEN-DEMO-B-{uuid.uuid4().hex[:6].upper()}",
                    "name": "Demo B — Multiple Weaving Cluster Failure (3 Looms)",
                    "description": "Simultaneous severe drive and motor vibration alarms on WEV-AJ-01, WEV-AJ-02, and WEV-AJ-04. Assesses severe department bottleneck and multi-technician allocation.",
                    "scenario_type": "MULTI_MACHINE_FAILURE",
                    "baseline_snapshot": snapshot_obj,
                    "failure_duration_hours": 6.0,
                    "repair_duration_hours": 4.0,
                    "capacity_reduction_pct": 100.0,
                    "spare_parts_availability": "PARTIAL",
                    "technicians_available": 2,
                    "demand_variation_pct": 0.0,
                    "shift_duration_hours": 8.0,
                    "selected_strategy": "ALL_COMPARISON",
                    "is_demo_scenario": True,
                },
            )
            scenario.machine_changes.all().delete()
            for code in ["WEV-AJ-01", "WEV-AJ-02", "WEV-AJ-04"]:
                ScenarioMachineChange.objects.create(
                    scenario=scenario,
                    machine_code=code,
                    simulated_state="CRITICAL",
                    failure_type="DRIVE_MOTOR_FAULT",
                    capacity_loss_pct=100.0,
                )
            return scenario

        elif demo_code == "DEMO_C":
            scenario, _ = WhatIfScenario.objects.update_or_create(
                demo_code="DEMO_C",
                defaults={
                    "scenario_id": f"SCEN-DEMO-C-{uuid.uuid4().hex[:6].upper()}",
                    "name": "Demo C — Cross-Department Material Disruption (Spinning -> Weaving)",
                    "description": "Hypothetical Ring Spinning thermal excursion on SPN-RS-01 reducing yarn output by 80%. Evaluates downstream yarn buffer depletion and starvation of weaving looms.",
                    "scenario_type": "CROSS_DEPARTMENT_DISRUPTION",
                    "baseline_snapshot": snapshot_obj,
                    "failure_duration_hours": 8.0,
                    "repair_duration_hours": 4.5,
                    "capacity_reduction_pct": 80.0,
                    "spare_parts_availability": "FULL",
                    "technicians_available": 3,
                    "demand_variation_pct": 15.0,
                    "shift_duration_hours": 8.0,
                    "selected_strategy": "ALL_COMPARISON",
                    "is_demo_scenario": True,
                },
            )
            scenario.machine_changes.all().delete()
            ScenarioMachineChange.objects.create(
                scenario=scenario,
                machine_code="SPN-RS-01",
                simulated_state="CRITICAL",
                failure_type="SPINDLE_BEARING_THERMAL_RUNAWAY",
                capacity_loss_pct=80.0,
            )
            return scenario

        else:
            raise ValueError(f"Unknown demo code: {demo_code}")


def timezone_now_iso() -> str:
    from django.utils import timezone
    return timezone.now().isoformat()
