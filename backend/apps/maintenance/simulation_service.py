import logging
import random
from datetime import timedelta
from decimal import Decimal
from django.db import transaction
from django.utils import timezone

from rest_framework.exceptions import ValidationError

from apps.machines.models import Machine, MachineTelemetry, MachineOperatingLimits, MachineStatus
from apps.maintenance.models import MaintenanceTicket, TicketStatus, VerificationStatus
from apps.maintenance.lifecycle_service import WorkOrderLifecycleService
from apps.maintenance.verification_service import RecoveryVerificationService
from apps.inventory.models import InventoryItem

logger = logging.getLogger(__name__)


class MaintenanceSimulationService:
    """
    Controlled Industrial Maintenance & Recovery Simulation Service.
    Enables realistic expo demonstration of guided technician inspections,
    spare-part replacement, and post-repair telemetry verification.
    """

    @classmethod
    def generate_post_repair_telemetry(
        cls,
        machine: Machine,
        num_readings: int = 6,
        mode: str = "HEALTHY",  # HEALTHY, FAULTY, STALE
    ) -> list:
        """
        Synthesizes realistic time-series post-repair telemetry records for verification.
        """
        now = timezone.now()
        readings = []

        # Ensure monotonically increasing timestamps so successive runs never interleave readings
        latest_ts = MachineTelemetry.objects.filter(machine=machine).order_by("-timestamp").values_list("timestamp", flat=True).first()
        if latest_ts and latest_ts >= now:
            base_time = latest_ts + timedelta(seconds=1)
        else:
            base_time = now

        # Machine nominal baselines
        is_weaving = "WEAV" in machine.department.code.upper() if machine.department else True
        base_rpm = machine.rated_speed_rpm or (1050 if is_weaving else 18000)
        base_kw = 12.0 if is_weaving else 35.0

        for i in range(num_readings):
            if mode == "STALE":
                # Timestamp 25 minutes ago
                ts = now - timedelta(minutes=25) + timedelta(seconds=i * 20)
            else:
                ts = base_time + timedelta(seconds=i * 2)

            if mode == "HEALTHY":
                # Nominal healthy post-repair telemetry
                vib = round(random.uniform(2.1, 2.6), 2)
                temp = round(random.uniform(53.0, 58.5), 1)
                rpm = int(base_rpm + random.uniform(-10, 10))
                kw = round(base_kw + random.uniform(-0.5, 0.5), 1)
                util = round(random.uniform(92.0, 96.0), 1)
            elif mode == "FAULTY":
                # Unresolved vibration or thermal anomaly
                vib = round(random.uniform(5.8, 6.9), 2)
                temp = round(random.uniform(79.0, 86.0), 1)
                rpm = int(base_rpm * 0.85)
                kw = round(base_kw * 1.3, 1)
                util = round(random.uniform(70.0, 78.0), 1)
            elif mode == "STALE":
                vib = round(random.uniform(2.3, 2.7), 2)
                temp = round(random.uniform(55.0, 60.0), 1)
                rpm = base_rpm
                kw = base_kw
                util = 90.0

            r = MachineTelemetry.objects.create(
                machine=machine,
                timestamp=ts,
                vibration_mms=vib,
                temperature_c=temp,
                speed_rpm=rpm,
                power_kw=kw,
                utilization_pct=util,
                output_rate=48.0 if is_weaving else 40.0,
            )
            readings.append(r)

        logger.info(
            "Generated %d %s post-repair telemetry readings for %s",
            len(readings),
            mode,
            machine.code,
        )
        return readings

    @classmethod
    @transaction.atomic
    def execute_demo_technician_flow(
        cls,
        ticket: MaintenanceTicket,
        mode: str = "HEALTHY",
        actor: str = "R. Sharma (Senior Diagnostic Tech)",
    ) -> dict:
        """
        Executes an end-to-end simulated technician execution flow on the ticket.
        State-aware and idempotent:
        1. If ticket is CLOSED or CANCELLED: rejects with clear ValidationError.
        2. If ticket is already in AWAITING_VERIFICATION: skips repeating physical repair
           and duplicate parts deduction; generates post-repair telemetry and routes
           directly through RecoveryVerificationService.
        3. If ticket is in REPAIR_COMPLETED: safely transitions to AWAITING_VERIFICATION,
           then generates telemetry and verifies.
        4. If ticket is in VERIFICATION_FAILED: simulates re-initiating corrective repair
           (VERIFICATION_FAILED -> REPAIR_IN_PROGRESS -> REPAIR_COMPLETED -> AWAITING_VERIFICATION)
           without duplicate parts consumption.
        5. If ticket is in an early stage (CREATED/OPEN/ASSIGNED/ACCEPTED/INSPECTION): runs
           the full lifecycle sequence safely.
        """
        if ticket.status in [TicketStatus.CLOSED, TicketStatus.CANCELLED]:
            raise ValidationError(
                f"Action unavailable: Work order {ticket.ticket_number} is already '{ticket.status}'."
            )

        # Ensure checklist exists
        WorkOrderLifecycleService.populate_checklist_if_empty(ticket)

        repair_performed = (
            "Disassembled loom main drive assembly. Extracted fatigued bearing #6204 using hydraulic puller. "
            "Flushed bearing housing of metal debris and contaminated grease. Installed new OEM SKF #6204-2RSH bearing "
            "with inductive heater (110°C). Repacked with Mobilith SHC 220 synthetic grease. Realigned drive belt "
            "and torqued eccentric locking ring to 45 Nm."
        )
        confirmed_fault = (
            "Fatigue spalling and roller cage micro-fracture on main drive deep groove ball bearing #6204"
        )
        fault_notes = (
            "Acoustic and thermal inspection confirmed inner raceway fatigue spalling on bearing #6204. "
            "Pitting caused micro-impacts manifesting as excessive 6.8 mm/s radial vibration."
        )

        if ticket.status == TicketStatus.AWAITING_VERIFICATION:
            # Physical repair is already complete; do not repeat repair or parts consumption.
            logger.info(
                "Ticket %s is in AWAITING_VERIFICATION. Routing directly to post-repair verification (%s).",
                ticket.ticket_number,
                mode,
            )

        elif ticket.status == TicketStatus.REPAIR_COMPLETED:
            # Physical repair was completed; advance to AWAITING_VERIFICATION
            WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.AWAITING_VERIFICATION,
                actor=actor,
                reason="Ready for post-repair telemetry evaluation and machine run-in observation.",
            )

        elif ticket.status == TicketStatus.VERIFICATION_FAILED:
            # Ensure inspection evidence and fault are present before moving to REPAIR_IN_PROGRESS
            if not ticket.confirmed_fault:
                ticket.confirmed_fault = confirmed_fault
                ticket.fault_confirmation_notes = fault_notes
                ticket.save(update_fields=["confirmed_fault", "fault_confirmation_notes"])
            checklist = ticket.inspection_checklist or []
            has_completed = any(item.get("status") in ["PASS", "COMPLETED", "DEFECT_FOUND"] for item in checklist)
            if not has_completed:
                checklist = [
                    {"step_id": 1, "task": "Check bearing vibration", "status": "DEFECT_FOUND", "observed_value": "Vibration high"},
                    {"step_id": 2, "task": "Check bearing temperature", "status": "DEFECT_FOUND", "observed_value": "Temp elevated"},
                ]
                ticket.inspection_checklist = checklist
                ticket.save(update_fields=["inspection_checklist"])

            # Permitted transition from VERIFICATION_FAILED: return to REPAIR_IN_PROGRESS
            WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.REPAIR_IN_PROGRESS,
                actor=actor,
                reason="Re-initiating corrective repair following recovery verification failure.",
                payload={"confirmed_fault": ticket.confirmed_fault or confirmed_fault},
            )
            # Re-complete repair
            WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.REPAIR_COMPLETED,
                actor=actor,
                reason="Physical re-alignment and secondary adjustment successfully completed.",
                payload={
                    "repair_performed": repair_performed,
                    "actual_repair_duration_minutes": 30,
                    "remaining_issues": "None. Re-checked alignment and tolerances.",
                },
            )
            WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.AWAITING_VERIFICATION,
                actor=actor,
                reason="Ready for secondary post-repair telemetry evaluation.",
            )

        elif ticket.status == TicketStatus.VERIFIED:
            logger.info("Ticket %s is already VERIFIED.", ticket.ticket_number)

        else:
            # Standard lifecycle sequence for un-repaired tickets
            # 1. Accept work order if CREATED, OPEN, or ASSIGNED
            if ticket.status in [TicketStatus.CREATED, TicketStatus.OPEN, TicketStatus.ASSIGNED]:
                WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.ACCEPTED,
                    actor=actor,
                    reason="Work order accepted by field diagnostic technician.",
                )

            # 2. Begin inspection if ACCEPTED
            if ticket.status == TicketStatus.ACCEPTED:
                WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.INSPECTION_IN_PROGRESS,
                    actor=actor,
                    reason="Beginning physical and sensor-guided inspection protocols.",
                )

            # 3. Complete inspection checklist & confirm fault if INSPECTION_IN_PROGRESS
            if ticket.status == TicketStatus.INSPECTION_IN_PROGRESS:
                checklist = ticket.inspection_checklist or []
                for idx, item in enumerate(checklist):
                    if idx == 0:
                        item["status"] = "DEFECT_FOUND"
                        item["observed_value"] = "6.8 mm/s radial amplitude"
                        item["notes"] = "Elevated 2x running speed vibration harmonic detected on drive bearing housing."
                    elif idx == 1:
                        item["status"] = "DEFECT_FOUND"
                        item["observed_value"] = "76.4 °C surface temp"
                        item["notes"] = "Localized thermal spike around drive bearing #6204."
                    else:
                        item["status"] = "PASS"
                        item["observed_value"] = "Within OEM tolerance"
                        item["notes"] = "Checked and verified satisfactory."

                confirmed_fault = (
                    "Fatigue spalling and roller cage micro-fracture on main drive deep groove ball bearing #6204"
                )
                fault_notes = (
                    "Acoustic and thermal inspection confirmed inner raceway fatigue spalling on bearing #6204. "
                    "Pitting caused micro-impacts manifesting as excessive 6.8 mm/s radial vibration."
                )

                ticket.inspection_checklist = checklist
                ticket.confirmed_fault = confirmed_fault
                ticket.fault_confirmation_notes = fault_notes
                ticket.save(update_fields=["inspection_checklist", "confirmed_fault", "fault_confirmation_notes"])

                # 4. Move to REPAIR_IN_PROGRESS
                WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.REPAIR_IN_PROGRESS,
                    actor=actor,
                    reason="Fault confirmed; disassembly and bearing replacement initiated.",
                    payload={"confirmed_fault": confirmed_fault},
                )

            # 5. Consume spare parts safely (with double-deduction prevention)
            if ticket.status == TicketStatus.REPAIR_IN_PROGRESS:
                try:
                    WorkOrderLifecycleService.consume_spare_parts(
                        ticket=ticket,
                        parts=[{"item_code": "SPR-BRG-6204", "quantity": 1}],
                        actor=actor,
                    )
                except Exception as e:
                    logger.warning("Spare parts consumption warning (simulated fallback): %s", str(e))

                # 6. Complete repair
                WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.REPAIR_COMPLETED,
                    actor=actor,
                    reason="Physical component replacement and mechanical alignment successfully completed.",
                    payload={
                        "repair_performed": repair_performed,
                        "actual_repair_duration_minutes": 45,
                        "remaining_issues": "None. Shaft spins freely by hand with zero binding or axial play.",
                    },
                )

                # 7. Move to AWAITING_VERIFICATION
                WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.AWAITING_VERIFICATION,
                    actor=actor,
                    reason="Ready for post-repair telemetry evaluation and machine run-in observation.",
                )

        # 8. Generate simulated post-repair telemetry
        cls.generate_post_repair_telemetry(ticket.machine, num_readings=6, mode=mode)

        # 9. Evaluate with dedicated Recovery Verification Engine
        eval_report = RecoveryVerificationService.evaluate_machine_recovery(
            machine=ticket.machine,
            ticket=ticket,
            observation_window=5,
        )

        ticket.is_simulation = True
        ticket.save(update_fields=["is_simulation"])

        return {
            "ticket_number": ticket.ticket_number,
            "status": ticket.status,
            "verification_status": ticket.verification_status,
            "evaluation_report": eval_report,
        }
