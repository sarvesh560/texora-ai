import pytest
from decimal import Decimal
from datetime import timedelta
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework.test import APIClient

from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType, MachineOperatingLimits, MachineTelemetry, MachineStatus
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus
from apps.inventory.models import InventoryItem, InventoryTransaction
from apps.maintenance.models import (
    MaintenanceTicket,
    TicketStatus,
    TicketPriority,
    VerificationStatus,
    WorkOrderTransition,
)
from apps.maintenance.lifecycle_service import WorkOrderLifecycleService
from apps.maintenance.verification_service import RecoveryVerificationService
from apps.maintenance.simulation_service import MaintenanceSimulationService
from apps.audit_logs.models import AuditLog


@pytest.fixture
def phase12_setup(db):
    """Sets up a realistic textile factory environment for maintenance testing."""
    factory = Factory.objects.create(name="Texora Mills Unit 1", code="TM-01", location="Coimbatore, TN")
    dept = Department.objects.create(
        factory=factory,
        name="Weaving Shed A",
        code="WEV",
        department_type=DepartmentType.WEAVING,
    )
    mtype = MachineType.objects.create(
        name="Air Jet Loom 340cm",
        category=DepartmentType.WEAVING,
        manufacturer="Picanol",
        model_number="OmniPlus-i",
        default_power_rating_kw=15.0,
    )
    machine = Machine.objects.create(
        code="WEV-AJ-02",
        name="Picanol OmniPlus-i Loom #2",
        machine_type=mtype,
        department=dept,
        status=MachineStatus.CRITICAL,
        rated_speed_rpm=1050,
        current_health_score=Decimal("42.00"),
    )
    limits = MachineOperatingLimits.objects.create(
        machine=machine,
        warning_vibration_mms=4.0,
        max_vibration_mms=5.5,
        warning_temp_c=75.0,
        max_temp_c=85.0,
        min_rpm=700,
        max_rpm=1200,
    )
    spare_part = InventoryItem.objects.create(
        item_code="SPR-BRG-6204",
        name="Deep Groove Ball Bearing 6204-2RSH",
        category="SPARE_PART",
        current_stock=Decimal("12.00"),
        minimum_safety_stock=Decimal("3.00"),
        unit="PCS",
        unit_cost=Decimal("850.00"),
    )
    incident = FactoryIncident.objects.create(
        incident_code="INC-2026-0099",
        factory=factory,
        department=dept,
        machine=machine,
        severity=IncidentSeverity.CRITICAL,
        status=IncidentStatus.MITIGATING,
        summary="Excessive loom main drive vibration detected on WEV-AJ-02",
        root_cause_hypothesis="Drive end bearing wear on main eccentric shaft",
    )
    ticket = MaintenanceTicket.objects.create(
        ticket_number="MNT-2026-0099",
        machine=machine,
        incident_reference=incident.incident_code,
        title="Repair: Excessive main drive vibration on WEV-AJ-02",
        description="Authorized work order following manager approval.",
        priority=TicketPriority.CRITICAL,
        status=TicketStatus.CREATED,
        assigned_technician="Fast Response Mechanical Specialist",
    )
    return {
        "factory": factory,
        "department": dept,
        "machine": machine,
        "limits": limits,
        "spare_part": spare_part,
        "incident": incident,
        "ticket": ticket,
    }


