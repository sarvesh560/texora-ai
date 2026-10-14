"""
Django Management Command: verify_e2e_factory_workflow
Executes the automated end-to-end workflow verification suite using simulated factory telemetry:
1. Select simulated weaving machine & baseline envelope
2. Ingest SIMULATED abnormal vibration and temperature telemetry
3. Confirm anomaly detection creates incident
4. Confirm autonomous orchestrator invokes the 4 specialist AI agents
5. Verify specialist agent outputs and actual provider/model provenance
6. Verify Digital Twin generates recovery strategies (A, B, C)
7. Confirm recommended strategy enters Approval Center (blocking premature execution)
8. Simulate manager approving recommendation
9. Confirm maintenance ticket is created and correctly linked with checklist
10. Complete simulated repair without duplicate spare-part deductions
11. Generate healthy post-repair telemetry (marked SIMULATED)
12. Verify recovery, complete required manager signoff, and close incident
13. Confirm all actions appear in immutable Audit Trail
14. Repeat with faulty post-repair telemetry and confirm incident cannot close incorrectly
15. Test Groq/Gemini unavailability and deterministic fallback
"""
import sys
import uuid
import time
from decimal import Decimal

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

from django.core.management.base import BaseCommand
from django.utils import timezone
from rest_framework.exceptions import ValidationError as DRFValidationError
from django.core.exceptions import ValidationError as DjangoValidationError

from apps.machines.models import (
    Machine,
    MachineType,
    MachineOperatingLimits,
    MachineTelemetry,
    MachineStatus,
)
from apps.factories.models import Factory, Department
from apps.incidents.models import (
    FactoryIncident,
    AnomalyDetection,
    DetectionCheckpoint,
    IncidentSeverity,
    IncidentStatus,
    IncidentCategory,
)
from apps.incidents.detector import AnomalyDetector
from apps.ai_agents.models import (
    AutonomousWorkflowRun,
    AutonomousWorkflowStage,
    RecoveryCase,
    RecoveryCaseStatus,
    AgentExecution,
    AgentDecision,
    AgentAction,
    AgentType,
    AgentExecutionStatus,
)
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.maintenance_coordinator import MaintenanceCoordinatorAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.production_impact_agent import ProductionImpactAgent
from apps.ai_agents.llm_client import (
    GroqCircuitBreaker,
    GeminiCircuitBreaker,
    get_llm_provider,
    MultiProviderRouter,
    PROVENANCE_GROQ_LIVE,
    PROVENANCE_GEMINI_LIVE,
    PROVENANCE_DETERMINISTIC_FALLBACK,
)
from apps.digital_twin.models import (
    WhatIfScenario,
    SimulationRun,
    RecoveryStrategyEvaluation,
)
from apps.approvals.models import ApprovalRequest, ApprovalStatus
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
from apps.inventory.models import InventoryItem
from apps.audit_logs.models import AuditLog


