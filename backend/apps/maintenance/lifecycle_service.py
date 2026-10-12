import logging
from decimal import Decimal
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.maintenance.models import (
    MaintenanceTicket,
    TicketStatus,
    VerificationStatus,
    WorkOrderTransition,
)
from apps.inventory.models import InventoryItem, InventoryTransaction
from apps.audit_logs.models import AuditLog

logger = logging.getLogger(__name__)


class WorkOrderLifecycleService:
    """
    Industrial Work Order Lifecycle State Machine and Safety Barrier.
    Enforces permitted state transitions, idempotency, inspection evidence,
    transaction-safe inventory deduction, and immutable audit logs.
    """

    PERMITTED_TRANSITIONS = {
        TicketStatus.CREATED: [
            TicketStatus.ASSIGNED,
            TicketStatus.ACCEPTED,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.OPEN: [
            TicketStatus.ASSIGNED,
            TicketStatus.ACCEPTED,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.ASSIGNED: [
            TicketStatus.ACCEPTED,
            TicketStatus.INSPECTION_IN_PROGRESS,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.ACCEPTED: [
            TicketStatus.INSPECTION_IN_PROGRESS,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.INSPECTION_IN_PROGRESS: [
            TicketStatus.REPAIR_IN_PROGRESS,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.REPAIR_IN_PROGRESS: [
            TicketStatus.REPAIR_COMPLETED,
            TicketStatus.PENDING_PARTS,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.IN_PROGRESS: [
            TicketStatus.REPAIR_COMPLETED,
            TicketStatus.PENDING_PARTS,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.PENDING_PARTS: [
            TicketStatus.REPAIR_IN_PROGRESS,
            TicketStatus.BLOCKED,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.REPAIR_COMPLETED: [
            TicketStatus.AWAITING_VERIFICATION,
            TicketStatus.BLOCKED,
        ],
        TicketStatus.AWAITING_VERIFICATION: [
            TicketStatus.VERIFIED,
            TicketStatus.VERIFICATION_FAILED,
            TicketStatus.BLOCKED,
        ],
        TicketStatus.VERIFICATION_FAILED: [
            TicketStatus.REPAIR_IN_PROGRESS,
            TicketStatus.BLOCKED,
        ],
        TicketStatus.VERIFIED: [
            TicketStatus.CLOSED,
        ],
        TicketStatus.RESOLVED: [
            TicketStatus.CLOSED,
        ],
        TicketStatus.BLOCKED: [
            TicketStatus.ASSIGNED,
            TicketStatus.ACCEPTED,
            TicketStatus.INSPECTION_IN_PROGRESS,
            TicketStatus.REPAIR_IN_PROGRESS,
            TicketStatus.CANCELLED,
        ],
        TicketStatus.CANCELLED: [],
        TicketStatus.CLOSED: [],
    }

    @classmethod
    def get_standard_inspection_checklist(cls, machine):
        """Generates machine-type specific inspection checklist items with hypotheses."""
        m_type = machine.machine_type.name.upper() if machine and machine.machine_type else ""
        dept = machine.department.code.upper() if machine and machine.department else ""

        if "LOOM" in m_type or "WEAV" in dept:
            checklist = [
                {
                    "step_id": 1,
                    "task": "Measure main shaft drive bearing radial and axial vibration levels",
                    "status": "PENDING",
                    "expected_threshold": "Vibration < 4.0 mm/s",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 2,
                    "task": "Inspect bearing housing #6204 for surface temperature and heat discoloration",
                    "status": "PENDING",
                    "expected_threshold": "Temperature < 68.0 °C",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 3,
                    "task": "Check drive belt tension, pulley alignment, and eccentric shaft backlash",
                    "status": "PENDING",
                    "expected_threshold": "Belt deflection 10-12 mm",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 4,
                    "task": "Inspect lubrication channels and grease pack contamination",
                    "status": "PENDING",
                    "expected_threshold": "Lithium EP2 grease clean, no metal flakes",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 5,
                    "task": "Inspect sley motion mechanism and sley sword pivot bearings for looseness",
                    "status": "PENDING",
                    "expected_threshold": "Zero perceptible mechanical play (< 0.05 mm)",
                    "observed_value": "",
                    "notes": "",
                },
            ]
            suspected_causes = [
                {"cause": "Bearing inner/outer race fatigue wear", "likelihood": "HIGH", "category": "Mechanical Wear"},
                {"cause": "Mechanical unbalance on main drive shaft", "likelihood": "MEDIUM", "category": "Dynamic Imbalance"},
                {"cause": "Shaft misalignment or loose mounting bracket", "likelihood": "MEDIUM", "category": "Mounting"},
                {"cause": "Insufficient grease lubrication in bearing housing", "likelihood": "LOW", "category": "Tribology"},
                {"cause": "Drive belt slip or worn eccentric gear", "likelihood": "LOW", "category": "Transmission"},
            ]
        elif "SPIN" in m_type or "SPN" in dept:
            checklist = [
                {
                    "step_id": 1,
                    "task": "Measure spindle bearing high-speed vibration at rated RPM",
                    "status": "PENDING",
                    "expected_threshold": "Vibration < 3.8 mm/s",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 2,
                    "task": "Measure draft roller bearing temperature with IR thermometer",
                    "status": "PENDING",
                    "expected_threshold": "Temperature < 72.0 °C",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 3,
                    "task": "Inspect spindle tape tension and pulley bearing condition",
                    "status": "PENDING",
                    "expected_threshold": "Tension nominal, tape wear < 15%",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 4,
                    "task": "Inspect ring rail oscillation guide rods and traverse bearings",
                    "status": "PENDING",
                    "expected_threshold": "Smooth oscillation, no binding",
                    "observed_value": "",
                    "notes": "",
                },
            ]
            suspected_causes = [
                {"cause": "Drafting roller bearing roller pitting", "likelihood": "HIGH", "category": "Bearing Wear"},
                {"cause": "Spindle tape slip / worn spindle bolster", "likelihood": "MEDIUM", "category": "Transmission"},
                {"cause": "Lint/fluff packing into bearing seal gap", "likelihood": "MEDIUM", "category": "Contamination"},
                {"cause": "Drive motor bearing fatigue", "likelihood": "LOW", "category": "Motor"},
            ]
        else:
            checklist = [
                {
                    "step_id": 1,
                    "task": "Measure motor and primary drive shaft vibration levels",
                    "status": "PENDING",
                    "expected_threshold": "Vibration within machine limits",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 2,
                    "task": "Measure bearing housing operating temperature",
                    "status": "PENDING",
                    "expected_threshold": "Temperature within machine limits",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 3,
                    "task": "Inspect mechanical couplings and mounting bolt torque",
                    "status": "PENDING",
                    "expected_threshold": "Torque to OEM spec, no looseness",
                    "observed_value": "",
                    "notes": "",
                },
                {
                    "step_id": 4,
                    "task": "Verify lubrication level and oil/grease condition",
                    "status": "PENDING",
                    "expected_threshold": "Clean oil at level indicator",
                    "observed_value": "",
                    "notes": "",
                },
            ]
            suspected_causes = [
                {"cause": "Bearing wear / race degradation", "likelihood": "HIGH", "category": "Bearing"},
                {"cause": "Coupling misalignment", "likelihood": "MEDIUM", "category": "Alignment"},
                {"cause": "Lubrication starvation", "likelihood": "MEDIUM", "category": "Lubrication"},
            ]

        return checklist, suspected_causes

    @classmethod
    def populate_checklist_if_empty(cls, ticket):
        """Ensures the ticket has an inspection checklist and AI hypotheses."""
        if not ticket.inspection_checklist:
            checklist, causes = cls.get_standard_inspection_checklist(ticket.machine)
            ticket.inspection_checklist = checklist
            if not ticket.ai_suspected_causes:
                ticket.ai_suspected_causes = causes
            ticket.save(update_fields=["inspection_checklist", "ai_suspected_causes"])
        return ticket

    @classmethod
    @transaction.atomic
    def transition_state(
        cls,
        ticket: MaintenanceTicket,
        new_state: str,
        actor: str,
        actor_role: str = "Technician",
        reason: str = "",
        payload: dict = None,
    ) -> MaintenanceTicket:
        """
        Executes a validated state transition with idempotency protection and audit logging.
        """
        payload = payload or {}
        current_state = ticket.status

        # Idempotency guard: already at requested state
        if current_state == new_state:
            logger.info("Idempotent transition: Ticket %s already in state %s", ticket.ticket_number, new_state)
            return ticket

        # Enforce state machine rules
        allowed = cls.PERMITTED_TRANSITIONS.get(current_state, [])
        if new_state not in allowed:
            raise ValidationError(
                f"Invalid state transition from '{current_state}' to '{new_state}'. "
                f"Permitted next states: {allowed}."
            )

        # Validate prerequisite evidence for specific transitions
        if new_state == TicketStatus.REPAIR_IN_PROGRESS:
            # Inspection must have been performed & fault confirmed
            checklist = ticket.inspection_checklist or []
            completed_steps = [item for item in checklist if item.get("status") in ["PASS", "COMPLETED", "DEFECT_FOUND"]]
            confirmed_fault = payload.get("confirmed_fault") or ticket.confirmed_fault
            if not completed_steps and not payload.get("inspection_checklist"):
                raise ValidationError(
                    "Inspection evidence required: Cannot transition to REPAIR_IN_PROGRESS without completing "
                    "at least one inspection checklist item."
                )
            if not confirmed_fault:
                raise ValidationError(
                    "Confirmed fault required: Technician must record the confirmed physical fault before starting repair."
                )

        elif new_state == TicketStatus.REPAIR_COMPLETED:
            # Repair documentation required
            repair_performed = payload.get("repair_performed") or ticket.repair_performed
            duration = payload.get("actual_repair_duration_minutes") or ticket.actual_repair_duration_minutes
            if not repair_performed or len(repair_performed.strip()) < 10:
                raise ValidationError(
                    "Repair documentation required: Please describe the physical repair performed (minimum 10 characters)."
                )
            if duration <= 0:
                raise ValidationError(
                    "Actual repair duration required: Must record positive repair duration in minutes."
                )

        elif new_state == TicketStatus.CLOSED:
            # Verification required
            if ticket.verification_status != VerificationStatus.VERIFIED and ticket.status != TicketStatus.VERIFIED:
                raise ValidationError(
                    f"Cannot close work order {ticket.ticket_number}: Recovery verification must be VERIFIED with "
                    f"authorized personnel sign-off before closing."
                )

        # Apply payload updates
        if "assigned_technician" in payload:
            ticket.assigned_technician = payload["assigned_technician"]
        if "inspection_checklist" in payload:
            ticket.inspection_checklist = payload["inspection_checklist"]
        if "confirmed_fault" in payload:
            ticket.confirmed_fault = payload["confirmed_fault"]
        if "fault_confirmation_notes" in payload:
            ticket.fault_confirmation_notes = payload["fault_confirmation_notes"]
        if "repair_performed" in payload:
            ticket.repair_performed = payload["repair_performed"]
        if "actual_repair_duration_minutes" in payload:
            ticket.actual_repair_duration_minutes = payload["actual_repair_duration_minutes"]
        if "remaining_issues" in payload:
            ticket.remaining_issues = payload["remaining_issues"]
        if "authorized_signoff_by" in payload:
            ticket.authorized_signoff_by = payload["authorized_signoff_by"]
            ticket.authorized_signoff_at = timezone.now()
        if "signoff_notes" in payload:
            ticket.signoff_notes = payload["signoff_notes"]

        if new_state == TicketStatus.REPAIR_COMPLETED:
            ticket.repair_completed_at = timezone.now()
            ticket.verification_status = VerificationStatus.MONITORING
        elif new_state == TicketStatus.AWAITING_VERIFICATION:
            ticket.verification_status = VerificationStatus.MONITORING
        elif new_state == TicketStatus.VERIFIED:
            ticket.verification_status = VerificationStatus.VERIFIED
        elif new_state == TicketStatus.CLOSED:
            ticket.resolved_at = timezone.now()

        # Update state
        ticket.status = new_state
        ticket.save()

        # Record immutable audit log
        audit = AuditLog.objects.create(
            entity_type="TICKET",
            entity_id=ticket.ticket_number,
            action="STATUS_CHANGE",
            actor_type="OPERATOR" if "Tech" in actor_role else "MANAGER",
            actor_id=actor,
            changes_payload={
                "previous_state": current_state,
                "new_state": new_state,
                "incident_reference": ticket.incident_reference,
                "reason": reason,
                "confirmed_fault": ticket.confirmed_fault,
            },
            description=(
                f"Work order {ticket.ticket_number} transitioned from {current_state} to {new_state} "
                f"by {actor} ({actor_role}). {reason}".strip()
            ),
        )

        # Record transition history
        WorkOrderTransition.objects.create(
            ticket=ticket,
            actor=actor,
            actor_role=actor_role,
            previous_state=current_state,
            new_state=new_state,
            incident_reference=ticket.incident_reference,
            reason=reason,
            audit_record_id=audit.id,
        )

        logger.info(
            "Ticket %s transitioned from %s to %s by %s",
            ticket.ticket_number,
            current_state,
            new_state,
            actor,
        )
        return ticket

    @classmethod
    @transaction.atomic
    def consume_spare_parts(
        cls,
        ticket: MaintenanceTicket,
        parts: list,
        actor: str = "Technician",
    ) -> list:
        """
        Deducts spare parts transaction-safely, preventing double deduction.
        parts: list of dicts [{"item_code": "SPR-BRG-6204", "quantity": 1}]
        """
        consumed = []
        already_consumed = {
            p.get("item_code"): p for p in (ticket.parts_replaced or []) if p.get("deducted")
        }

        for part in parts:
            item_code = part.get("item_code")
            qty = Decimal(str(part.get("quantity", 1)))

            # Double-deduction guard
            if item_code in already_consumed:
                logger.warning(
                    "Part %s already deducted for ticket %s. Skipping duplicate.",
                    item_code,
                    ticket.ticket_number,
                )
                consumed.append(already_consumed[item_code])
                continue

            item = InventoryItem.objects.select_for_update().filter(item_code=item_code, is_active=True).first()
            if not item:
                # If exact item_code not found, try searching by name or category
                item = InventoryItem.objects.select_for_update().filter(category="SPARE_PART", is_active=True).first()
                if not item:
                    raise ValidationError(f"Spare part item '{item_code}' not found in factory warehouse.")

            if item.current_stock < qty:
                raise ValidationError(
                    f"Insufficient warehouse stock for '{item.name}' ({item.item_code}): "
                    f"Available {item.current_stock} {item.unit}, Requested {qty} {item.unit}."
                )

            # Deduct stock safely
            item.current_stock -= qty
            item.save(update_fields=["current_stock", "updated_at"])

            # Create warehouse transaction record
            InventoryTransaction.objects.create(
                item=item,
                transaction_type="ISSUE",
                quantity=qty,
                reference_number=ticket.ticket_number,
                recorded_by=actor,
                notes=f"Authorized consumption for Work Order {ticket.ticket_number} (Machine: {ticket.machine.code})",
            )

            consumed_record = {
                "item_code": item.item_code,
                "name": item.name,
                "quantity": float(qty),
                "unit": item.unit,
                "unit_cost": float(item.unit_cost),
                "deducted": True,
                "deducted_at": timezone.now().isoformat(),
            }
            consumed.append(consumed_record)

        # Update ticket parts_replaced
        existing = [p for p in (ticket.parts_replaced or []) if p.get("item_code") not in [c["item_code"] for c in consumed]]
        ticket.parts_replaced = existing + consumed
        ticket.parts_cost = sum([Decimal(str(p.get("unit_cost", 0))) * Decimal(str(p.get("quantity", 1))) for p in ticket.parts_replaced])
        ticket.save(update_fields=["parts_replaced", "parts_cost"])

        return consumed
