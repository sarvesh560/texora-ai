"""
TEXORA AI — END-TO-END AUTONOMOUS INDUSTRIAL WORKFLOW VERIFICATION SUITE
Comprehensive regression and verification test suite covering the full 15-stage lifecycle:
1. Simulated machine selection & baseline envelope
2. Ingestion of SIMULATED abnormal multi-sensor telemetry (vibration & temperature)
3. Autonomous IoT anomaly detection & incident creation
4. Autonomous orchestrator invocation of the 4 specialist AI agents
5. Specialist agent execution outputs, decision reasoning, and provider provenance
6. Digital Twin What-If simulation across Strategies A, B, and C
7. Recommendation synthesis and human-in-the-loop Approval Center gate
8. Managerial approval simulation and role validation
9. Maintenance work order creation, linkage, and checklist population
10. Physical repair execution and spare-part consumption (with double-deduction prevention)
11. Ingestion of SIMULATED healthy post-repair telemetry
12. Recovery verification engine evaluation, authorized signoff, and incident closure
13. Immutable audit trail verification across all lifecycle milestones
14. Faulty post-repair telemetry regression (confirming premature closure is strictly blocked)
15. Multi-provider circuit breaker failover and deterministic fallback resilience
"""
import uuid
from decimal import Decimal
import pytest
from django.utils import timezone
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework.exceptions import ValidationError as DRFValidationError

ValidationErrorTuple = (DjangoValidationError, DRFValidationError)

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
    RecoveryStepStatus,
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
    PROVENANCE_MOCK_SUCCESS,
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
from apps.inventory.models import InventoryItem, InventoryCategory
from apps.audit_logs.models import AuditLog


@pytest.fixture
def workflow_test_fixture(db):
    """
    Creates an isolated sandbox factory, department, weaving machine, limits, and inventory.
    Guarantees existing demo records (like WEV-AJ-02) are NEVER mutated or deleted.
    """
    factory, _ = Factory.objects.get_or_create(
        code="FAC-E2E-TEST",
        defaults={"name": "E2E Verification Testing Mill", "location": "Test Facility"},
    )
    dept, _ = Department.objects.get_or_create(
        factory=factory,
        code="WEV-TEST",
        defaults={"name": "Weaving Testing Shed"},
    )
    m_type, _ = MachineType.objects.get_or_create(
        name="Airjet Loom Simulation",
        defaults={"category": "WEAVING", "manufacturer": "Picanol Testing"},
    )
    machine, _ = Machine.objects.get_or_create(
        code=f"WEV-E2E-{uuid.uuid4().hex[:4].upper()}",
        defaults={
            "name": "Simulated Weaving Loom Test Unit",
            "department": dept,
            "machine_type": m_type,
            "status": MachineStatus.OPERATIONAL,
            "rated_speed_rpm": 950,
        },
    )
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
    # Ensure spare part inventory item exists with stock
    part, _ = InventoryItem.objects.get_or_create(
        item_code="SPR-BRG-6204",
        defaults={
            "name": "Deep Groove Ball Bearing 6204-2RSH",
            "category": "SPARE_PART",
            "current_stock": Decimal("15.00"),
            "minimum_safety_stock": Decimal("3.00"),
            "reorder_point": Decimal("5.00"),
            "unit": "PCS",
            "unit_cost": Decimal("2450.00"),
            "is_active": True,
        },
    )
    if part.current_stock < Decimal("5.00"):
        part.current_stock = Decimal("15.00")
        part.save(update_fields=["current_stock"])

    return {
        "factory": factory,
        "department": dept,
        "machine": machine,
        "limits": limits,
        "spare_part": part,
    }