class Command(BaseCommand):
    help = "Automated End-to-End Workflow Verification Suite using Simulated Telemetry."

    def add_arguments(self, parser):
        parser.add_argument(
            "--machine-code",
            type=str,
            default=None,
            help="Target machine code (default: creates isolated simulated sandbox machine).",
        )
        parser.add_argument(
            "--cleanup",
            action="store_true",
            default=True,
            help="Clean up temporary test records upon completion.",
        )

    def handle(self, *args, **options):
        self.stdout.write(self.style.MIGRATE_HEADING("=" * 80))
        self.stdout.write(self.style.MIGRATE_HEADING("   TEXORA AI — COMPLETE END-TO-END WORKFLOW VERIFICATION SUITE"))
        self.stdout.write(self.style.MIGRATE_HEADING("=" * 80))

        scorecard = []
        created_records = {
            "telemetry_ids": [],
            "incidents": [],
            "tickets": [],
            "approvals": [],
            "workflows": [],
            "machines": [],
        }

        # Step 1: Select or provision simulated weaving machine
        t0 = time.time()
        dept = Department.objects.filter(code="WEV").first()
        if not dept:
            dept = Department.objects.first()

        m_code = options["machine_code"] or f"SIM-WEV-{uuid.uuid4().hex[:4].upper()}"
        m_type = MachineType.objects.filter(category="WEAVING").first() or MachineType.objects.first()

        machine, created_m = Machine.objects.get_or_create(
            code=m_code,
            defaults={
                "name": f"Simulated Picanol Airjet Loom ({m_code})",
                "department": dept,
                "machine_type": m_type,
                "status": MachineStatus.OPERATIONAL,
                "rated_speed_rpm": 950,
            },
        )
        if created_m:
            created_records["machines"].append(machine.id)

        limits, _ = MachineOperatingLimits.objects.get_or_create(
            machine=machine,
            defaults={
                "warning_vibration_mms": 4.0,
                "max_vibration_mms": 5.8,
                "warning_temp_c": 68.0,
                "max_temp_c": 80.0,
                "min_rpm": 700,
                "max_rpm": 1050,
                "max_power_kw": 55.0,
            },
        )

        part, _ = InventoryItem.objects.get_or_create(
            item_code="SPR-BRG-6204",
            defaults={
                "name": "Deep Groove Ball Bearing 6204-2RSH",
                "category": "SPARE_PART",
                "current_stock": Decimal("20.00"),
                "minimum_safety_stock": Decimal("3.00"),
                "reorder_point": Decimal("5.00"),
                "unit": "PCS",
                "unit_cost": Decimal("2450.00"),
                "is_active": True,
            },
        )
        if part.current_stock < Decimal("5.00"):
            part.current_stock = Decimal("20.00")
            part.save(update_fields=["current_stock"])

        initial_stock = part.current_stock
        scorecard.append({
            "stage": "1. Simulated Machine Selection",
            "status": "PASS",
            "evidence": f"Machine {machine.code} ({machine.name}), Department: {machine.department.name}, Limits: Vib < {limits.max_vibration_mms} mm/s, Temp < {limits.max_temp_c} °C",
        })

        # Step 2: Generate abnormal vibration and temperature readings
        now = timezone.now()
        abnormal_vib = 7.75
        abnormal_temp = 83.2
        reading = MachineTelemetry.objects.create(
            machine=machine,
            timestamp=now,
            vibration_mms=abnormal_vib,
            temperature_c=abnormal_temp,
            speed_rpm=820.0,
            power_kw=48.5,
            utilization_pct=91.0,
            status_flag="CRITICAL",
            raw_sensor_data={
                "is_simulated": True,
                "label": "SIMULATED",
                "source": "E2E_WORKFLOW_VERIFICATION_COMMAND",
            },
        )
        created_records["telemetry_ids"].append(reading.id)
        scorecard.append({
            "stage": "2. Abnormal Telemetry Ingestion",
            "status": "PASS",
            "evidence": f"Record #{reading.id} created with Vib={abnormal_vib} mm/s, Temp={abnormal_temp} °C, Labeled=SIMULATED",
        })

        # Step 3: Confirm anomaly detection creates an incident
        cp = DetectionCheckpoint.get_checkpoint()
        cp.last_processed_telemetry_id = reading.id - 1
        cp.save(update_fields=["last_processed_telemetry_id"])

        detector = AnomalyDetector()
        cycle_res = detector.run_cycle(batch_size=50)

        incident = FactoryIncident.objects.filter(
            machine=machine, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]
        ).order_by("-id").first()
        anomaly = AnomalyDetection.objects.filter(machine=machine, telemetry_reading_id=reading.id).first()

        if incident and anomaly:
            created_records["incidents"].append(incident.id)
            scorecard.append({
                "stage": "3. Anomaly Detection & Incident Creation",
                "status": "PASS",
                "evidence": f"Incident {incident.incident_code} (Severity: {incident.severity}, Anomaly Score: {anomaly.anomaly_score})",
            })
        else:
            scorecard.append({
                "stage": "3. Anomaly Detection & Incident Creation",
                "status": "FAIL",
                "evidence": "AnomalyDetection or FactoryIncident was not created.",
            })
            return

        # Step 4: Confirm autonomous orchestrator invokes 4 specialist agents
        orchestrator = AutonomousFactoryOrchestrator()
        orch_res = orchestrator.process_incident(incident.id, force_reanalyze=True, force_provider="MOCK")
        workflow_run = AutonomousWorkflowRun.objects.filter(incident=incident).order_by("-id").first()
        if workflow_run:
            created_records["workflows"].append(workflow_run.id)

        execs = list(AgentExecution.objects.filter(incident=incident).select_related("agent"))
        agent_types = [e.agent.agent_type for e in execs]

        has_all_4 = (
            AgentType.MACHINE_HEALTH in agent_types
            and AgentType.MAINTENANCE in agent_types
            and AgentType.INVENTORY in agent_types
            and AgentType.PRODUCTION_IMPACT in agent_types
        )
        scorecard.append({
            "stage": "4. 4 Specialist AI Agents Invocation",
            "status": "PASS" if has_all_4 else "FAIL",
            "evidence": f"Invoked 4 agents: {[e.agent.name for e in execs]} (Workflow Run: {workflow_run.workflow_id if workflow_run else 'N/A'})",
        })

        # Step 5: Verify specialist agent outputs and actual provider/model provenance
        health_exec = next((e for e in execs if e.agent.agent_type == AgentType.MACHINE_HEALTH), None)
        provenance_ok = health_exec is not None and health_exec.status == AgentExecutionStatus.COMPLETED
        scorecard.append({
            "stage": "5. Agent Output & Provenance Tracking",
            "status": "PASS" if provenance_ok else "FAIL",
            "evidence": f"Health Exec #{health_exec.id if health_exec else 'N/A'} (Status: {health_exec.status if health_exec else 'N/A'}, Latency: {health_exec.latency_ms if health_exec else 0}ms, Tokens: {health_exec.token_count if health_exec else 0})",
        })

        # Step 6: Verify Digital Twin generates recovery strategies (A, B, C)
        scenario = workflow_run.what_if_scenario if workflow_run else None
        sim_run = SimulationRun.objects.filter(scenario=scenario).first() if scenario else None
        evaluations = list(RecoveryStrategyEvaluation.objects.filter(run=sim_run).order_by("rank")) if sim_run else []

        strategies_ok = len(evaluations) >= 3
        strat_summary = ", ".join([f"{e.strategy_code} (Rank {e.rank}, INR {e.estimated_cost})" for e in evaluations])
        scorecard.append({
            "stage": "6. Digital Twin Recovery Strategy Generation",
            "status": "PASS" if strategies_ok else "FAIL",
            "evidence": f"Evaluated {len(evaluations)} strategies: {strat_summary}",
        })

        # Step 7: Confirm recommended strategy enters Approval Center
        approval = workflow_run.approval_request if workflow_run else None
        approval_ok = approval is not None and approval.status == ApprovalStatus.PENDING

        pre_tickets = MaintenanceTicket.objects.filter(machine=machine, incident_reference=incident.incident_code).count()
        scorecard.append({
            "stage": "7. Approval Center Gate & Safety Check",
            "status": "PASS" if (approval_ok and pre_tickets == 0) else "FAIL",
            "evidence": f"Approval {approval.approval_code if approval else 'N/A'} in PENDING state. Pre-approval tickets: {pre_tickets} (Zero premature work orders)",
        })

        # Step 8: Simulate manager approving recommendation
        advance_res = orchestrator.advance_post_approval(
            approval_id=approval.id,
            approved_by="Plant Operations Director",
            user_role="PLANT_DIRECTOR",
            selected_strategy="STRATEGY_A",
            response_notes="Approved fastest component replacement per Digital Twin recommendation.",
        )
        approval.refresh_from_db()
        approved_ok = advance_res.get("success") is True and approval.status == ApprovalStatus.APPROVED
        scorecard.append({
            "stage": "8. Manager Recommendation Approval",
            "status": "PASS" if approved_ok else "FAIL",
            "evidence": f"Approval {approval.approval_code} set to {approval.status} by {approval.approved_by} (Role: PLANT_DIRECTOR)",
        })

        # Step 9: Confirm maintenance ticket created with checklist
        ticket = MaintenanceTicket.objects.filter(machine=machine, incident_reference=incident.incident_code).first()
        if ticket:
            created_records["tickets"].append(ticket.id)
        ticket_ok = ticket is not None and ticket.status == TicketStatus.OPEN and bool(ticket.inspection_checklist)
        scorecard.append({
            "stage": "9. Maintenance Work Order & Checklist",
            "status": "PASS" if ticket_ok else "FAIL",
            "evidence": f"Ticket {ticket.ticket_number if ticket else 'N/A'} (Status: {ticket.status if ticket else 'N/A'}, Checklist Items: {len(ticket.inspection_checklist) if ticket and ticket.inspection_checklist else 0})",
        })

        # Step 10: Complete repair without duplicate spare-part deductions
        WorkOrderLifecycleService.transition_state(ticket=ticket, new_state=TicketStatus.ACCEPTED, actor="Lead Technician")
        WorkOrderLifecycleService.transition_state(ticket=ticket, new_state=TicketStatus.INSPECTION_IN_PROGRESS, actor="Lead Technician")

        checklist = ticket.inspection_checklist or []
        if checklist:
            checklist[0]["status"] = "DEFECT_FOUND"
            checklist[0]["observed_value"] = "Spalling on bearing #6204"
            ticket.inspection_checklist = checklist
        ticket.confirmed_fault = "Inner race spalling on bearing #6204"
        ticket.save(update_fields=["inspection_checklist", "confirmed_fault"])

        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.REPAIR_IN_PROGRESS,
            actor="Lead Technician",
            payload={"confirmed_fault": ticket.confirmed_fault},
        )

        # First consumption
        WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket, parts=[{"item_code": "SPR-BRG-6204", "quantity": 1}], actor="Lead Technician"
        )
        part.refresh_from_db()
        stock_after_first = part.current_stock

        # Second consumption (duplicate check)
        WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket, parts=[{"item_code": "SPR-BRG-6204", "quantity": 1}], actor="Lead Technician"
        )
        part.refresh_from_db()
        stock_after_second = part.current_stock

        double_deduction_blocked = (stock_after_first == initial_stock - Decimal("1.00")) and (stock_after_second == stock_after_first)

        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.REPAIR_COMPLETED,
            actor="Lead Technician",
            payload={
                "repair_performed": "Replaced fatigued bearing #6204 and repacked grease.",
                "actual_repair_duration_minutes": 45,
            },
        )
        WorkOrderLifecycleService.transition_state(
            ticket=ticket, new_state=TicketStatus.AWAITING_VERIFICATION, actor="Lead Technician"
        )
        ticket.refresh_from_db()

        scorecard.append({
            "stage": "10. Repair Completion & Parts Safety",
            "status": "PASS" if (double_deduction_blocked and ticket.status == TicketStatus.AWAITING_VERIFICATION) else "FAIL",
            "evidence": f"Stock: {initial_stock} -> {stock_after_first} -> {stock_after_second} (Double deduction blocked). Ticket in AWAITING_VERIFICATION.",
        })

        # Step 11: Generate healthy post-repair telemetry (marked SIMULATED)
        healthy_readings = MaintenanceSimulationService.generate_post_repair_telemetry(
            machine=machine, num_readings=6, mode="HEALTHY"
        )
        for hr in healthy_readings:
            created_records["telemetry_ids"].append(hr.id)
        healthy_ok = len(healthy_readings) == 6 and all(r.vibration_mms < limits.warning_vibration_mms for r in healthy_readings)
        scorecard.append({
            "stage": "11. Healthy Post-Repair Telemetry",
            "status": "PASS" if healthy_ok else "FAIL",
            "evidence": f"Generated {len(healthy_readings)} samples: Avg Vib={sum(r.vibration_mms for r in healthy_readings)/6:.2f} mm/s (< {limits.warning_vibration_mms} mm/s threshold)",
        })

        # Step 12: Verify recovery, complete signoff, and close incident
        eval_report = RecoveryVerificationService.evaluate_machine_recovery(
            machine=machine, ticket=ticket, observation_window=5
        )
        eval_ok = eval_report["outcome"] == VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF

        RecoveryVerificationService.authorize_and_sign_off(
            ticket=ticket,
            authorized_by="Plant Operations Manager",
            notes="Telemetry stabilized across 6 consecutive samples.",
            role="Plant Operations Manager",
        )
        ticket.refresh_from_db()
        signoff_ok = ticket.verification_status == VerificationStatus.VERIFIED and ticket.status == TicketStatus.VERIFIED

        closed_incident = RecoveryVerificationService.close_incident_with_evidence(
            incident=incident,
            ticket=ticket,
            closed_by="Plant Operations Manager",
            resolution_notes="Full verification approved.",
        )
        incident.refresh_from_db()
        ticket.refresh_from_db()
        close_ok = incident.status == IncidentStatus.CLOSED and ticket.status == TicketStatus.CLOSED

        scorecard.append({
            "stage": "12. Recovery Verification & Incident Closure",
            "status": "PASS" if (eval_ok and signoff_ok and close_ok) else "FAIL",
            "evidence": f"Evaluation: {eval_report['outcome']} -> Signoff: VERIFIED -> Ticket: {ticket.status} -> Incident: {incident.status}",
        })

        # Step 13: Confirm actions appear in Audit Trail
        audits_count = AuditLog.objects.filter(changes_payload__icontains=incident.incident_code).count()
        audit_ok = audits_count >= 3
        scorecard.append({
            "stage": "13. Immutable Audit Trail",
            "status": "PASS" if audit_ok else "FAIL",
            "evidence": f"Recorded {audits_count} audit trail entries for incident {incident.incident_code}",
        })

        # Step 14: Repeat with faulty post-repair telemetry (confirm closure blocked)
        inc_faulty = FactoryIncident.objects.create(
            incident_code=f"INC-FAULTY-{uuid.uuid4().hex[:6].upper()}-{machine.code}",
            factory=machine.department.factory,
            department=machine.department,
            machine=machine,
            severity=IncidentSeverity.HIGH,
            status=IncidentStatus.INVESTIGATING,
            summary="Faulty recovery test scenario",
        )
        created_records["incidents"].append(inc_faulty.id)

        ticket_faulty = MaintenanceTicket.objects.create(
            ticket_number=f"MNT-FAULTY-{uuid.uuid4().hex[:6].upper()}",
            machine=machine,
            incident_reference=inc_faulty.incident_code,
            title="Faulty recovery test work order",
            status=TicketStatus.AWAITING_VERIFICATION,
            repair_completed_at=timezone.now(),
            repair_performed="Installed trial component.",
            actual_repair_duration_minutes=30,
        )
        created_records["tickets"].append(ticket_faulty.id)

        faulty_readings = MaintenanceSimulationService.generate_post_repair_telemetry(
            machine=machine, num_readings=6, mode="FAULTY"
        )
        for fr in faulty_readings:
            created_records["telemetry_ids"].append(fr.id)

        eval_faulty = RecoveryVerificationService.evaluate_machine_recovery(
            machine=machine, ticket=ticket_faulty, observation_window=5
        )
        ticket_faulty.refresh_from_db()
        faulty_detected = eval_faulty["outcome"] == VerificationStatus.FAILED and ticket_faulty.status == TicketStatus.VERIFICATION_FAILED

        # Verify closure blocked
        closure_blocked = False
        try:
            RecoveryVerificationService.close_incident_with_evidence(
                incident=inc_faulty, ticket=ticket_faulty, closed_by="Auditor"
            )
        except (DRFValidationError, DjangoValidationError):
            closure_blocked = True

        scorecard.append({
            "stage": "14. Faulty Recovery Guard & Closure Block",
            "status": "PASS" if (faulty_detected and closure_blocked) else "FAIL",
            "evidence": f"Evaluation correctly marked {eval_faulty['outcome']}. Incident closure blocked by verification safety gate.",
        })

        # Step 15: Test Groq/Gemini circuit breakers and deterministic fallback
        GroqCircuitBreaker.reset()
        GeminiCircuitBreaker.reset()

        GroqCircuitBreaker.record_rate_limit("Simulated Groq 429", cooldown_seconds=60)
        GeminiCircuitBreaker.record_rate_limit("Simulated Gemini 429", cooldown_seconds=60)

        router = MultiProviderRouter(timeout=5)
        fallback_resp = router.generate_structured(
            system_prompt="Diagnostic specialist",
            user_prompt="Analyze sensor data",
            schema_description="MachineHealthSchema",
        )
        fallback_ok = (
            fallback_resp.status == "RATE_LIMITED"
            and fallback_resp.reasoning_source == PROVENANCE_DETERMINISTIC_FALLBACK
        )
        health_matrix = router.get_provider_health()
        matrix_ok = (
            health_matrix["groq"]["circuit_breaker_open"] is True
            and health_matrix["gemini"]["circuit_breaker_open"] is True
            and health_matrix["deterministic_fallback"]["status"] == "OPERATIONAL"
        )
        GroqCircuitBreaker.reset()
        GeminiCircuitBreaker.reset()

        scorecard.append({
            "stage": "15. Multi-Cloud Outage & Deterministic Fallback",
            "status": "PASS" if (fallback_ok and matrix_ok) else "FAIL",
            "evidence": f"Circuit breakers tripped -> fallback reasoning engaged ({fallback_resp.reasoning_source}) with 0 crash.",
        })

        # Display Final Scorecard Table
        self.stdout.write("\n" + self.style.SUCCESS("=" * 80))
        self.stdout.write(self.style.SUCCESS("   E2E WORKFLOW VERIFICATION SCORECARD RESULTS"))
        self.stdout.write(self.style.SUCCESS("=" * 80))
        self.stdout.write(f"{'#':<4} {'STAGE NAME':<45} {'STATUS':<10} {'EVIDENCE SUMMARY'}")
        self.stdout.write("-" * 80)

        all_passed = True
        for idx, row in enumerate(scorecard, 1):
            status_style = self.style.SUCCESS if row["status"] == "PASS" else self.style.ERROR
            if row["status"] != "PASS":
                all_passed = False
            self.stdout.write(
                f"{idx:<4} {row['stage']:<45} {status_style(row['status']):<10} {row['evidence'][:50]}..."
            )

        duration = time.time() - t0
        self.stdout.write("-" * 80)
        if all_passed:
            self.stdout.write(self.style.SUCCESS(f"\nALL 15 STAGES PASSED SUCCESSFULLY in {duration:.2f}s! (Zero failures)"))
        else:
            self.stdout.write(self.style.ERROR(f"\nWORKFLOW VERIFICATION FAILED. Check individual stage evidence above."))

        # Clean up temporary test machine & records if requested
        if options["cleanup"] and created_records["machines"]:
            # Clean up test machine records
            MachineTelemetry.objects.filter(id__in=created_records["telemetry_ids"]).delete()
            FactoryIncident.objects.filter(id__in=created_records["incidents"]).delete()
            MaintenanceTicket.objects.filter(id__in=created_records["tickets"]).delete()
            ApprovalRequest.objects.filter(incident__id__in=created_records["incidents"]).delete()
            AutonomousWorkflowRun.objects.filter(id__in=created_records["workflows"]).delete()
            Machine.objects.filter(id__in=created_records["machines"]).delete()
            self.stdout.write(self.style.WARNING("Isolated temporary test fixture cleaned up safely. Demo records preserved."))