@pytest.mark.django_db
class TestWorkOrderLifecycle:
    """Tests the state transitions, validation barriers, and idempotency."""

    def test_checklist_population(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        assert len(ticket.inspection_checklist) == 0

        WorkOrderLifecycleService.populate_checklist_if_empty(ticket)
        ticket.refresh_from_db()
        assert len(ticket.inspection_checklist) >= 4
        assert len(ticket.ai_suspected_causes) >= 3
        # Check hypothesis framing
        assert any("bearing" in cause["cause"].lower() for cause in ticket.ai_suspected_causes)

    def test_transition_created_to_accepted(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.ACCEPTED,
            actor="R. Sharma",
            actor_role="Field Technician",
            reason="Accepted work order dispatch",
        )
        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.ACCEPTED

        # Verify audit log & transition log
        trans = WorkOrderTransition.objects.filter(ticket=ticket).first()
        assert trans is not None
        assert trans.previous_state == TicketStatus.CREATED
        assert trans.new_state == TicketStatus.ACCEPTED
        assert trans.actor == "R. Sharma"

        audit = AuditLog.objects.filter(entity_id=ticket.ticket_number).first()
        assert audit is not None
        assert audit.action == "STATUS_CHANGE"

    def test_inspection_evidence_required_for_repair(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        WorkOrderLifecycleService.populate_checklist_if_empty(ticket)
        ticket.status = TicketStatus.INSPECTION_IN_PROGRESS
        ticket.save()

        # Attempt to transition to REPAIR_IN_PROGRESS without completing checklist or confirming fault
        with pytest.raises(ValidationError) as exc:
            WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.REPAIR_IN_PROGRESS,
                actor="R. Sharma",
            )
        assert "Inspection evidence required" in str(exc.value)

    def test_repair_documentation_required_for_completion(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.REPAIR_IN_PROGRESS
        ticket.confirmed_fault = "Bearing inner race pitting"
        ticket.save()

        # Attempt to complete without repair description
        with pytest.raises(ValidationError) as exc:
            WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.REPAIR_COMPLETED,
                actor="R. Sharma",
                payload={"repair_performed": "short", "actual_repair_duration_minutes": 0},
            )
        assert "Repair documentation required" in str(exc.value)

    def test_idempotent_transition(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.ACCEPTED
        ticket.save()

        # Transitioning to same state should be a no-op
        initial_trans_count = WorkOrderTransition.objects.filter(ticket=ticket).count()
        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.ACCEPTED,
            actor="R. Sharma",
        )
        assert WorkOrderTransition.objects.filter(ticket=ticket).count() == initial_trans_count


@pytest.mark.django_db
class TestInventorySafetyAndConsumption:
    """Tests transaction-safe spare part deduction and double-deduction prevention."""

    def test_spare_part_consumption(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        part = phase12_setup["spare_part"]
        initial_stock = part.current_stock

        consumed = WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket,
            parts=[{"item_code": part.item_code, "quantity": 2}],
            actor="R. Sharma",
        )
        assert len(consumed) == 1
        part.refresh_from_db()
        assert part.current_stock == initial_stock - Decimal("2.00")

        # Warehouse transaction recorded
        tx = InventoryTransaction.objects.filter(reference_number=ticket.ticket_number).first()
        assert tx is not None
        assert tx.transaction_type == "ISSUE"
        assert tx.quantity == Decimal("2.00")

    def test_prevent_double_deduction(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        part = phase12_setup["spare_part"]

        WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket,
            parts=[{"item_code": part.item_code, "quantity": 1}],
            actor="R. Sharma",
        )
        part.refresh_from_db()
        stock_after_first = part.current_stock

        # Second attempt for same item should be ignored safely
        WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket,
            parts=[{"item_code": part.item_code, "quantity": 1}],
            actor="R. Sharma",
        )
        part.refresh_from_db()
        assert part.current_stock == stock_after_first


