import time
import math
import uuid
import logging
import threading
from typing import Optional, Dict, Any, List
from django.db import transaction, close_old_connections
from django.utils import timezone

from apps.machines.models import Machine, MachineOperatingLimits, MachineTelemetry, MachineStatus
from apps.factories.models import Department
from apps.incidents.models import (
    FactoryIncident,
    AnomalyDetection,
    DetectionCheckpoint,
    IncidentSeverity,
    IncidentStatus,
    IncidentCategory,
)

logger = logging.getLogger(__name__)


class AnomalyDetector:
    """
    Autonomous Industrial IoT Anomaly Detection Engine for Textile Operations.
    Continuously monitors persisted telemetry, applies rolling-window and baseline physics rules,
    correlates anomalies, manages incident lifecycles, and executes recovery transitions.
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(AnomalyDetector, cls).__new__(cls)
                cls._instance._is_initialized = False
            return cls._instance

    def __init__(self):
        if self._is_initialized:
            return
        self._is_initialized = True
        self._thread = None
        self._stop_requested = threading.Event()
        self._pause_requested = threading.Event()

    def start(self, poll_interval: float = 2.0):
        """Starts background detection worker loop."""
        with self._lock:
            checkpoint = DetectionCheckpoint.get_checkpoint()
            checkpoint.is_worker_running = True
            checkpoint.save(update_fields=["is_worker_running", "updated_at"])

            self._stop_requested.clear()
            self._pause_requested.clear()

            if self._thread is None or not self._thread.is_alive():
                self._thread = threading.Thread(
                    target=self._run_loop,
                    args=(poll_interval,),
                    name="TexoraAnomalyDetectionWorker",
                    daemon=True,
                )
                self._thread.start()
                logger.info("Autonomous Anomaly Detection worker started.")

    def pause(self):
        """Pauses the detection worker."""
        with self._lock:
            self._pause_requested.set()
            logger.info("Anomaly Detection worker paused.")

    def resume(self):
        """Resumes the detection worker."""
        with self._lock:
            self._pause_requested.clear()
            logger.info("Anomaly Detection worker resumed.")

    def stop(self):
        """Stops the detection worker thread."""
        with self._lock:
            checkpoint = DetectionCheckpoint.get_checkpoint()
            checkpoint.is_worker_running = False
            checkpoint.save(update_fields=["is_worker_running", "updated_at"])

            self._stop_requested.set()
            self._pause_requested.clear()
            logger.info("Anomaly Detection worker stop requested.")

    def is_active(self) -> bool:
        """Returns True if the background detection worker thread is alive."""
        return self._thread is not None and self._thread.is_alive()

    def _run_loop(self, poll_interval: float):
        """Main detection loop processing new telemetry records incrementally."""
        while not self._stop_requested.is_set():
            if self._pause_requested.is_set():
                time.sleep(0.5)
                continue

            try:
                close_old_connections()
                self.run_cycle(batch_size=100)
                time.sleep(poll_interval)
            except Exception as e:
                logger.error("Error during anomaly detection cycle: %s", e, exc_info=True)
                time.sleep(2.0)
            finally:
                close_old_connections()

    @transaction.atomic
    def run_cycle(self, batch_size: int = 100) -> Dict[str, Any]:
        """
        Executes a single discrete detection evaluation cycle across new telemetry records.
        """
        now = timezone.now()
        checkpoint = DetectionCheckpoint.get_checkpoint()
        last_id = checkpoint.last_processed_telemetry_id

        # 1. Fetch unprocessed telemetry batch
        records = list(
            MachineTelemetry.objects.filter(id__gt=last_id)
            .select_related("machine", "machine__operating_limits", "machine__department", "machine__department__factory")
            .order_by("id")[:batch_size]
        )

        anomalies_detected_this_cycle = 0
        incidents_created_this_cycle = 0
        incidents_updated_this_cycle = 0
        incidents_resolved_this_cycle = 0

        if records:
            # Group records by machine to perform temporal rolling-window analysis
            machine_records_map = {}
            for r in records:
                machine_records_map.setdefault(r.machine, []).append(r)

            for machine, m_records in machine_records_map.items():
                limits = getattr(machine, "operating_limits", None)
                if not limits:
                    continue

                for r in m_records:
                    # Evaluate physical rules
                    anomaly_data = self._evaluate_telemetry_rules(machine, r, limits)

                    if anomaly_data:
                        # Process identified anomaly
                        anom_obj, inc_obj, is_new = self._process_anomaly_and_incident(
                            machine, r, anomaly_data, now
                        )
                        anomalies_detected_this_cycle += 1
                        if is_new:
                            incidents_created_this_cycle += 1
                        else:
                            incidents_updated_this_cycle += 1
                    else:
                        # Check for recovery if machine has active incidents
                        resolved = self._check_and_resolve_active_incidents(machine, r, limits, now)
                        if resolved:
                            incidents_resolved_this_cycle += len(resolved)

            # Update Checkpoint
            max_id = max(r.id for r in records)
            checkpoint.last_processed_telemetry_id = max_id
            checkpoint.total_telemetry_processed += len(records)
            checkpoint.total_anomalies_detected += anomalies_detected_this_cycle
            checkpoint.total_incidents_created += incidents_created_this_cycle
            checkpoint.last_evaluated_at = now
            checkpoint.save()
        else:
            # Check recovery on existing active incidents even when no new batch arrived
            active_incidents = FactoryIncident.objects.filter(
                status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING],
                machine__isnull=False,
            ).select_related("machine", "machine__operating_limits")
            for inc in active_incidents:
                machine = inc.machine
                limits = getattr(machine, "operating_limits", None)
                latest_reading = machine.telemetry_readings.order_by("-id").first()
                if latest_reading and limits:
                    resolved = self._check_and_resolve_active_incidents(machine, latest_reading, limits, now)
                    if resolved:
                        incidents_resolved_this_cycle += len(resolved)

        return {
            "evaluated_records": len(records),
            "anomalies_detected": anomalies_detected_this_cycle,
            "incidents_created": incidents_created_this_cycle,
            "incidents_updated": incidents_updated_this_cycle,
            "incidents_resolved": incidents_resolved_this_cycle,
            "checkpoint_last_id": checkpoint.last_processed_telemetry_id,
            "timestamp": now.isoformat(),
        }

    def _evaluate_telemetry_rules(
        self, machine: Machine, reading: MachineTelemetry, limits: MachineOperatingLimits
    ) -> Optional[Dict[str, Any]]:
        """
        Applies machine-specific industrial thresholds and rolling temporal filters.
        Distinguishes transient spikes from persistent operational deviations.
        """
        temp = reading.temperature_c
        vib = reading.vibration_mms
        rpm = reading.speed_rpm
        power = reading.power_kw

        # 1. Vibration Anomaly Rule
        if vib >= limits.max_vibration_mms:
            # Critical Vibration
            score = round(vib / max(0.1, limits.warning_vibration_mms), 2)
            return {
                "metric_name": "vibration_mms",
                "observed_value": vib,
                "threshold_value": limits.max_vibration_mms,
                "severity": IncidentSeverity.CRITICAL,
                "category": IncidentCategory.MACHINE_HEALTH,
                "anomaly_score": score,
                "confidence_pct": 98.50,
                "algorithm": "THRESHOLD_RULE",
                "summary": f"Severe mechanical vibration ({vib} mm/s) exceeding critical limit ({limits.max_vibration_mms} mm/s) on {machine.code}",
                "hypothesis": f"Elevated bearing vibration RMS on {machine.name}. Potential mechanical imbalance, misalignment, or spindle bearing wear.",
            }
        elif vib >= limits.warning_vibration_mms:
            # Check temporal persistence (2 consecutive readings or rolling mean)
            recent_readings = list(machine.telemetry_readings.filter(id__lte=reading.id).order_by("-id")[:3])
            recent_vibs = [r.vibration_mms for r in recent_readings]
            if len(recent_vibs) >= 2 and all(v >= limits.warning_vibration_mms * 0.95 for v in recent_vibs):
                score = round(vib / max(0.1, limits.warning_vibration_mms), 2)
                return {
                    "metric_name": "vibration_mms",
                    "observed_value": vib,
                    "threshold_value": limits.warning_vibration_mms,
                    "severity": IncidentSeverity.HIGH,
                    "category": IncidentCategory.MACHINE_HEALTH,
                    "anomaly_score": score,
                    "confidence_pct": 94.00,
                    "algorithm": "STATISTICAL_ZSCORE",
                    "summary": f"Persistent elevated vibration ({vib} mm/s) above warning threshold ({limits.warning_vibration_mms} mm/s) on {machine.code}",
                    "hypothesis": f"Vibration drift observed on {machine.name}. Recommend inspecting mechanical mounting and drive belt tension.",
                }

        # 2. Thermal / Overheating Anomaly Rule
        if temp >= limits.max_temp_c:
            score = round(temp / max(1.0, limits.warning_temp_c), 2)
            return {
                "metric_name": "temperature_c",
                "observed_value": temp,
                "threshold_value": limits.max_temp_c,
                "severity": IncidentSeverity.CRITICAL,
                "category": IncidentCategory.MACHINE_HEALTH,
                "anomaly_score": score,
                "confidence_pct": 99.00,
                "algorithm": "THRESHOLD_RULE",
                "summary": f"Critical thermal runaway ({temp} °C) exceeding max limit ({limits.max_temp_c} °C) on {machine.code}",
                "hypothesis": f"Severe thermal accumulation in {machine.name}. Potential lubrication failure, motor overload, or cooling duct obstruction.",
            }
        elif temp >= limits.warning_temp_c:
            recent_readings = list(machine.telemetry_readings.filter(id__lte=reading.id).order_by("-id")[:3])
            recent_temps = [r.temperature_c for r in recent_readings]
            if len(recent_temps) >= 2 and all(t >= limits.warning_temp_c * 0.98 for t in recent_temps):
                score = round(temp / max(1.0, limits.warning_temp_c), 2)
                return {
                    "metric_name": "temperature_c",
                    "observed_value": temp,
                    "threshold_value": limits.warning_temp_c,
                    "severity": IncidentSeverity.HIGH,
                    "category": IncidentCategory.MACHINE_HEALTH,
                    "anomaly_score": score,
                    "confidence_pct": 92.50,
                    "algorithm": "THRESHOLD_RULE",
                    "summary": f"Persistent high operating temperature ({temp} °C) on {machine.code}",
                    "hypothesis": f"Thermal elevation above standard baseline in {machine.name}. Check lubrication viscosity and chamber exhaust fan.",
                }

        # 3. Speed / Bottleneck Anomaly Rule
        if machine.status == MachineStatus.OPERATIONAL and limits.min_rpm > 0:
            if rpm < (limits.min_rpm * 0.85):
                return {
                    "metric_name": "speed_rpm",
                    "observed_value": float(rpm),
                    "threshold_value": float(limits.min_rpm),
                    "severity": IncidentSeverity.MEDIUM,
                    "category": IncidentCategory.PRODUCTION_BOTTLENECK,
                    "anomaly_score": 1.45,
                    "confidence_pct": 90.00,
                    "algorithm": "THRESHOLD_RULE",
                    "summary": f"Production throughput throttling: {machine.code} running at {rpm} RPM (Min rated: {limits.min_rpm} RPM)",
                    "hypothesis": f"Speed reduction detected on {machine.name}. Potential yarn draft slippage, yarn breakage stop, or feeder blockage.",
                }

        # 4. Energy Spike Anomaly Rule
        if limits.max_power_kw > 0 and power >= (limits.max_power_kw * 1.35):
            return {
                "metric_name": "power_kw",
                "observed_value": power,
                "threshold_value": limits.max_power_kw,
                "severity": IncidentSeverity.HIGH,
                "category": IncidentCategory.ENERGY_SPIKE,
                "anomaly_score": round(power / limits.max_power_kw, 2),
                "confidence_pct": 91.00,
                "algorithm": "THRESHOLD_RULE",
                "summary": f"Abnormal electrical load surge ({power} kW) on {machine.code}",
                "hypothesis": f"Power consumption exceeds rated motor capacity on {machine.name}. Check motor bearing friction and variable frequency drive harmonics.",
            }

        return None

    def _process_anomaly_and_incident(
        self, machine: Machine, reading: MachineTelemetry, anom_data: Dict[str, Any], now
    ):
        """
        Creates AnomalyDetection record and creates or correlates FactoryIncident.
        Guarantees deduplication: updates existing active incident rather than creating duplicates.
        """
        category = anom_data["category"]
        severity = anom_data["severity"]

        # Check for existing active incident on this machine and category
        existing_incident = FactoryIncident.objects.filter(
            machine=machine,
            category=category,
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING],
        ).first()

        is_new_incident = False

        if existing_incident:
            incident = existing_incident
            # Escalate severity if incoming anomaly is higher severity
            if severity == IncidentSeverity.CRITICAL and incident.severity != IncidentSeverity.CRITICAL:
                incident.severity = IncidentSeverity.CRITICAL
                incident.summary = anom_data["summary"]

            # Append evidence snapshot
            evidence = incident.evidence_data or {}
            history = evidence.setdefault("anomaly_history", [])
            history.append({
                "timestamp": now.isoformat(),
                "reading_id": reading.id,
                "metric": anom_data["metric_name"],
                "observed": anom_data["observed_value"],
                "threshold": anom_data["threshold_value"],
                "score": anom_data["anomaly_score"],
            })
            # Keep last 15 evidence entries
            evidence["anomaly_history"] = history[-15:]
            evidence["last_observed_reading"] = {
                "temp": reading.temperature_c,
                "vib": reading.vibration_mms,
                "rpm": reading.speed_rpm,
                "power": reading.power_kw,
                "timestamp": reading.timestamp.isoformat(),
            }
            incident.evidence_data = evidence
            incident.save(update_fields=["severity", "summary", "evidence_data"])
        else:
            # Create new deterministic incident
            is_new_incident = True
            incident_code = f"INC-{now.strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:6].upper()}-{machine.code}"
            incident = FactoryIncident.objects.create(
                incident_code=incident_code,
                factory=machine.department.factory,
                department=machine.department,
                machine=machine,
                severity=severity,
                status=IncidentStatus.OPEN,
                category=category,
                summary=anom_data["summary"],
                root_cause_hypothesis=anom_data["hypothesis"],
                evidence_data={
                    "initial_trigger": {
                        "reading_id": reading.id,
                        "metric": anom_data["metric_name"],
                        "observed": anom_data["observed_value"],
                        "threshold": anom_data["threshold_value"],
                        "score": anom_data["anomaly_score"],
                        "timestamp": reading.timestamp.isoformat(),
                    },
                    "anomaly_history": [{
                        "timestamp": now.isoformat(),
                        "reading_id": reading.id,
                        "metric": anom_data["metric_name"],
                        "observed": anom_data["observed_value"],
                        "threshold": anom_data["threshold_value"],
                        "score": anom_data["anomaly_score"],
                    }],
                },
                is_autonomous_action_allowed=True,
            )
            logger.warning("Autonomous Anomaly Detector CREATED INCIDENT %s on %s (%s)", incident.incident_code, machine.code, incident.summary)

        # Create AnomalyDetection row
        anomaly = AnomalyDetection.objects.create(
            incident=incident,
            machine=machine,
            telemetry_reading_id=reading.id,
            metric_name=anom_data["metric_name"],
            observed_value=anom_data["observed_value"],
            threshold_value=anom_data["threshold_value"],
            anomaly_score=anom_data["anomaly_score"],
            confidence_pct=anom_data["confidence_pct"],
            algorithm_used=anom_data["algorithm"],
        )

        return anomaly, incident, is_new_incident

    def _check_and_resolve_active_incidents(
        self, machine: Machine, reading: MachineTelemetry, limits: MachineOperatingLimits, now
    ) -> List[FactoryIncident]:
        """
        Executes sustained recovery detection with hysteresis:
        If telemetry has returned to normal operating limits for 3 consecutive readings,
        marks open incidents on this machine as RESOLVED.
        """
        active_incidents = list(
            FactoryIncident.objects.filter(
                machine=machine,
                category=IncidentCategory.MACHINE_HEALTH,
                status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING],
            )
        )

        if not active_incidents:
            return []

        # Check recent 3 readings
        recent_readings = list(
            machine.telemetry_readings.filter(id__lte=reading.id).order_by("-id")[:3]
        )

        if len(recent_readings) < 3:
            return []

        is_sustained_normal = all(
            r.temperature_c < limits.warning_temp_c
            and r.vibration_mms < limits.warning_vibration_mms
            and r.status_flag in ["NORMAL", "RECOVERED"]
            for r in recent_readings
        )

        resolved_incidents = []
        if is_sustained_normal:
            for inc in active_incidents:
                inc.status = IncidentStatus.RESOLVED
                inc.resolved_at = now
                inc.resolution_summary = (
                    f"Autonomous Recovery Confirmed: Sustained normal telemetry verified over 3 consecutive cycles. "
                    f"Current Temp: {reading.temperature_c} °C, Vibration: {reading.vibration_mms} mm/s (Below warning threshold {limits.warning_vibration_mms} mm/s)."
                )
                inc.save(update_fields=["status", "resolved_at", "resolution_summary"])
                resolved_incidents.append(inc)
                logger.info("Autonomous Anomaly Detector RESOLVED INCIDENT %s on %s", inc.incident_code, machine.code)

            # Restore machine status
            if machine.status in [MachineStatus.WARNING, MachineStatus.CRITICAL]:
                machine.status = MachineStatus.OPERATIONAL
                machine.save(update_fields=["status"])

        return resolved_incidents
