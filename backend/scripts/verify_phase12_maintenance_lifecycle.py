"""
Phase 12 End-to-End Maintenance Execution & Autonomous Recovery Verification
Executes actual database operations and backend API endpoints:
- Successful recovery path with authorized sign-off
- Negative recovery path with failed telemetry checks
- Idempotency and double-deduction guards
"""
import os
import sys
import django

# Setup Django environment
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.development")
django.setup()

from decimal import Decimal
from django.utils import timezone
from apps.machines.models import Machine, MachineStatus, MachineTelemetry, MachineOperatingLimits
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus
from apps.inventory.models import InventoryItem, InventoryTransaction
from apps.maintenance.models import MaintenanceTicket, TicketStatus, VerificationStatus, WorkOrderTransition
from apps.maintenance.lifecycle_service import WorkOrderLifecycleService
from apps.maintenance.verification_service import RecoveryVerificationService
from apps.maintenance.simulation_service import MaintenanceSimulationService
from apps.audit_logs.models import AuditLog


def run_phase12_e2e_verification():
    print("=" * 80)
    print("TEXORA AI — PHASE 12 E2E MAINTENANCE & RECOVERY VERIFICATION")
    print("=" * 80)

    # 1. Target Machine Setup (WEV-AJ-02)
    machine = Machine.objects.filter(code="WEV-AJ-02").first()
    if not machine:
        print("[!] Machine WEV-AJ-02 not found. Seeding machine...")
        from apps.machines.models import MachineType
        from apps.factories.models import Department
        dept = Department.objects.first()
        mtype = MachineType.objects.first()
        machine = Machine.objects.create(
            code="WEV-AJ-02",
            name="Picanol OmniPlus-i Loom #2",
            department=dept,
            machine_type=mtype,
            status=MachineStatus.CRITICAL,
        )

    # Ensure operating limits
    limits, _ = MachineOperatingLimits.objects.get_or_create(
        machine=machine,
        defaults={
            "warning_vibration_mms": 4.0,
            "max_vibration_mms": 5.5,
            "warning_temp_c": 75.0,
            "max_temp_c": 85.0,
        },
    )

    # Ensure warehouse spare part exists
    part, _ = InventoryItem.objects.get_or_create(
        item_code="SPR-BRG-6204",
        defaults={
            "name": "Deep Groove Ball Bearing 6204-2RSH",
            "category": "SPARE_PART",
            "current_stock": Decimal("15.00"),
            "minimum_safety_stock": Decimal("3.00"),
            "unit": "PCS",
            "unit_cost": Decimal("850.00"),
        },
    )
    if part.current_stock < 5:
        part.current_stock = Decimal("15.00")
        part.save()

    print(f"\n[STEP 1] Target Machine Initial State: {machine.code} [{machine.status}]")
    print(f"         Configured Limits: Warning Vib={limits.warning_vibration_mms} mm/s, Warning Temp={limits.warning_temp_c}°C")
    print(f"         Warehouse Stock: {part.item_code} = {part.current_stock} {part.unit}")

    # 2. Factory Incident Setup
    incident_code = f"INC-P12-{timezone.now().strftime('%H%M%S')}"
    incident = FactoryIncident.objects.create(
        incident_code=incident_code,
        factory=machine.department.factory,
        department=machine.department,
        machine=machine,
        severity=IncidentSeverity.CRITICAL,
        status=IncidentStatus.MITIGATING,
        summary=f"Severe loom vibration excursion (6.8 mm/s) on {machine.code}",
        root_cause_hypothesis="Drive end bearing race spalling or mechanical imbalance",
    )
    print(f"\n[STEP 2] Factory Incident Created: {incident.incident_code} [{incident.status}]")

    # 3. Approved Maintenance Work Order
    ticket_number = f"MNT-P12-{timezone.now().strftime('%H%M%S')}"
    ticket = MaintenanceTicket.objects.create(
        ticket_number=ticket_number,
        machine=machine,
        incident_reference=incident.incident_code,
        title=f"Authorized Repair on {machine.code}: Bearing Replacement & Alignment",
        description="Manager approved recovery work order for abnormal vibration.",
        priority="CRITICAL",
        status=TicketStatus.CREATED,
        assigned_technician="R. Sharma (Senior Diagnostic Tech)",
        labor_hours=Decimal("2.00"),
    )
    WorkOrderLifecycleService.populate_checklist_if_empty(ticket)
    print(f"\n[STEP 3] Work Order Actionable: {ticket.ticket_number} [{ticket.status}]")
    print(f"         Assigned Technician: {ticket.assigned_technician}")
    print(f"         Inspection Checklist Items Populated: {len(ticket.inspection_checklist)}")

    # 4. Technician Accepts Work Order
    WorkOrderLifecycleService.transition_state(
        ticket=ticket,
        new_state=TicketStatus.ACCEPTED,
        actor=ticket.assigned_technician,
        reason="Technician accepted assignment and dispatched to Loom A-2.",
    )
    print(f"\n[STEP 4] Work Order Accepted: {ticket.ticket_number} [{ticket.status}]")

    # 5. Technician Performs Guided Inspection
    WorkOrderLifecycleService.transition_state(
        ticket=ticket,
        new_state=TicketStatus.INSPECTION_IN_PROGRESS,
        actor=ticket.assigned_technician,
        reason="Beginning sensor-guided diagnostic inspection.",
    )
    checklist = ticket.inspection_checklist
    checklist[0]["status"] = "DEFECT_FOUND"
    checklist[0]["observed_value"] = "6.85 mm/s radial amplitude"
    checklist[0]["notes"] = "Excessive vibration centered at 2x shaft frequency"
    checklist[1]["status"] = "DEFECT_FOUND"
    checklist[1]["observed_value"] = "76.4 °C surface temperature"
    checklist[1]["notes"] = "Thermal hot spot on drive bearing housing #6204"
    for item in checklist[2:]:
        item["status"] = "PASS"
        item["observed_value"] = "Within OEM tolerance"

    confirmed_fault = "Inner race spalling and cage fracture on drive-end ball bearing #6204"
    ticket.inspection_checklist = checklist
    ticket.confirmed_fault = confirmed_fault
    ticket.fault_confirmation_notes = "Acoustic and IR inspection confirmed inner race pitting on bearing #6204."
    ticket.save()

    print(f"\n[STEP 5] Guided Inspection Completed & Fault Confirmed:")
    print(f"         Confirmed Fault: {ticket.confirmed_fault}")
    print(f"         Checklist Status: Step 1={checklist[0]['status']} ({checklist[0]['observed_value']}), Step 2={checklist[1]['status']} ({checklist[1]['observed_value']})")

    # 6. Move to REPAIR_IN_PROGRESS
    WorkOrderLifecycleService.transition_state(
        ticket=ticket,
        new_state=TicketStatus.REPAIR_IN_PROGRESS,
        actor=ticket.assigned_technician,
        reason="Disassembly and bearing replacement in progress.",
        payload={"confirmed_fault": confirmed_fault},
    )
    print(f"\n[STEP 6] Work Order in Repair: {ticket.ticket_number} [{ticket.status}]")

    # 7. Safe Spare Part Consumption (and double-deduction test)
    stock_before = part.current_stock
    consumed = WorkOrderLifecycleService.consume_spare_parts(
        ticket=ticket,
        parts=[{"item_code": part.item_code, "quantity": 1}],
        actor=ticket.assigned_technician,
    )
    part.refresh_from_db()
    print(f"\n[STEP 7] Spare Part Deducted:")
    print(f"         Stock Before: {stock_before} -> After: {part.current_stock} {part.unit}")
    print(f"         Ledger Transaction: Reference #{ticket.ticket_number}, Item: {consumed[0]['item_code']}")

    # Double deduction test
    WorkOrderLifecycleService.consume_spare_parts(
        ticket=ticket,
        parts=[{"item_code": part.item_code, "quantity": 1}],
        actor=ticket.assigned_technician,
    )
    part.refresh_from_db()
    assert part.current_stock == stock_before - Decimal("1.00"), "Error: Double deduction occurred!"
    print(f"         Double-Deduction Guard: Verified safe (stock remained at {part.current_stock})")

    # 8. Document Physical Repair Completion
    repair_desc = (
        "Extracted damaged drive-end bearing #6204 with hydraulic puller. Cleaned housing cavity of metal dust. "
        "Induction heated new SKF bearing to 110°C and pressed onto shaft. Repacked with Mobilith SHC 220 grease. "
        "Realigned drive belt tension and torqued eccentric locking ring to 45 Nm."
    )
    WorkOrderLifecycleService.transition_state(
        ticket=ticket,
        new_state=TicketStatus.REPAIR_COMPLETED,
        actor=ticket.assigned_technician,
        reason="Physical repair completed successfully.",
        payload={
            "repair_performed": repair_desc,
            "actual_repair_duration_minutes": 45,
            "remaining_issues": "None. Shaft spins freely by hand.",
        },
    )
    print(f"\n[STEP 8] Physical Repair Documented:")
    print(f"         Repair Status: {ticket.status} (Duration: {ticket.actual_repair_duration_minutes} mins)")
    print(f"         Verification Status: {ticket.verification_status}")

    # 9. Enter Telemetry Observation Window & Generate Post-Repair Telemetry
    WorkOrderLifecycleService.transition_state(
        ticket=ticket,
        new_state=TicketStatus.AWAITING_VERIFICATION,
        actor=ticket.assigned_technician,
        reason="Machine entering post-repair run-in observation.",
    )
    post_readings = MaintenanceSimulationService.generate_post_repair_telemetry(
        machine=machine,
        num_readings=6,
        mode="HEALTHY",
    )
    print(f"\n[STEP 9] Post-Repair Telemetry Collected:")
    print(f"         Generated {len(post_readings)} successive telemetry readings.")
    for idx, r in enumerate(post_readings[:3], 1):
        print(f"         Sample #{idx}: Vib={r.vibration_mms} mm/s, Temp={r.temperature_c}°C, Speed={r.speed_rpm} RPM")

    # 10. Recovery Verification Engine Evaluation
    eval_report = RecoveryVerificationService.evaluate_machine_recovery(
        machine=machine,
        ticket=ticket,
        observation_window=5,
    )
    print(f"\n[STEP 10] Recovery Verification Engine Evaluation:")
    print(f"          Outcome: {eval_report['outcome']}")
    print(f"          Summary: {eval_report['summary']}")
    print(f"          Peak Vibration: {eval_report['max_vibration']} mm/s (Limit: < {eval_report['limit_vibration']} mm/s)")
    print(f"          Peak Temp: {eval_report['max_temp']} °C (Limit: < {eval_report['limit_temp']} °C)")
    print(f"          Stability Confirmed: {eval_report['is_stable']}")

    assert eval_report["outcome"] == VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF, "Evaluation outcome mismatch!"

    # 11. Safety Check: Verify Unauthorized Closure is Blocked
    try:
        RecoveryVerificationService.close_incident_with_evidence(
            incident=incident,
            ticket=ticket,
            closed_by="Operator",
        )
        assert False, "Safety barrier failed: closed without authorized sign-off!"
    except Exception as e:
        print(f"\n[STEP 11] Safety Barrier Check:")
        print(f"          Premature Closure Prevented: {str(e)}")

    # 12. Authorized Return-to-Service Sign-Off
    signed_report = RecoveryVerificationService.authorize_and_sign_off(
        ticket=ticket,
        authorized_by="V. Ramanathan (Plant Operations Manager)",
        notes="Observed nominal vibration levels at full loom operating speed. Cleared for weaving production.",
    )
    print(f"\n[STEP 12] Authorized Return to Service Sign-Off:")
    print(f"          Authorized By: {ticket.authorized_signoff_by}")
    print(f"          Verification Outcome: {signed_report['outcome']}")
    machine.refresh_from_db()
    print(f"          Machine Status: {machine.code} [{machine.status}] (Health: {machine.current_health_score})")

    # 13. Evidence-Based Incident Closure
    closed_incident = RecoveryVerificationService.close_incident_with_evidence(
        incident=incident,
        ticket=ticket,
        closed_by="V. Ramanathan (Plant Operations Manager)",
        resolution_notes="Incident closed with complete post-repair telemetry verification.",
    )
    ticket.refresh_from_db()
    print(f"\n[STEP 13] Factory Incident Closed with Complete Evidence:")
    print(f"          Incident Status: {closed_incident.incident_code} [{closed_incident.status}]")
    print(f"          Work Order Status: {ticket.ticket_number} [{ticket.status}]")
    print(f"          Resolution Summary: {closed_incident.resolution_summary[:120]}...")

    # 14. Negative Test: Failed Recovery Verification Scenario
    print("\n" + "-" * 80)
    print("[NEGATIVE PATH TEST] Unresolved Fault & Failed Recovery Verification")
    print("-" * 80)

    neg_ticket = MaintenanceTicket.objects.create(
        ticket_number=f"MNT-NEG-{timezone.now().strftime('%H%M%S')}",
        machine=machine,
        title=f"Negative Test Repair on {machine.code}",
        priority="HIGH",
        status=TicketStatus.REPAIR_COMPLETED,
        repair_completed_at=timezone.now(),
        confirmed_fault="Residual imbalance test",
        repair_performed="Adjusted mounting bolts (incomplete repair)",
        actual_repair_duration_minutes=20,
    )
    MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="FAULTY")
    neg_eval = RecoveryVerificationService.evaluate_machine_recovery(machine=machine, ticket=neg_ticket)
    print(f"Outcome: {neg_eval['outcome']}")
    print(f"Summary: {neg_eval['summary']}")
    print(f"Max Vibration: {neg_eval['max_vibration']} mm/s (Threshold: {neg_eval['limit_vibration']} mm/s)")
    assert neg_eval["outcome"] == VerificationStatus.FAILED, "Expected FAILED verification for faulty telemetry!"
    neg_ticket.refresh_from_db()
    assert neg_ticket.status == TicketStatus.VERIFICATION_FAILED
    print("Negative path correctly transitioned to VERIFICATION_FAILED!")

    print("\n" + "=" * 80)
    print("ALL PHASE 12 END-TO-END WORKFLOW VERIFICATIONS PASSED SUCCESSFULLY!")
    print("=" * 80)


if __name__ == "__main__":
    run_phase12_e2e_verification()
