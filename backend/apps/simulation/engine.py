import time
import math
import random
import logging
import threading
from datetime import datetime, timezone, timedelta
from django.db import transaction, connection
from django.utils import timezone as dj_timezone

from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineTelemetry, MachineStatus, MachineStateHistory
from apps.production.models import ProductionOrder, ProductionBatch, ProductionOutput, ProductionDelay, OrderStatus
from apps.quality.models import QualityInspection, QualityDefect, DefectType
from apps.inventory.models import InventoryItem, InventoryTransaction
from apps.energy.models import EnergyReading
from apps.simulation.models import SimulationState, InjectedScenario, ScenarioType

logger = logging.getLogger(__name__)


class SimulationEngine:
    """
    Core Autonomous Factory Simulation Engine.
    Generates realistic textile telemetry, executes physical simulation models,
    advances production batches, simulates quality & energy, and applies scenario injections.
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(SimulationEngine, cls).__new__(cls)
                cls._instance._is_initialized = False
            return cls._instance

    def __init__(self):
        if self._is_initialized:
            return
        self._is_initialized = True
        self._thread = None
        self._stop_requested = threading.Event()
        self._pause_requested = threading.Event()

    def start(self, speed_multiplier: float = 1.0, tick_interval: float = 3.0):
        """Starts the background simulation loop in a worker thread."""
        with self._lock:
            state = SimulationState.get_state()
            state.is_running = True
            state.is_paused = False
            state.speed_multiplier = speed_multiplier
            state.tick_interval_seconds = tick_interval
            state.started_at = dj_timezone.now()
            state.save()

            self._stop_requested.clear()
            self._pause_requested.clear()

            if self._thread is None or not self._thread.is_alive():
                self._thread = threading.Thread(
                    target=self._run_loop,
                    name="TexoraSimulationWorker",
                    daemon=True,
                )
                self._thread.start()
                logger.info("Simulation Engine worker thread started.")

    def pause(self):
        """Pauses the simulation without terminating the worker thread."""
        with self._lock:
            state = SimulationState.get_state()
            state.is_paused = True
            state.save()
            self._pause_requested.set()
            logger.info("Simulation Engine paused.")

    def resume(self):
        """Resumes a paused simulation."""
        with self._lock:
            state = SimulationState.get_state()
            state.is_paused = False
            state.is_running = True
            state.save()
            self._pause_requested.clear()
            logger.info("Simulation Engine resumed.")

    def stop(self):
        """Stops the simulation engine."""
        with self._lock:
            state = SimulationState.get_state()
            state.is_running = False
            state.is_paused = False
            state.save()
            self._stop_requested.set()
            self._pause_requested.clear()
            logger.info("Simulation Engine stop requested.")

    def is_active(self) -> bool:
        """Returns True if the background simulation thread is currently running."""
        return self._thread is not None and self._thread.is_alive()

    def _run_loop(self):
        """Main background simulation cycle."""
        import os
        from django.db import close_old_connections
        from apps.incidents.models import WorkerHeartbeat
        while not self._stop_requested.is_set():
            try:
                close_old_connections()
                state = SimulationState.get_state()

                if not state.is_running or state.is_paused or self._pause_requested.is_set():
                    time.sleep(0.5)
                    continue

                WorkerHeartbeat.record_heartbeat(
                    worker_name="TELEMETRY_SIMULATOR",
                    process_id=os.getpid(),
                    status="RUNNING",
                    metrics={
                        "total_ticks": state.total_ticks,
                        "speed_multiplier": float(state.speed_multiplier),
                        "tick_interval_seconds": float(state.tick_interval_seconds),
                    },
                )

                interval = max(0.5, state.tick_interval_seconds / max(0.1, state.speed_multiplier))

                # Execute one physical simulation tick
                self.run_tick()

                time.sleep(interval)
            except Exception as e:
                logger.error("Error during simulation tick execution: %s", e, exc_info=True)
                time.sleep(2.0)
            finally:
                close_old_connections()

        try:
            WorkerHeartbeat.record_heartbeat(
                worker_name="TELEMETRY_SIMULATOR",
                process_id=os.getpid(),
                status="STOPPED",
            )
        except Exception:
            pass

        logger.info("Simulation loop terminated.")

    @transaction.atomic
    def run_tick(self) -> dict:
        """Executes a single discrete simulation tick across all factory machinery."""
        now = dj_timezone.now()
        state = SimulationState.get_state()

        # 1. Fetch active scenarios
        active_scenarios = list(InjectedScenario.objects.filter(is_active=True))
        scenario_map = {s.target_machine_code: s for s in active_scenarios if s.target_machine_code}
        global_scenarios = [s for s in active_scenarios if not s.target_machine_code]

        # 2. Fetch all machines with limits
        machines = Machine.objects.select_related("operating_limits", "department", "machine_type").filter(is_active=True)
        telemetry_batch = []
        energy_batch = []
        now_ts = now.timestamp()

        for machine in machines:
            limits = getattr(machine, "operating_limits", None)
            dept_type = machine.department.department_type
            scenario = scenario_map.get(machine.code) or (global_scenarios[0] if global_scenarios else None)

            # Base Physical Characteristics
            base_temp, base_vib, base_rpm, base_kw, base_rate = self._get_baseline_physics(machine, limits)

            # Smooth sinusoidal micro-variation
            sin_phase = math.sin(now_ts / 30.0 + (hash(machine.code) % 100))
            noise_temp = random.uniform(-0.8, 0.8) + (sin_phase * 1.2)
            noise_vib = random.uniform(-0.15, 0.15) + (sin_phase * 0.25)
            noise_kw = random.uniform(-1.5, 1.5)

            temp = round(base_temp + noise_temp, 2)
            vib = round(max(0.2, base_vib + noise_vib), 2)
            rpm = int(max(1, base_rpm * (1.0 + (sin_phase * 0.015) + random.uniform(-0.012, 0.012))))
            power = round(max(1.0, base_kw + noise_kw), 2)
            util = round(random.uniform(88.0, 96.0), 1)
            output_rate = round(float(machine.rated_capacity_units_per_hour) * (util / 100.0), 2)
            status_flag = "NORMAL"

            # Machine status handling
            if machine.status in [MachineStatus.MAINTENANCE, MachineStatus.OFFLINE]:
                rpm = 0
                output_rate = 0.0
                power = round(base_kw * 0.05, 2)
                temp = round(28.0 + random.uniform(-0.5, 0.5), 1)
                vib = 0.1
                util = 0.0
            elif machine.status == MachineStatus.IDLE:
                rpm = int(base_rpm * 0.2)
                output_rate = 0.0
                power = round(base_kw * 0.25, 2)
                util = 0.0

            # 3. Apply Scenario Injections
            if scenario:
                temp, vib, rpm, power, util, output_rate, status_flag = self._apply_scenario_to_machine(
                    scenario, machine, limits, temp, vib, rpm, power, util, output_rate, status_flag, now
                )

            # Check operating limits if status_flag not already critical
            if limits and status_flag == "NORMAL":
                if temp >= limits.max_temp_c or vib >= limits.max_vibration_mms:
                    status_flag = "CRITICAL"
                elif temp >= limits.warning_temp_c or vib >= limits.warning_vibration_mms:
                    status_flag = "WARNING"

            # Prepare telemetry record
            telemetry_batch.append(
                MachineTelemetry(
                    machine=machine,
                    timestamp=now,
                    temperature_c=temp,
                    vibration_mms=vib,
                    speed_rpm=rpm,
                    power_kw=power,
                    utilization_pct=util,
                    output_rate=output_rate,
                    operating_hours=round(1240.0 + (state.total_ticks_generated * 0.01), 2),
                    status_flag=status_flag,
                    raw_sensor_data={
                        "bearing_temp": temp,
                        "vibration_rms": vib,
                        "line_voltage": round(415.0 + random.uniform(-3, 3), 1),
                        "motor_amps": round(power * 1.45, 1),
                    },
                )
            )

            # Update machine health score
            if status_flag == "CRITICAL":
                machine.current_health_score = max(35.0, round(float(machine.current_health_score) - 0.5, 2))
                if machine.status == MachineStatus.OPERATIONAL:
                    machine.status = MachineStatus.WARNING
                    machine.save(update_fields=["status", "current_health_score"])
            elif status_flag == "WARNING":
                machine.current_health_score = max(70.0, round(float(machine.current_health_score) - 0.1, 2))
                machine.save(update_fields=["current_health_score"])
            else:
                machine.current_health_score = min(100.0, round(float(machine.current_health_score) + 0.05, 2))
                machine.save(update_fields=["current_health_score"])

            # Energy Reading
            energy_batch.append(
                EnergyReading(
                    factory=machine.department.factory,
                    department=machine.department,
                    machine=machine,
                    timestamp=now,
                    active_power_kw=power,
                    energy_kwh=round(power * (state.tick_interval_seconds / 3600.0), 4),
                    power_factor=0.93,
                    voltage_v=415.0,
                    current_amps=round(power * 1.45, 1),
                    carbon_emission_kg=round(power * 0.00082, 4),
                    is_peak_hour=(18 <= now.hour <= 22),
                )
            )

        # 4. Bulk Insert Telemetry and Energy
        MachineTelemetry.objects.bulk_create(telemetry_batch)
        EnergyReading.objects.bulk_create(energy_batch)

        # 5. Advance Active Production Batches
        self._advance_production_batches(now, state.speed_multiplier)

        # 6. Update Simulation State
        state.total_ticks_generated += 1
        state.last_tick_at = now
        state.save(update_fields=["total_ticks_generated", "last_tick_at"])

        # 7. Prune excess historical telemetry to keep database snappy
        if state.total_ticks_generated % 50 == 0:
            self._prune_old_records()

        return {
            "tick": state.total_ticks_generated,
            "timestamp": now.isoformat(),
            "machines_updated": len(machines),
            "telemetry_recorded": len(telemetry_batch),
            "active_scenarios": len(active_scenarios),
        }

    def _get_baseline_physics(self, machine: Machine, limits: Optional[MachineOperatingLimits]):
        """Returns realistic baseline physical values scaled to each machine's specific operating limits."""
        if limits:
            base_temp = round(limits.min_temp_c + (limits.warning_temp_c - limits.min_temp_c) * 0.65, 1)
            base_vib = round(limits.warning_vibration_mms * 0.62, 2)
            base_rpm = machine.rated_speed_rpm
            base_kw = round(float(limits.max_power_kw) * 0.75, 1)
            base_rate = float(machine.rated_capacity_units_per_hour)
            return (base_temp, base_vib, base_rpm, base_kw, base_rate)

        dept_type = machine.department.department_type
        if dept_type == DepartmentType.SPINNING:
            return (65.0, 2.4, machine.rated_speed_rpm or 19500, 35.0, 42.0)
        elif dept_type == DepartmentType.WEAVING:
            return (58.0, 2.5, machine.rated_speed_rpm or 1050, 12.0, 48.0)
        elif dept_type == DepartmentType.KNITTING:
            return (42.0, 1.8, machine.rated_speed_rpm or 32, 6.5, 28.0)
        elif dept_type == DepartmentType.DYEING:
            return (115.0, 2.0, machine.rated_speed_rpm or 320, 30.0, 180.0)
        elif dept_type == DepartmentType.FINISHING:
            return (120.0, 1.9, machine.rated_speed_rpm or 80, 40.0, 500.0)
        return (50.0, 2.0, 1000, 20.0, 50.0)

    def _apply_scenario_to_machine(self, scenario: InjectedScenario, machine: Machine, limits, temp, vib, rpm, power, util, output_rate, status_flag, now):
        """Modifies machine telemetry and creates operational artifacts based on injected scenarios."""
        stype = scenario.scenario_type

        if stype == ScenarioType.WEAVING_VIBRATION and machine.department.department_type == DepartmentType.WEAVING:
            # Inject excessive loom vibration
            vib = round(random.uniform(5.9, 7.4), 2)
            temp = round(temp + 6.5, 2)
            status_flag = "CRITICAL"
            logger.info("Scenario active: Injected WEAVING_VIBRATION on %s (Vib: %s mm/s)", machine.code, vib)

        elif stype == ScenarioType.SPINNING_OVERHEAT and machine.department.department_type == DepartmentType.SPINNING:
            # Inject ring frame bearing overheat
            temp = round(random.uniform(86.5, 94.0), 2)
            vib = round(vib + 1.8, 2)
            status_flag = "CRITICAL"
            logger.info("Scenario active: Injected SPINNING_OVERHEAT on %s (Temp: %s C)", machine.code, temp)

        elif stype == ScenarioType.PRODUCTION_SLOWDOWN:
            # Throttle machine speed
            rpm = int(rpm * 0.45)
            output_rate = round(output_rate * 0.45, 2)
            util = round(util * 0.5, 1)
            status_flag = "WARNING"

            # Create production delay record if none active
            active_batch = machine.batches.filter(status="RUNNING").first()
            if active_batch and not ProductionDelay.objects.filter(machine=machine, resolved_at__isnull=True).exists():
                ProductionDelay.objects.create(
                    production_order=active_batch.production_order,
                    production_batch=active_batch,
                    machine=machine,
                    delay_reason="MACHINE_BREAKDOWN",
                    estimated_delay_minutes=120,
                    impact_summary=f"Simulated bottleneck: {machine.code} running at 45% speed due to draft roller slippage.",
                )

        elif stype == ScenarioType.QUALITY_DEFECT_SPIKE:
            # Inject defect into current batch
            active_batch = machine.batches.filter(status="RUNNING").first()
            if active_batch and random.random() < 0.3:
                inspection_code = f"QC-{now.strftime('%H%M%S')}-{machine.code}"
                if not QualityInspection.objects.filter(inspection_code=inspection_code).exists():
                    insp = QualityInspection.objects.create(
                        inspection_code=inspection_code,
                        production_batch=active_batch,
                        machine=machine,
                        inspector_name="Automated In-line Optical Scanner",
                        sample_size=100.0,
                        inspected_quantity=100.0,
                        accepted_quantity=72.0,
                        rejected_quantity=28.0,
                        status="FAILED",
                        overall_score=72.50,
                        notes="High incidence of barre defects and yarn count variation Delta > 2.8%",
                    )
                    QualityDefect.objects.create(
                        inspection=insp,
                        defect_type=DefectType.BARRE_EFFECT if machine.department.department_type == DepartmentType.KNITTING else DefectType.YARN_UNEVENNESS,
                        severity="CRITICAL",
                        count=14,
                        defect_location="Across Full Width",
                        root_cause_category="Mechanical Speed Deviation",
                    )

        elif stype == ScenarioType.SPARE_PART_SHORTAGE:
            # Deplete critical inventory
            item = InventoryItem.objects.filter(category="SPARE_PART", current_stock__gt=2).first()
            if item:
                item.current_stock = 1.0
                item.save(update_fields=["current_stock"])
                InventoryTransaction.objects.create(
                    item=item,
                    transaction_type="ISSUE",
                    quantity=10.0,
                    reference_number=f"SIM-DEPLETION-{scenario.id}",
                    notes="Emergency spare parts depletion scenario triggered",
                )

        elif stype == ScenarioType.ENERGY_SURGE:
            # Inject power spike
            power = round(power * 2.4, 2)
            status_flag = "WARNING"

        return temp, vib, rpm, power, util, output_rate, status_flag

    def _advance_production_batches(self, now: datetime, speed_multiplier: float):
        """Advances quantities in active production batches and updates completed orders."""
        active_batches = ProductionBatch.objects.filter(status="RUNNING").select_related("machine", "production_order")
        for batch in active_batches:
            if not batch.machine:
                continue

            # Calculate batch output increment
            rate_per_sec = float(batch.machine.rated_capacity_units_per_hour) / 3600.0
            increment = round(rate_per_sec * 3.0 * speed_multiplier, 2)

            batch.actual_quantity = round(float(batch.actual_quantity) + increment, 2)
            order = batch.production_order
            order.completed_quantity = round(float(order.completed_quantity) + increment, 2)

            if order.completed_quantity >= order.target_quantity:
                order.status = OrderStatus.COMPLETED
                order.completed_at = now
                batch.status = "COMPLETED"
                batch.completed_at = now
                batch.save(update_fields=["actual_quantity", "status", "completed_at"])
                order.save(update_fields=["completed_quantity", "status", "completed_at"])
            else:
                batch.save(update_fields=["actual_quantity"])
                order.save(update_fields=["completed_quantity"])

    def _prune_old_records(self):
        """Retains recent telemetry while pruning records beyond 3,000 to keep SQLite fast."""
        try:
            total_telemetry = MachineTelemetry.objects.count()
            if total_telemetry > 3000:
                cutoff_id = MachineTelemetry.objects.order_by("-id").values_list("id", flat=True)[2500]
                MachineTelemetry.objects.filter(id__lt=cutoff_id).delete()

            total_energy = EnergyReading.objects.count()
            if total_energy > 3000:
                cutoff_energy_id = EnergyReading.objects.order_by("-id").values_list("id", flat=True)[2500]
                EnergyReading.objects.filter(id__lt=cutoff_energy_id).delete()
        except Exception as e:
            logger.warning("Pruning old simulation records skipped: %s", e)
