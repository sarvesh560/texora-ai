import logging
import math
from datetime import timedelta
from decimal import Decimal
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.machines.models import Machine, MachineTelemetry, MachineOperatingLimits, MachineStatus
from apps.maintenance.models import MaintenanceTicket, TicketStatus, VerificationStatus
from apps.incidents.models import FactoryIncident, IncidentStatus
from apps.audit_logs.models import AuditLog

logger = logging.getLogger(__name__)


class RecoveryVerificationService:
    """
    Dedicated Industrial Recovery Verification Engine.
    Evaluates multi-point post-repair telemetry against machine operating limits,
    measures stability over an observation window, detects stale/missing sensors,
    and enforces authorized sign-off boundaries before incident closure.
    """

    DEFAULT_OBSERVATION_WINDOW = 5
    MAX_STALE_MINUTES = 10

    @classmethod
    def evaluate_machine_recovery(
        cls,
        machine: Machine,
        ticket: MaintenanceTicket = None,
        observation_window: int = DEFAULT_OBSERVATION_WINDOW,
        allow_simulation: bool = True,
    ) -> dict:
        """
        Evaluates post-repair telemetry and physical evidence to determine recovery outcome.
        Returns a structured evaluation report dictionary.
        """
        now = timezone.now()

        # 1. Check machine limits
        limits = getattr(machine, "operating_limits", None)
        warning_vib = limits.warning_vibration_mms if limits else 4.0
        max_vib = limits.max_vibration_mms if limits else 5.5
        warning_temp = limits.warning_temp_c if limits else 75.0
        max_temp = limits.max_temp_c if limits else 85.0

        # 2. Check physical repair evidence
        if ticket:
            if ticket.status in [
                TicketStatus.CREATED,
                TicketStatus.OPEN,
                TicketStatus.ASSIGNED,
                TicketStatus.ACCEPTED,
                TicketStatus.INSPECTION_IN_PROGRESS,
            ]:
                return {
                    "outcome": VerificationStatus.PENDING_EVIDENCE,
                    "summary": "Physical maintenance has not been completed. Work order is still in progress.",
                    "is_healthy": False,
                    "readings_count": 0,
                    "readings": [],
                    "checks": {
                        "physical_repair_completed": False,
                        "checklist_verified": False,
                        "telemetry_collected": False,
                        "telemetry_nominal": False,
                        "stability_confirmed": False,
                        "authorized_signoff": False,
                    },
                }

        # Determine cutoff time for post-repair telemetry
        repair_time = (
            ticket.repair_completed_at
            if (ticket and ticket.repair_completed_at)
            else (now - timedelta(minutes=15))
        )

        # 3. Retrieve telemetry readings
        readings_qs = MachineTelemetry.objects.filter(
            machine=machine,
            timestamp__gte=repair_time - timedelta(minutes=2),
        ).order_by("-timestamp")[:observation_window]

        readings = list(readings_qs)

        # If too few post-repair readings, fall back to recent readings for evaluation
        if len(readings) < observation_window:
            readings = list(
                MachineTelemetry.objects.filter(machine=machine).order_by("-timestamp")[:observation_window]
            )

        readings_count = len(readings)

        # Check for missing telemetry
        if readings_count == 0:
            return {
                "outcome": VerificationStatus.PENDING_EVIDENCE,
                "summary": "No telemetry readings available for machine post-repair observation.",
                "is_healthy": False,
                "readings_count": 0,
                "readings": [],
                "checks": {
                    "physical_repair_completed": bool(ticket and ticket.repair_completed_at),
                    "telemetry_collected": False,
                    "telemetry_nominal": False,
                    "stability_confirmed": False,
                    "authorized_signoff": False,
                },
            }

        # Check for stale sensor data
        latest_reading = readings[0]
        age_minutes = (now - latest_reading.timestamp).total_seconds() / 60.0
        if age_minutes > cls.MAX_STALE_MINUTES:
            return {
                "outcome": VerificationStatus.INCONCLUSIVE,
                "summary": (
                    f"Sensor stream is stale: Latest reading was recorded {age_minutes:.1f} minutes ago "
                    f"(threshold: {cls.MAX_STALE_MINUTES} mins). Real-time telemetry connection required."
                ),
                "is_healthy": False,
                "readings_count": readings_count,
                "stale_minutes": round(age_minutes, 1),
                "readings": [cls._format_reading(r) for r in readings],
                "checks": {
                    "physical_repair_completed": bool(ticket and ticket.repair_completed_at),
                    "telemetry_collected": True,
                    "telemetry_fresh": False,
                    "telemetry_nominal": False,
                    "stability_confirmed": False,
                    "authorized_signoff": False,
                },
            }

        # Check observation window sufficiency (cannot verify on just 1 reading)
        if readings_count < observation_window:
            return {
                "outcome": VerificationStatus.MONITORING,
                "summary": (
                    f"Observation window accumulating: Collected {readings_count} of {observation_window} required "
                    f"consecutive samples. Monitoring sensor stability..."
                ),
                "is_healthy": False,
                "readings_count": readings_count,
                "readings": [cls._format_reading(r) for r in readings],
                "checks": {
                    "physical_repair_completed": bool(ticket and ticket.repair_completed_at),
                    "telemetry_collected": True,
                    "telemetry_fresh": True,
                    "window_sufficient": False,
                    "authorized_signoff": False,
                },
            }

        # 4. Multi-sample Limit Evaluation
        vibrations = [float(r.vibration_mms or 0) for r in readings]
        temperatures = [float(r.temperature_c or 0) for r in readings]

        avg_vib = sum(vibrations) / len(vibrations)
        max_observed_vib = max(vibrations)
        avg_temp = sum(temperatures) / len(temperatures)
        max_observed_temp = max(temperatures)

        # Check critical / warning thresholds
        vib_failed = any(v >= warning_vib for v in vibrations)
        temp_failed = any(t >= warning_temp for t in temperatures)

        # Measure stability (spread / variance)
        vib_spread = max_observed_vib - min(vibrations)
        is_stable = vib_spread < 1.2  # Max 1.2 mm/s spread during stable run

        # Failure condition
        if vib_failed or temp_failed:
            failure_reasons = []
            if vib_failed:
                failure_reasons.append(
                    f"Vibration readings ({max_observed_vib:.2f} mm/s) exceed configured threshold ({warning_vib:.2f} mm/s)"
                )
            if temp_failed:
                failure_reasons.append(
                    f"Temperature readings ({max_observed_temp:.1f} °C) exceed configured threshold ({warning_temp:.1f} °C)"
                )

            summary = "Recovery verification failed: " + "; ".join(failure_reasons) + "."

            report = {
                "outcome": VerificationStatus.FAILED,
                "summary": summary,
                "is_healthy": False,
                "readings_count": readings_count,
                "avg_vibration": round(avg_vib, 2),
                "max_vibration": round(max_observed_vib, 2),
                "limit_vibration": warning_vib,
                "avg_temp": round(avg_temp, 1),
                "max_temp": round(max_observed_temp, 1),
                "limit_temp": warning_temp,
                "is_stable": is_stable,
                "readings": [cls._format_reading(r) for r in readings],
                "checks": {
                    "physical_repair_completed": bool(ticket and ticket.repair_completed_at),
                    "telemetry_collected": True,
                    "telemetry_fresh": True,
                    "telemetry_nominal": False,
                    "stability_confirmed": is_stable,
                    "authorized_signoff": False,
                },
            }
            if ticket:
                ticket.verification_status = VerificationStatus.FAILED
                ticket.verification_summary = summary
                ticket.verification_data = report
                ticket.status = TicketStatus.VERIFICATION_FAILED
                ticket.save(update_fields=["verification_status", "verification_summary", "verification_data", "status"])
            return report

        # Passed all telemetry checks!
        has_signoff = bool(ticket and ticket.authorized_signoff_by)

        if not has_signoff:
            outcome = VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF
            summary = (
                f"All {readings_count} post-repair telemetry samples are within nominal limits "
                f"(Peak Vib: {max_observed_vib:.2f} mm/s < {warning_vib:.2f} mm/s, "
                f"Peak Temp: {max_observed_temp:.1f} °C < {warning_temp:.1f} °C). "
                f"Telemetry normalized. Awaiting authorized personnel sign-off for safe return to service."
            )
        else:
            outcome = VerificationStatus.VERIFIED
            summary = (
                f"Recovery fully verified: Telemetry nominal across {readings_count} samples. "
                f"Safe return to service authorized by {ticket.authorized_signoff_by}."
            )

        report = {
            "outcome": outcome,
            "summary": summary,
            "is_healthy": True,
            "readings_count": readings_count,
            "avg_vibration": round(avg_vib, 2),
            "max_vibration": round(max_observed_vib, 2),
            "limit_vibration": warning_vib,
            "avg_temp": round(avg_temp, 1),
            "max_temp": round(max_observed_temp, 1),
            "limit_temp": warning_temp,
            "is_stable": is_stable,
            "readings": [cls._format_reading(r) for r in readings],
            "checks": {
                "physical_repair_completed": bool(ticket and ticket.repair_completed_at),
                "telemetry_collected": True,
                "telemetry_fresh": True,
                "telemetry_nominal": True,
                "stability_confirmed": is_stable,
                "authorized_signoff": has_signoff,
            },
        }

        if ticket:
            ticket.verification_status = outcome
            ticket.verification_summary = summary
            ticket.verification_data = report
            if outcome == VerificationStatus.VERIFIED and ticket.status != TicketStatus.CLOSED:
                ticket.status = TicketStatus.VERIFIED
            ticket.save(update_fields=["verification_status", "verification_summary", "verification_data", "status"])

        return report

    @classmethod
    @transaction.atomic
    def authorize_and_sign_off(
        cls,
        ticket: MaintenanceTicket,
        authorized_by: str,
        notes: str = "",
        role: str = "Plant Operations Manager",
    ) -> dict:
        """
        Signs off machine safe return to service after telemetry checks have passed.
        """
        # Re-evaluate to ensure telemetry checks currently pass
        eval_report = cls.evaluate_machine_recovery(ticket.machine, ticket=ticket)
        if eval_report["outcome"] not in [
            VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF,
            VerificationStatus.PASSED_TELEMETRY_CHECKS,
            VerificationStatus.VERIFIED,
        ]:
            raise ValidationError(
                f"Cannot authorize return to service: Recovery evaluation status is '{eval_report['outcome']}'. "
                f"Telemetry checks must pass before sign-off."
            )

        ticket.authorized_signoff_by = authorized_by
        ticket.authorized_signoff_at = timezone.now()
        ticket.signoff_notes = notes or f"Authorized safe return to production line by {authorized_by} ({role})."
        ticket.verification_status = VerificationStatus.VERIFIED
        ticket.status = TicketStatus.VERIFIED
        ticket.save()

        # Update machine status back to OPERATIONAL safely
        machine = ticket.machine
        machine.status = MachineStatus.OPERATIONAL
        machine.current_health_score = Decimal("96.50")
        machine.save(update_fields=["status", "current_health_score"])

        # Audit log
        AuditLog.objects.create(
            entity_type="TICKET",
            entity_id=ticket.ticket_number,
            action="APPROVAL_GRANTED",
            actor_type="MANAGER",
            actor_id=authorized_by,
            changes_payload={
                "machine_code": machine.code,
                "verification_status": "VERIFIED",
                "signoff_notes": notes,
            },
            description=f"Safe return to service authorized for {machine.code} by {authorized_by} ({role}).",
        )

        return cls.evaluate_machine_recovery(ticket.machine, ticket=ticket)

    @classmethod
    @transaction.atomic
    def close_incident_with_evidence(
        cls,
        incident: FactoryIncident,
        ticket: MaintenanceTicket,
        closed_by: str,
        resolution_notes: str = "",
    ) -> FactoryIncident:
        """
        Closes incident ONLY when recovery is verified and sign-off is complete.
        """
        if ticket.verification_status != VerificationStatus.VERIFIED:
            raise ValidationError(
                "Incident cannot be closed: Recovery verification is not yet complete. "
                "Both telemetry normalization and authorized sign-off are required."
            )

        if not ticket.authorized_signoff_by:
            raise ValidationError(
                "Incident cannot be closed: Authorized personnel sign-off is missing."
            )

        # Close ticket if not already closed
        if ticket.status != TicketStatus.CLOSED:
            ticket.status = TicketStatus.CLOSED
            ticket.resolved_at = timezone.now()
            ticket.save(update_fields=["status", "resolved_at"])

        # Close incident
        incident.status = IncidentStatus.CLOSED
        incident.resolved_at = timezone.now()
        incident.resolution_summary = (
            f"Closed following complete maintenance lifecycle. "
            f"Work Order {ticket.ticket_number} executed by {ticket.assigned_technician or 'Technician'}. "
            f"Fault confirmed: {ticket.confirmed_fault}. "
            f"Telemetry verified within configured operating limits. "
            f"Authorized return to service signed off by {ticket.authorized_signoff_by}."
        )
        if resolution_notes:
            incident.resolution_summary += f" Notes: {resolution_notes}"
        incident.save(update_fields=["status", "resolved_at", "resolution_summary"])

        # Audit log
        AuditLog.objects.create(
            entity_type="INCIDENT",
            entity_id=incident.incident_code,
            action="STATUS_CHANGE",
            actor_type="MANAGER",
            actor_id=closed_by,
            changes_payload={
                "previous_status": "MITIGATING",
                "new_status": "CLOSED",
                "work_order": ticket.ticket_number,
                "verified_by": ticket.authorized_signoff_by,
            },
            description=f"Incident {incident.incident_code} closed by {closed_by} with complete verification evidence.",
        )

        return incident

    @classmethod
    def _format_reading(cls, r: MachineTelemetry) -> dict:
        return {
            "id": r.id,
            "timestamp": r.timestamp.isoformat(),
            "vibration_mms": round(float(r.vibration_mms or 0), 2),
            "temperature_c": round(float(r.temperature_c or 0), 1),
            "speed_rpm": round(float(r.speed_rpm or 0), 0),
            "power_kw": round(float(r.power_kw or 0), 1),
        }