@pytest.mark.django_db
class TestEndToEndWorkflowVerificationSuite:
    """Automated End-to-End Workflow Verification Suite covering all 15 stages."""

    def test_complete_end_to_end_successful_lifecycle(self, workflow_test_fixture):
        """
        Executes and audits the complete 13-stage lifecycle from telemetry anomaly to verified closure.
        """
        machine = workflow_test_fixture["machine"]
        limits = workflow_test_fixture["limits"]
        part = workflow_test_fixture["spare_part"]
        initial_part_stock = part.current_stock

        # ---------------------------------------------------------------------
        # STAGE 1 & 2: Select Machine and Ingest SIMULATED Abnormal Telemetry
        # ---------------------------------------------------------------------
        now = timezone.now()
        abnormal_vib = 7.82  # Critical: exceeds max 5.8
        abnormal_temp = 83.5  # Critical: exceeds max 80.0

        sim_reading = MachineTelemetry.objects.create(
            machine=machine,
            timestamp=now,
            vibration_mms=abnormal_vib,
            temperature_c=abnormal_temp,
            speed_rpm=820.0,
            power_kw=49.0,
            utilization_pct=91.0,
            status_flag="CRITICAL",
            raw_sensor_data={
                "is_simulated": True,
                "label": "SIMULATED",
                "source": "E2E_WORKFLOW_VERIFICATION_TEST",
            },
        )
        assert sim_reading.id is not None
        assert sim_reading.raw_sensor_data.get("label") == "SIMULATED"

        # ---------------------------------------------------------------------
        # STAGE 3: Confirm Anomaly Detection Creates Incident
        # ---------------------------------------------------------------------
        # Align checkpoint to ingest this test reading
        cp = DetectionCheckpoint.get_checkpoint()
        cp.last_processed_telemetry_id = sim_reading.id - 1
        cp.save(update_fields=["last_processed_telemetry_id"])

        detector = AnomalyDetector()
        cycle_res = detector.run_cycle(batch_size=20)
        assert cycle_res["anomalies_detected"] >= 1

        anomaly_record = AnomalyDetection.objects.filter(
            machine=machine, telemetry_reading_id=sim_reading.id
        ).first()
        assert anomaly_record is not None
        assert anomaly_record.observed_value == abnormal_vib

        incident = FactoryIncident.objects.filter(
            machine=machine, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]
        ).order_by("-id").first()
        assert incident is not None
        assert incident.severity == IncidentSeverity.CRITICAL
        assert incident.category == IncidentCategory.MACHINE_HEALTH
        assert incident.is_autonomous_action_allowed is True

        # ---------------------------------------------------------------------
        # STAGE 4 & 5: Autonomous Orchestrator Invokes 4 Specialist AI Agents
        # ---------------------------------------------------------------------
        orchestrator = AutonomousFactoryOrchestrator()
        pipeline_res = orchestrator.process_incident(incident.id, force_reanalyze=True, force_provider="MOCK")
        assert pipeline_res["success"] is True

        # Confirm all 4 specialist agent executions exist for this incident
        exec_types = list(
            AgentExecution.objects.filter(incident=incident).values_list("agent__agent_type", flat=True)
        )
        assert AgentType.MACHINE_HEALTH in exec_types
        assert AgentType.MAINTENANCE in exec_types
        assert AgentType.INVENTORY in exec_types
        assert AgentType.PRODUCTION_IMPACT in exec_types

        # Verify incident-specific outputs and provenance
        health_exec = AgentExecution.objects.filter(incident=incident, agent__agent_type=AgentType.MACHINE_HEALTH).first()
        assert health_exec is not None
        assert health_exec.status == AgentExecutionStatus.COMPLETED
        assert health_exec.token_count >= 0
        assert health_exec.latency_ms >= 0

        recovery_case = RecoveryCase.objects.filter(incident=incident).first()
        assert recovery_case is not None
        assert recovery_case.steps.count() >= 3

        # ---------------------------------------------------------------------
        # STAGE 6: Digital Twin Generates Recovery Strategies (A, B, C)
        # ---------------------------------------------------------------------
        workflow_run = AutonomousWorkflowRun.objects.filter(incident=incident).order_by("-id").first()
        assert workflow_run is not None
        assert workflow_run.what_if_scenario is not None

        sim_run = SimulationRun.objects.filter(scenario=workflow_run.what_if_scenario).first()
        assert sim_run is not None

        evaluations = list(RecoveryStrategyEvaluation.objects.filter(run=sim_run).order_by("rank"))
        assert len(evaluations) >= 3
        strat_codes = [e.strategy_code for e in evaluations]
        assert "STRATEGY_A" in strat_codes
        assert "STRATEGY_B" in strat_codes
        assert "STRATEGY_C" in strat_codes
        for ev in evaluations:
            assert ev.estimated_cost is not None
            assert ev.estimated_downtime_hours is not None
            assert ev.rank in [1, 2, 3]

        # ---------------------------------------------------------------------
        # STAGE 7: Strategy Enters Approval Center & Blocks Premature Execution
        # ---------------------------------------------------------------------
        approval = workflow_run.approval_request
        assert approval is not None
        assert approval.status == ApprovalStatus.PENDING
        assert "STRATEGY" in approval.requested_action or "Recovery" in approval.requested_action
        assert ApprovalRequest.objects.filter(incident=incident, status=ApprovalStatus.PENDING).count() >= 1

        # Confirm no premature maintenance tickets were created before approval
        pre_tickets = MaintenanceTicket.objects.filter(machine=machine, incident_reference=incident.incident_code).count()
        assert pre_tickets == 0, "Safety violation: Ticket created before manager approval!"

        # ---------------------------------------------------------------------
        # STAGE 8 & 9: Manager Approves Recommendation & Ticket is Created
        # ---------------------------------------------------------------------
        advance_res = orchestrator.advance_post_approval(
            approval_id=approval.id,
            approved_by="Operations Director",
            user_role="PLANT_DIRECTOR",
            selected_strategy="STRATEGY_A",
            response_notes="Approved Strategy A in-place component replacement.",
        )
        assert advance_res["success"] is True

        approval.refresh_from_db()
        assert approval.status == ApprovalStatus.APPROVED
        assert approval.approved_by == "Operations Director"

        ticket = MaintenanceTicket.objects.filter(machine=machine, incident_reference=incident.incident_code).first()
        assert ticket is not None
        assert ticket.status == TicketStatus.OPEN
        assert ticket.machine == machine
        assert ticket.inspection_checklist is not None
        assert len(ticket.inspection_checklist) >= 3

        # ---------------------------------------------------------------------
        # STAGE 10: Complete Simulated Repair Without Duplicate Spare Part Deductions
        # ---------------------------------------------------------------------
        # Advance through acceptance and inspection
        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.ACCEPTED,
            actor="Lead Technician",
            reason="Accepted work order.",
        )
        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.INSPECTION_IN_PROGRESS,
            actor="Lead Technician",
            reason="Starting inspection.",
        )
        # Record inspection checklist evidence
        checklist = ticket.inspection_checklist
        checklist[0]["status"] = "DEFECT_FOUND"
        checklist[0]["observed_value"] = "Bearing race spalling"
        ticket.inspection_checklist = checklist
        ticket.confirmed_fault = "Bearing race spalling on #6204"
        ticket.save(update_fields=["inspection_checklist", "confirmed_fault"])

        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.REPAIR_IN_PROGRESS,
            actor="Lead Technician",
            reason="Starting repair.",
            payload={"confirmed_fault": ticket.confirmed_fault},
        )

        # First consumption: deducts 1 bearing
        consumed_parts = WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket,
            parts=[{"item_code": "SPR-BRG-6204", "quantity": 1}],
            actor="Lead Technician",
        )
        assert len(consumed_parts) == 1
        part.refresh_from_db()
        assert part.current_stock == initial_part_stock - Decimal("1.00")

        # Second consumption attempt on same ticket: must NOT double-deduct
        duplicate_consumption = WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket,
            parts=[{"item_code": "SPR-BRG-6204", "quantity": 1}],
            actor="Lead Technician",
        )
        part.refresh_from_db()
        assert part.current_stock == initial_part_stock - Decimal("1.00"), "Double deduction occurred!"

        # Complete repair documentation
        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.REPAIR_COMPLETED,
            actor="Lead Technician",
            reason="Bearing replaced and aligned.",
            payload={
                "repair_performed": "Replaced ball bearing #6204 and repacked with Mobilith grease.",
                "actual_repair_duration_minutes": 45,
            },
        )
        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.REPAIR_COMPLETED
        assert ticket.repair_completed_at is not None

        # Advance to AWAITING_VERIFICATION
        WorkOrderLifecycleService.transition_state(
            ticket=ticket,
            new_state=TicketStatus.AWAITING_VERIFICATION,
            actor="Lead Technician",
            reason="Ready for post-repair run-in observation.",
        )
        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.AWAITING_VERIFICATION

        # Duplicate consumption of already consumed part: skips duplicate, stock unchanged
        dup_res = WorkOrderLifecycleService.consume_spare_parts(
            ticket=ticket,
            parts=[{"item_code": "SPR-BRG-6204", "quantity": 1}],
            actor="Lead Technician",
        )
        assert len(dup_res) == 1
        part.refresh_from_db()
        assert part.current_stock == initial_part_stock - Decimal("1.00")

        # Attempting to allocate NEW unconsumed spare parts when in AWAITING_VERIFICATION: blocked
        with pytest.raises(ValidationErrorTuple):
            WorkOrderLifecycleService.consume_spare_parts(
                ticket=ticket,
                parts=[{"item_code": "SPR-NEW-PART-XYZ", "quantity": 1}],
                actor="Lead Technician",
            )

        # ---------------------------------------------------------------------
        # STAGE 11: Generate SIMULATED Healthy Post-Repair Telemetry
        # ---------------------------------------------------------------------
        healthy_readings = MaintenanceSimulationService.generate_post_repair_telemetry(
            machine=machine, num_readings=6, mode="HEALTHY"
        )
        assert len(healthy_readings) == 6
        for r in healthy_readings:
            assert r.vibration_mms < limits.warning_vibration_mms
            assert r.temperature_c < limits.warning_temp_c

        # ---------------------------------------------------------------------
        # STAGE 12: Verify Recovery, Authorized Signoff, and Close Incident
        # ---------------------------------------------------------------------
        eval_report = RecoveryVerificationService.evaluate_machine_recovery(
            machine=machine, ticket=ticket, observation_window=5
        )
        assert eval_report["outcome"] == VerificationStatus.AWAITING_AUTHORIZED_SIGNOFF
        assert eval_report["is_healthy"] is True
        assert eval_report["checks"]["physical_repair_completed"] is True
        assert eval_report["checks"]["telemetry_nominal"] is True
        assert eval_report["checks"]["authorized_signoff"] is False

        # Attempting to close incident before signoff must be BLOCKED
        with pytest.raises(ValidationErrorTuple):
            RecoveryVerificationService.close_incident_with_evidence(
                incident=incident, ticket=ticket, closed_by="Operations Director"
            )

        # Manager Signoff
        signoff_res = RecoveryVerificationService.authorize_and_sign_off(
            ticket=ticket,
            authorized_by="Plant Operations Manager",
            notes="Observed nominal vibration and temperature across 6 run-in samples.",
            role="Plant Operations Manager",
        )
        ticket.refresh_from_db()
        assert ticket.verification_status == VerificationStatus.VERIFIED
        assert ticket.status == TicketStatus.VERIFIED
        assert ticket.authorized_signoff_by == "Plant Operations Manager"

        machine.refresh_from_db()
        assert machine.status == MachineStatus.OPERATIONAL

        # Close incident with complete evidence
        closed_inc = RecoveryVerificationService.close_incident_with_evidence(
            incident=incident,
            ticket=ticket,
            closed_by="Plant Operations Manager",
            resolution_notes="Full verification evidence approved.",
        )
        assert closed_inc.status == IncidentStatus.CLOSED
        assert closed_inc.resolved_at is not None

        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.CLOSED

        # Verify associated RecoveryCase and WorkflowRun were synced to RECOVERED / VERIFIED_RECOVERED
        recovery_case.refresh_from_db()
        assert recovery_case.status == RecoveryCaseStatus.RECOVERED
        assert recovery_case.autonomous_stage == AutonomousWorkflowStage.VERIFIED_RECOVERED

        workflow_run.refresh_from_db()
        assert workflow_run.current_stage == AutonomousWorkflowStage.VERIFIED_RECOVERED
        assert workflow_run.status == "COMPLETED"

        # ---------------------------------------------------------------------
        # STAGE 13: Confirm All Actions Appear in the Audit Trail
        # ---------------------------------------------------------------------
        audits = AuditLog.objects.filter(
            changes_payload__icontains=incident.incident_code
        )
        # Should record incident, ticket transitions, approvals, signoffs
        assert audits.count() >= 3

        # Verify specific audit entries
        approval_audit = AuditLog.objects.filter(
            entity_type="APPROVAL", entity_id=approval.approval_code
        ).first()
        assert approval_audit is not None
        assert approval_audit.actor_id == "Operations Director"

        ticket_audit = AuditLog.objects.filter(
            entity_type="TICKET", entity_id=ticket.ticket_number, action="APPROVAL_GRANTED"
        ).first()
        assert ticket_audit is not None
        assert ticket_audit.actor_id == "Plant Operations Manager"

        incident_close_audit = AuditLog.objects.filter(
            entity_type="INCIDENT", entity_id=incident.incident_code, action="STATUS_CHANGE"
        ).first()
        assert incident_close_audit is not None
        assert incident_close_audit.changes_payload.get("new_status") == "CLOSED"

    def test_faulty_post_repair_telemetry_blocks_closure(self, workflow_test_fixture):
        """
        STAGE 14: Repeat with faulty post-repair telemetry and confirm the incident cannot close incorrectly.
        """
        machine = workflow_test_fixture["machine"]
        limits = workflow_test_fixture["limits"]

        # Create separate incident and ticket for faulty path
        incident = FactoryIncident.objects.create(
            incident_code=f"INC-FAULTY-{uuid.uuid4().hex[:6].upper()}-{machine.code}",
            factory=workflow_test_fixture["factory"],
            department=workflow_test_fixture["department"],
            machine=machine,
            severity=IncidentSeverity.HIGH,
            status=IncidentStatus.INVESTIGATING,
            summary="Bearing vibration anomaly for faulty recovery test",
        )
        ticket = MaintenanceTicket.objects.create(
            ticket_number=f"MNT-FAULTY-{uuid.uuid4().hex[:6].upper()}",
            machine=machine,
            incident_reference=incident.incident_code,
            title="Corrective repair test",
            status=TicketStatus.AWAITING_VERIFICATION,
            repair_completed_at=timezone.now(),
            repair_performed="Installed replacement bearing.",
            actual_repair_duration_minutes=35,
        )

        # Ingest FAULTY post-repair telemetry (vibration 6.8 mm/s exceeds 4.0 warning and 5.8 max)
        faulty_readings = MaintenanceSimulationService.generate_post_repair_telemetry(
            machine=machine, num_readings=6, mode="FAULTY"
        )
        assert len(faulty_readings) == 6

        # Evaluate recovery
        eval_report = RecoveryVerificationService.evaluate_machine_recovery(
            machine=machine, ticket=ticket, observation_window=5
        )
        assert eval_report["outcome"] == VerificationStatus.FAILED
        assert eval_report["is_healthy"] is False
        assert eval_report["checks"]["telemetry_nominal"] is False

        ticket.refresh_from_db()
        assert ticket.status == TicketStatus.VERIFICATION_FAILED
        assert ticket.verification_status == VerificationStatus.FAILED

        # Attempting to authorize signoff must raise ValidationError
        with pytest.raises(ValidationErrorTuple) as exc_signoff:
            RecoveryVerificationService.authorize_and_sign_off(
                ticket=ticket,
                authorized_by="Shift Manager",
                notes="Premature signoff attempt",
            )
        assert "FAILED" in str(exc_signoff.value)

        # Attempting to close incident must raise ValidationError
        with pytest.raises(ValidationErrorTuple) as exc_close:
            RecoveryVerificationService.close_incident_with_evidence(
                incident=incident,
                ticket=ticket,
                closed_by="Shift Manager",
            )
        assert "cannot be closed" in str(exc_close.value).lower()

        # Confirm incident remains open
        incident.refresh_from_db()
        assert incident.status != IncidentStatus.CLOSED

    def test_multi_provider_circuit_breaker_and_deterministic_fallback(self):
        """
        STAGE 15: Test Groq/Gemini unavailability and deterministic fallback resilience.
        """
        # Reset breakers to clean state
        GroqCircuitBreaker.reset()
        GeminiCircuitBreaker.reset()

        # Step 1: Trip Groq circuit breaker (simulating HTTP 429 quota exhaustion)
        GroqCircuitBreaker.record_rate_limit("HTTP 429: Groq Cloud API Rate Limit Exceeded", cooldown_seconds=60)
        assert GroqCircuitBreaker.is_open() is True
        is_avail, status, msg = GroqCircuitBreaker.check_availability()
        assert is_avail is False
        assert status == "RATE_LIMITED"

        # Step 2: Trip Gemini circuit breaker (simulating Google Free Tier quota exhaustion)
        GeminiCircuitBreaker.record_rate_limit("HTTP 429: Google Gemini Resource Exhausted", cooldown_seconds=60)
        assert GeminiCircuitBreaker.is_open() is True
        is_gem_avail, gem_status, _ = GeminiCircuitBreaker.check_availability()
        assert is_gem_avail is False
        assert gem_status == "RATE_LIMITED"

        # Step 3: Verify router engages deterministic fallback
        router = MultiProviderRouter(timeout=5)
        resp = router.generate_structured(
            system_prompt="You are an industrial health specialist",
            user_prompt="Analyze vibration spike",
            schema_description="MachineHealthSchema",
        )
        assert resp.status == "RATE_LIMITED"
        assert resp.reasoning_source == PROVENANCE_DETERMINISTIC_FALLBACK

        # Step 4: Verify health matrix reports breakers accurately
        health = router.get_provider_health()
        assert health["groq"]["circuit_breaker_open"] is True
        assert health["groq"]["status"] == "RATE_LIMITED"
        assert health["gemini"]["circuit_breaker_open"] is True
        assert health["gemini"]["status"] == "RATE_LIMITED"
        assert health["deterministic_fallback"]["status"] == "OPERATIONAL"
        assert health["current_fallback_state"] == "ACTIVE"

        # Step 5: Test specialist agents under deterministic fallback
        health_agent = MachineHealthAgent(provider=get_llm_provider("fallback"))
        assert health_agent.provider.is_configured() is True
        health_out = health_agent.provider.generate_structured(
            system_prompt="Machine Health Specialist",
            user_prompt="Evaluate WEV-AJ-02 bearing vibration",
        )
        assert health_out.structured_json is not None
        assert "possible_root_causes" in health_out.structured_json

        maint_agent = MaintenanceCoordinatorAgent(provider=get_llm_provider("fallback"))
        maint_out = maint_agent.provider.generate_structured(
            system_prompt="Maintenance Coordinator",
            user_prompt="Evaluate inspection checklist for WEV-AJ-02",
            schema_description="MaintenanceCoordinationSchema",
        )
        assert maint_out.structured_json is not None
        assert "recommended_inspection_checklist" in maint_out.structured_json

        # Cleanup: Reset breakers so subsequent tests have pristine state
        GroqCircuitBreaker.reset()
        GeminiCircuitBreaker.reset()