@pytest.mark.django_db
class TestRecoveryVerificationEngine:
    """Tests the dedicated RecoveryVerificationService rules and safety gates."""

    def test_pending_evidence_when_repair_not_done(self, phase12_setup):
        machine = phase12_setup["machine"]
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.ACCEPTED
        ticket.save()

        eval_report = RecoveryVerificationService.evaluate_machine_recovery(machine=machine, ticket=ticket)
        assert eval_report["outcome"] == VerificationStatus.PENDING_EVIDENCE
        assert eval_report["is_healthy"] is False

    def test_stale_telemetry_detection(self, phase12_setup):
        machine = phase12_setup["machine"]
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.REPAIR_COMPLETED
        ticket.repair_completed_at = timezone.now() - timedelta(minutes=30)
        ticket.save()

        # Generate telemetry with timestamps 25 minutes ago
        MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="STALE")

        eval_report = RecoveryVerificationService.evaluate_machine_recovery(machine=machine, ticket=ticket)
        assert eval_report["outcome"] == VerificationStatus.INCONCLUSIVE
        assert "stale" in eval_report["summary"].lower()

    def test_failed_recovery_telemetry(self, phase12_setup):
        machine = phase12_setup["machine"]
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        # Generate faulty telemetry (vibration ~6.5 mm/s > warning limit 4.0)
        MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="FAULTY")

        eval_report = RecoveryVerificationService.evaluate_machine_recovery(machine=machine, ticket=ticket)
        assert eval_report["outcome"] == VerificationStatus.FAILED
        assert eval_report["is_healthy"] is False
        assert eval_report["max_vibration"] > 4.0

    def test_successful_telemetry_awaiting_signoff(self, phase12_setup):
        machine = phase12_setup["machine"]
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        # Generate healthy telemetry (vibration 2.1-2.6 mm/s < 4.0)
        MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="HEALTHY")

        eval_report = RecoveryVerificationService.evaluate_machine_recovery(machine=machine, ticket=ticket)
        assert eval_report["outcome"] == VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF
        assert eval_report["is_healthy"] is True
        assert eval_report["max_vibration"] < 4.0

    def test_authorized_signoff_and_closure(self, phase12_setup):
        machine = phase12_setup["machine"]
        ticket = phase12_setup["ticket"]
        incident = phase12_setup["incident"]
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="HEALTHY")

        # Sign-off by plant manager
        signed_report = RecoveryVerificationService.authorize_and_sign_off(
            ticket=ticket,
            authorized_by="V. Ramanathan (Plant Operations Manager)",
            notes="Observed nominal vibration spectrum. Cleared for weaving production.",
        )
        assert signed_report["outcome"] == VerificationStatus.VERIFIED
        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.VERIFIED
        assert ticket.authorized_signoff_by == "V. Ramanathan (Plant Operations Manager)"
        machine.refresh_from_db()
        assert machine.status == MachineStatus.OPERATIONAL

        # Close incident with evidence
        closed_inc = RecoveryVerificationService.close_incident_with_evidence(
            incident=incident,
            ticket=ticket,
            closed_by="V. Ramanathan",
            resolution_notes="Closed following full verification lifecycle.",
        )
        assert closed_inc.status == IncidentStatus.CLOSED
        assert closed_inc.resolved_at is not None
        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.CLOSED

    def test_cannot_close_incident_without_verification(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        incident = phase12_setup["incident"]
        ticket.status = TicketStatus.CREATED
        ticket.save()

        with pytest.raises(ValidationError) as exc:
            RecoveryVerificationService.close_incident_with_evidence(
                incident=incident,
                ticket=ticket,
                closed_by="Unauthorized User",
            )
        assert "Recovery verification is not yet complete" in str(exc.value)


@pytest.mark.django_db
class TestCompleteSimulatedTechnicianWorkflow:
    """Tests the full simulated technician execution path for WEV-AJ-02."""

    def test_full_successful_expo_demonstration(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        result = MaintenanceSimulationService.execute_demo_technician_flow(
            ticket=ticket,
            mode="HEALTHY",
            actor="R. Sharma (Senior Diagnostic Tech)",
        )
        ticket.refresh_from_db()
        assert ticket.status in [TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED]
        assert ticket.confirmed_fault != ""
        assert ticket.repair_performed != ""
        assert ticket.actual_repair_duration_minutes == 45
        assert result["evaluation_report"]["is_healthy"] is True
        assert result["evaluation_report"]["outcome"] == VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF

    def test_failed_recovery_demonstration_scenario(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        result = MaintenanceSimulationService.execute_demo_technician_flow(
            ticket=ticket,
            mode="FAULTY",
            actor="R. Sharma",
        )
        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.VERIFICATION_FAILED
        assert result["evaluation_report"]["is_healthy"] is False
        assert result["evaluation_report"]["outcome"] == VerificationStatus.FAILED


@pytest.mark.django_db
class TestStateAwareTransitionsAndRegression:
    """
    Regression test suite for tickets in AWAITING_VERIFICATION and invalid state transitions:
    - Simulating repair on a ticket already in AWAITING_VERIFICATION does not error or repeat repair.
    - Prevents duplicate spare-part deductions and duplicate repair-completion records.
    - API endpoints enforce state-aware validation and return clear error messages.
    - Repeated simulation calls (e.g. rapid double clicks) are idempotent and safe.
    """

    def test_simulation_on_ticket_already_awaiting_verification_healthy(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        spare_part = phase12_setup["spare_part"]

        # First run: advances CREATED -> ... -> AWAITING_VERIFICATION
        res1 = MaintenanceSimulationService.execute_demo_technician_flow(ticket, mode="HEALTHY")
        ticket.refresh_from_db()
        assert ticket.status in [TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED]

        initial_parts_count = len(ticket.parts_replaced)
        spare_part.refresh_from_db()
        stock_after_first_run = spare_part.current_stock
        transitions_count_first_run = ticket.transitions.count()

        # Ensure ticket is specifically in AWAITING_VERIFICATION
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.save(update_fields=["status"])

        # Second run (repeated click or simulating on ticket already awaiting verification):
        res2 = MaintenanceSimulationService.execute_demo_technician_flow(ticket, mode="HEALTHY")
        ticket.refresh_from_db()

        # Must remain in AWAITING_VERIFICATION without invalid transition errors
        assert ticket.status == TicketStatus.AWAITING_VERIFICATION
        assert res2["evaluation_report"]["is_healthy"] is True
        assert res2["evaluation_report"]["outcome"] == VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF

        # Verify NO duplicate spare-part deductions occurred
        spare_part.refresh_from_db()
        assert spare_part.current_stock == stock_after_first_run
        assert len(ticket.parts_replaced) == initial_parts_count

        # Verify NO duplicate REPAIR_COMPLETED transitions were recorded
        repair_completed_transitions = ticket.transitions.filter(new_state=TicketStatus.REPAIR_COMPLETED)
        assert repair_completed_transitions.count() == 1

    def test_simulation_on_ticket_already_awaiting_verification_faulty(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        spare_part = phase12_setup["spare_part"]

        # Put ticket into AWAITING_VERIFICATION
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.parts_replaced = [{"item_code": spare_part.item_code, "quantity": 1.0, "deducted": True}]
        ticket.save()

        initial_stock = spare_part.current_stock

        # Simulate Faulty telemetry on AWAITING_VERIFICATION ticket
        res = MaintenanceSimulationService.execute_demo_technician_flow(ticket, mode="FAULTY")
        ticket.refresh_from_db()

        # Permitted transition from AWAITING_VERIFICATION to VERIFICATION_FAILED
        assert ticket.status == TicketStatus.VERIFICATION_FAILED
        assert ticket.verification_status == VerificationStatus.FAILED
        assert res["evaluation_report"]["is_healthy"] is False
        assert res["evaluation_report"]["max_vibration"] > 4.0

        # Stock must not have changed
        spare_part.refresh_from_db()
        assert spare_part.current_stock == initial_stock

        # Now re-simulate Healthy from VERIFICATION_FAILED (corrective repair cycle)
        res_healthy = MaintenanceSimulationService.execute_demo_technician_flow(ticket, mode="HEALTHY")
        ticket.refresh_from_db()
        assert ticket.status in [TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED]
        assert res_healthy["evaluation_report"]["is_healthy"] is True

        # Part is already in parts_replaced, so no double deduction
        spare_part.refresh_from_db()
        assert spare_part.current_stock == initial_stock

    def test_api_complete_repair_rejects_when_awaiting_verification(self, phase12_setup):
        client = APIClient()
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        url = f"/api/v1/maintenance/tickets/{ticket.id}/complete-repair/"
        resp = client.post(url, {
            "repair_performed": "Repeated attempt to complete repair on already completed work order.",
            "actual_duration_minutes": 30,
        }, format="json")

        assert resp.status_code == 400
        assert "already been completed" in resp.data["error"]
        assert "AWAITING_VERIFICATION" in resp.data["error"]

    def test_api_consume_parts_rejects_when_awaiting_verification(self, phase12_setup):
        client = APIClient()
        ticket = phase12_setup["ticket"]
        spare_part = phase12_setup["spare_part"]
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        # Attempt to deduct an additional part
        url = f"/api/v1/maintenance/tickets/{ticket.id}/consume-parts/"
        resp = client.post(url, {
            "parts": [{"item_code": "SPR-NEW-PART", "quantity": 1}],
        }, format="json")

        assert resp.status_code == 400
        assert "Cannot deduct spare parts" in resp.data["error"]

    def test_api_submit_inspection_rejects_when_awaiting_verification(self, phase12_setup):
        client = APIClient()
        ticket = phase12_setup["ticket"]
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        url = f"/api/v1/maintenance/tickets/{ticket.id}/submit-inspection/"
        resp = client.post(url, {
            "confirmed_fault": "Attempt to re-inspect confirmed fault",
        }, format="json")

        assert resp.status_code == 400
        assert "Diagnostic inspection already completed" in resp.data["error"]

    def test_rapid_repeated_button_clicks_simulation(self, phase12_setup):
        ticket = phase12_setup["ticket"]
        spare_part = phase12_setup["spare_part"]

        # Run 3 consecutive clicks of execute_demo_technician_flow
        for i in range(3):
            MaintenanceSimulationService.execute_demo_technician_flow(ticket, mode="HEALTHY")
            ticket.refresh_from_db()

        # Ticket must cleanly be in awaiting verification / verified
        assert ticket.status in [TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED]
        # Only 1 part deduction was ever performed
        spare_part.refresh_from_db()
        assert spare_part.current_stock == Decimal("11.00")  # 12 - 1 = 11
        # Exactly 1 repair completed transition
        assert ticket.transitions.filter(new_state=TicketStatus.REPAIR_COMPLETED).count() == 1

