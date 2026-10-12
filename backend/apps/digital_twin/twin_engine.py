import uuid
from datetime import timedelta
from django.utils import timezone
from apps.factories.models import Factory, Department
from apps.machines.models import Machine, MachineTelemetry, MachineOperatingLimits
from apps.incidents.models import FactoryIncident
from apps.maintenance.models import MaintenanceTicket
from apps.production.models import ProductionBatch, ProductionOrder
from apps.ai_agents.models import RecoveryCase
from .models import DigitalTwinSnapshot, MachineTwinState


class DigitalTwinEngine:
    """Constructs and queries high-fidelity virtual snapshots of the simulated factory."""

    TELEMETRY_STALE_THRESHOLD_SECONDS = 180  # 3 minutes

    @classmethod
    def calculate_presentation_state(
        cls,
        machine: Machine,
        latest_telemetry: MachineTelemetry | None,
        active_incidents: list,
        active_tickets: list,
        active_recovery: RecoveryCase | None,
    ) -> tuple[str, str]:
        """Calculates presentation state and reason based on live telemetry, incidents, and maintenance.
        
        Returns:
            (presentation_state, reason_details)
        """
        # 1. Check for active critical incidents or recovery cases
        critical_incidents = [i for i in active_incidents if i.severity == "CRITICAL"]
        if critical_incidents:
            return (
                MachineTwinState.CRITICAL,
                f"Active Critical Incident: {critical_incidents[0].summary}",
            )

        # 2. Check for active maintenance tickets
        in_progress_tickets = [t for t in active_tickets if t.status in ["OPEN", "IN_PROGRESS", "ASSIGNED", "PENDING_PARTS"]]
        if in_progress_tickets:
            return (
                MachineTwinState.UNDER_MAINTENANCE,
                f"Active Work Order: {in_progress_tickets[0].ticket_number} ({in_progress_tickets[0].title})",
            )

        # 3. Check for active recovery case
        if active_recovery and active_recovery.status in ["ANALYZING", "PLAN_READY", "AWAITING_APPROVALS", "IN_RECOVERY"]:
            return (
                MachineTwinState.UNDER_MAINTENANCE,
                f"Recovery Case {active_recovery.case_code} in progress",
            )

        # 4. Check telemetry freshness and values
        if not latest_telemetry:
            return (
                MachineTwinState.UNKNOWN,
                "No telemetry records found for machine",
            )

        age_seconds = (timezone.now() - latest_telemetry.timestamp).total_seconds()
        if age_seconds > cls.TELEMETRY_STALE_THRESHOLD_SECONDS:
            return (
                MachineTwinState.UNKNOWN,
                f"Telemetry stale (last reading {int(age_seconds)}s ago)",
            )

        # 5. Evaluate telemetry status flag and sensor thresholds
        if latest_telemetry.status_flag == "CRITICAL":
            return (
                MachineTwinState.CRITICAL,
                "Telemetry reading indicates CRITICAL operational violation",
            )

        if latest_telemetry.status_flag == "WARNING":
            return (
                MachineTwinState.WARNING,
                "Telemetry reading indicates WARNING threshold excursion",
            )

        # 6. Check machine operational limits if configured
        try:
            limits = machine.operating_limits
            if latest_telemetry.temperature_c and latest_telemetry.temperature_c >= limits.max_temp_c:
                return (MachineTwinState.CRITICAL, f"Temperature {latest_telemetry.temperature_c}°C exceeds limit {limits.max_temp_c}°C")
            if latest_telemetry.vibration_mms and latest_telemetry.vibration_mms >= limits.max_vibration_mms:
                return (MachineTwinState.CRITICAL, f"Vibration {latest_telemetry.vibration_mms} mm/s exceeds limit {limits.max_vibration_mms} mm/s")
            if latest_telemetry.temperature_c and latest_telemetry.temperature_c >= limits.warning_temp_c:
                return (MachineTwinState.WARNING, f"Temperature {latest_telemetry.temperature_c}°C in warning range")
            if latest_telemetry.vibration_mms and latest_telemetry.vibration_mms >= limits.warning_vibration_mms:
                return (MachineTwinState.WARNING, f"Vibration {latest_telemetry.vibration_mms} mm/s in warning range")
        except MachineOperatingLimits.DoesNotExist:
            pass

        # 7. Check if machine is idle vs running
        if latest_telemetry.utilization_pct is not None and latest_telemetry.utilization_pct <= 5.0:
            return (MachineTwinState.IDLE, "Machine in Standby / Idle (Utilization <= 5%)")

        if machine.status == "OFFLINE":
            return (MachineTwinState.OFFLINE, "Machine configured as Offline")

        return (MachineTwinState.RUNNING, "Operating within nominal parameters")

    @classmethod
    def capture_snapshot(cls, factory_code: str = "FAC-01", save_to_db: bool = True) -> dict:
        """Constructs a comprehensive virtual factory snapshot across all 25 machines."""
        factory = Factory.objects.filter(code=factory_code).first()
        if not factory:
            factory = Factory.objects.first()
            if not factory:
                factory = Factory.objects.create(
                    code=factory_code,
                    name="Texora Smart Textile Mill #1",
                    location="Coimbatore, Tamil Nadu, India",
                )

        departments = Department.objects.filter(factory=factory).prefetch_related("machines")
        now = timezone.now()
        snapshot_id = f"TWIN-{now.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6].upper()}"

        all_machines = Machine.objects.filter(department__factory=factory).select_related(
            "machine_type", "department", "operating_limits", "production_line"
        )

        # Batch query latest telemetry for all machines
        machine_telemetry_map = {}
        for m in all_machines:
            latest = MachineTelemetry.objects.filter(machine=m).order_by("-timestamp").first()
            if latest:
                machine_telemetry_map[m.id] = latest

        # Batch query active incidents
        active_incidents_qs = FactoryIncident.objects.filter(
            machine__in=all_machines,
            status__in=["OPEN", "INVESTIGATING", "MITIGATING"],
        ).order_by("-detected_at")
        incidents_by_machine = {}
        for inc in active_incidents_qs:
            incidents_by_machine.setdefault(inc.machine_id, []).append(inc)

        # Batch query active maintenance tickets
        active_tickets_qs = MaintenanceTicket.objects.filter(
            machine__in=all_machines,
            status__in=["OPEN", "ASSIGNED", "IN_PROGRESS", "PENDING_PARTS"],
        ).order_by("-created_at")
        tickets_by_machine = {}
        for t in active_tickets_qs:
            tickets_by_machine.setdefault(t.machine_id, []).append(t)

        # Batch query active recovery cases
        active_recoveries_qs = RecoveryCase.objects.filter(
            machine__in=all_machines,
            status__in=["ANALYZING", "PLAN_READY", "AWAITING_APPROVALS", "IN_RECOVERY", "VERIFYING_TELEMETRY"],
        ).order_by("-created_at")
        recovery_by_machine = {rc.machine_id: rc for rc in active_recoveries_qs}

        # Batch query active production batches
        active_batches = ProductionBatch.objects.filter(
            machine__in=all_machines,
            status__in=["STAGED", "RUNNING", "PAUSED"],
        ).select_related("production_order")
        batches_by_machine = {b.machine_id: b for b in active_batches}

        machine_states = []
        state_distribution = {state.value: 0 for state in MachineTwinState}
        department_summaries = {}

        for dept in departments:
            dept_machines = [m for m in all_machines if m.department_id == dept.id]
            dept_states = {state.value: 0 for state in MachineTwinState}
            dept_total_rated_capacity = 0.0
            dept_active_incidents_count = 0

            for m in dept_machines:
                latest_tel = machine_telemetry_map.get(m.id)
                m_incidents = incidents_by_machine.get(m.id, [])
                m_tickets = tickets_by_machine.get(m.id, [])
                m_recovery = recovery_by_machine.get(m.id)
                m_batch = batches_by_machine.get(m.id)

                presentation_state, reason_details = cls.calculate_presentation_state(
                    machine=m,
                    latest_telemetry=latest_tel,
                    active_incidents=m_incidents,
                    active_tickets=m_tickets,
                    active_recovery=m_recovery,
                )

                state_distribution[presentation_state] = state_distribution.get(presentation_state, 0) + 1
                dept_states[presentation_state] = dept_states.get(presentation_state, 0) + 1
                dept_total_rated_capacity += float(m.rated_capacity_units_per_hour or 0.0)
                dept_active_incidents_count += len(m_incidents)

                # Format limits
                limits_data = None
                try:
                    limits = m.operating_limits
                    limits_data = {
                        "min_temp_c": limits.min_temp_c,
                        "max_temp_c": limits.max_temp_c,
                        "warning_temp_c": limits.warning_temp_c,
                        "max_vibration_mms": limits.max_vibration_mms,
                        "warning_vibration_mms": limits.warning_vibration_mms,
                        "min_rpm": limits.min_rpm,
                        "max_rpm": limits.max_rpm,
                        "max_power_kw": limits.max_power_kw,
                    }
                except MachineOperatingLimits.DoesNotExist:
                    limits_data = None

                # Format production assignment
                production_assignment = None
                if m_batch:
                    production_assignment = {
                        "batch_number": m_batch.batch_number,
                        "order_number": m_batch.production_order.order_number if m_batch.production_order else "N/A",
                        "client_name": m_batch.production_order.client_name if m_batch.production_order else "N/A",
                        "fabric_spec": m_batch.production_order.fabric_or_yarn_spec if m_batch.production_order else "Standard",
                        "status": m_batch.status,
                        "planned_quantity": float(m_batch.planned_quantity or 0.0),
                        "actual_quantity": float(m_batch.actual_quantity or 0.0),
                        "unit": m_batch.production_order.unit if m_batch.production_order else "KG",
                    }

                telemetry_data = None
                if latest_tel:
                    telemetry_data = {
                        "timestamp": latest_tel.timestamp.isoformat(),
                        "temperature_c": latest_tel.temperature_c,
                        "vibration_mms": latest_tel.vibration_mms,
                        "speed_rpm": latest_tel.speed_rpm,
                        "power_kw": latest_tel.power_kw,
                        "utilization_pct": latest_tel.utilization_pct,
                        "output_rate": latest_tel.output_rate,
                        "status_flag": latest_tel.status_flag,
                        "is_stale": (now - latest_tel.timestamp).total_seconds() > cls.TELEMETRY_STALE_THRESHOLD_SECONDS,
                    }

                is_stale_tel = (now - latest_tel.timestamp).total_seconds() > cls.TELEMETRY_STALE_THRESHOLD_SECONDS if latest_tel else True
                tel_age = (now - latest_tel.timestamp).total_seconds() if latest_tel else None

                provenance_type = "NOMINAL_OPERATION"
                if presentation_state == MachineTwinState.CRITICAL:
                    provenance_type = "OPERATIONAL_INCIDENT_BASELINE"
                elif presentation_state == MachineTwinState.UNDER_MAINTENANCE:
                    provenance_type = "OPERATIONAL_WORK_ORDER"
                elif presentation_state == MachineTwinState.UNKNOWN:
                    provenance_type = "STALE_TELEMETRY_UNKNOWN"

                machine_states.append({
                    "id": m.id,
                    "code": m.code,
                    "name": m.name,
                    "machine_type_name": m.machine_type.name,
                    "category": m.machine_type.category,
                    "department_code": dept.code,
                    "department_name": dept.name,
                    "floor_location": dept.floor_location,
                    "raw_status": m.status,
                    "twin_presentation_state": presentation_state,
                    "state_reason": reason_details,
                    "provenance_type": provenance_type,
                    "is_baseline_incident": bool(m_incidents),
                    "health_score": float(m.current_health_score or 100.0),
                    "rated_capacity_units_per_hour": float(m.rated_capacity_units_per_hour or 50.0),
                    "rated_speed_rpm": m.rated_speed_rpm,
                    "latest_telemetry": telemetry_data,
                    "telemetry_freshness": {
                        "is_fresh": not is_stale_tel,
                        "age_seconds": round(tel_age, 1) if tel_age is not None else None,
                        "threshold_seconds": cls.TELEMETRY_STALE_THRESHOLD_SECONDS,
                        "status_label": "FRESH (<180s)" if not is_stale_tel else f"STALE (>{int(tel_age or 0)}s ago - Simulator Paused)",
                    },
                    "operating_limits": limits_data,
                    "active_incidents": [
                        {
                            "id": inc.id,
                            "incident_code": inc.incident_code,
                            "summary": inc.summary,
                            "severity": inc.severity,
                            "status": inc.status,
                            "category": inc.category,
                            "detected_at": inc.detected_at.isoformat(),
                        }
                        for inc in m_incidents
                    ],
                    "active_tickets": [
                        {
                            "id": t.id,
                            "ticket_number": t.ticket_number,
                            "title": t.title,
                            "priority": t.priority,
                            "status": t.status,
                            "assigned_technician": t.assigned_technician,
                        }
                        for t in m_tickets
                    ],
                    "active_recovery": (
                        {
                            "id": m_recovery.id,
                            "case_code": m_recovery.case_code,
                            "status": m_recovery.status,
                            "priority": m_recovery.priority,
                            "pending_approvals_count": m_recovery.pending_approvals_count,
                        }
                        if m_recovery
                        else None
                    ),
                    "production_assignment": production_assignment,
                })

            department_summaries[dept.code] = {
                "name": dept.name,
                "code": dept.code,
                "department_type": dept.department_type,
                "floor_location": dept.floor_location,
                "total_machines": len(dept_machines),
                "state_counts": dept_states,
                "rated_capacity_total": dept_total_rated_capacity,
                "active_incidents_count": dept_active_incidents_count,
                "target_efficiency_pct": float(dept.target_efficiency_pct or 85.0),
            }

        stale_count = sum(1 for m in machine_states if m.get("telemetry_freshness", {}).get("is_fresh") is False)
        operational_summary = {
            "factory_code": factory.code,
            "factory_name": factory.name,
            "system_label": "SIMULATED FACTORY DIGITAL TWIN — PSG COIMBATORE EXPO",
            "is_simulated_twin": True,
            "captured_at": now.isoformat(),
            "total_machines": len(all_machines),
            "state_distribution": state_distribution,
            "active_incidents_total": sum(len(incs) for incs in incidents_by_machine.values()),
            "active_tickets_total": sum(len(tks) for tks in tickets_by_machine.values()),
            "active_recovery_cases_total": len(active_recoveries_qs),
            "telemetry_freshness_summary": {
                "freshness_threshold_seconds": cls.TELEMETRY_STALE_THRESHOLD_SECONDS,
                "fresh_machines_count": len(all_machines) - stale_count,
                "stale_machines_count": stale_count,
                "telemetry_simulator_status": "STREAMING" if stale_count == 0 else "IDLE_OR_PAUSED",
                "explanation": "Machines with telemetry older than 180s are classified as UNKNOWN. Missing telemetry is never fabricated as healthy.",
            },
            "department_summaries": department_summaries,
        }

        snapshot_dict = {
            "snapshot_id": snapshot_id,
            "factory_id": factory.id,
            "factory_code": factory.code,
            "captured_at": now.isoformat(),
            "total_machines": len(all_machines),
            "operational_summary": operational_summary,
            "machine_states": machine_states,
        }

        if save_to_db:
            snapshot_obj = DigitalTwinSnapshot.objects.create(
                snapshot_id=snapshot_id,
                factory=factory,
                total_machines=len(all_machines),
                operational_summary=operational_summary,
                machine_states=machine_states,
                is_baseline=True,
            )
            snapshot_dict["id"] = snapshot_obj.id

        return snapshot_dict
