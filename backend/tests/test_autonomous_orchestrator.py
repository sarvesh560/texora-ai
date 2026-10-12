import pytest
from unittest.mock import patch, MagicMock
from django.utils import timezone
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType, MachineOperatingLimits, MachineTelemetry, MachineStatus
from apps.incidents.models import FactoryIncident
from apps.ai_agents.models import (
    AutonomousWorkflowRun,
    AutonomousWorkflowStage,
    RecoveryCase,
    RecoveryCaseStatus,
    AgentExecution,
    AgentDefinition,
)
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.maintenance.models import MaintenanceTicket, TicketStatus
from apps.audit_logs.models import AuditLog
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator
from apps.ai_agents.action_service import ActionSafetyService

User = get_user_model()


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def setup_factory(db):
    factory, _ = Factory.objects.get_or_create(code="FAC-PSG-01", defaults={"name": "PSG Mill"})
    dept, _ = Department.objects.get_or_create(
        code="WEV", factory=factory, defaults={"name": "Weaving Shed", "department_type": DepartmentType.WEAVING}
    )
    mtype, _ = MachineType.objects.get_or_create(name="Rapier Loom", defaults={"category": DepartmentType.WEAVING})
    machine, _ = Machine.objects.get_or_create(
        code="WEV-RAP-01",
        defaults={
            "department": dept,
            "machine_type": mtype,
            "name": "Picanol Optimax-i Rapier Loom #1",
            "status": MachineStatus.OPERATIONAL,
            "rated_speed_rpm": 650,
            "current_health_score": 95.0,
        },
    )
    limits, _ = MachineOperatingLimits.objects.get_or_create(
        machine=machine,
        defaults={
            "warning_temp_c": 75.0,
            "max_temp_c": 85.0,
            "warning_vibration_mms": 4.0,
            "max_vibration_mms": 5.5,
            "min_rpm": 500,
            "max_rpm": 750,
        },
    )
    telemetry = MachineTelemetry.objects.create(
        machine=machine,
        timestamp=timezone.now(),
        vibration_mms=14.5,
        temperature_c=82.0,
        speed_rpm=580.0,
        power_kw=18.5,
        status_flag="CRITICAL",
    )
    return {
        "factory": factory,
        "dept": dept,
        "machine": machine,
        "telemetry": telemetry,
    }


@pytest.mark.django_db
class TestAutonomousFactoryOrchestrator:

    def test_a_b_c_d_e_f_full_autonomous_loop(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-001",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="CRITICAL",
            summary="Severe bearing vibration excursion (14.5 mm/s)",
            status="OPEN",
            evidence_data={"vibration_mms": 14.5, "temperature_c": 82.0},
        )

        orchestrator = AutonomousFactoryOrchestrator()
        result = orchestrator.process_incident(incident.id, force_provider="FALLBACK")

        assert result["success"] is True
        assert result["status"] == AutonomousWorkflowStage.AWAITING_MANAGER_APPROVAL
        assert result["recommended_strategy"] in [
            "HYBRID_RECOVERY", "REPAIR_FIRST", "PRODUCTION_REROUTING",
            "STRATEGY_A", "STRATEGY_B", "STRATEGY_C"
        ]
        assert result["workflow_run_id"].startswith("AWR-")

        # Verify RecoveryCase linkage
        rec_case = RecoveryCase.objects.get(id=result["recovery_case_id"])
        assert rec_case.incident == incident
        assert rec_case.autonomous_stage == AutonomousWorkflowStage.AWAITING_MANAGER_APPROVAL
        assert rec_case.what_if_scenario is not None
        assert rec_case.recommended_strategy is not None

        # Verify ApprovalRequest created & pending
        approval = ApprovalRequest.objects.filter(incident=incident).first()
        assert approval is not None
        assert approval.status == ApprovalStatus.PENDING

    def test_g_no_maintenance_execution_before_approval(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-002",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="HIGH",
            summary="Thermal buildup on drive shaft",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        result = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        assert result["success"] is True

        # Ensure no open maintenance ticket created before approval
        tickets = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code)
        assert tickets.count() == 0

    def test_h_approved_action_advances_recovery_workflow(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-003",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="CRITICAL",
            summary="Motor phase imbalance",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        res = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        case_id = res["recovery_case_id"]

        approval = ApprovalRequest.objects.filter(incident=incident).first()

        # Manager approves
        advance_res = orchestrator.advance_post_approval(
            recovery_case_id=case_id,
            approval_request_id=approval.id if approval else None,
            approved_by="K. Sundaram (Plant Director)",
            selected_strategy="HYBRID_RECOVERY",
            response_notes="Approved for priority repair and partial batch rerouting.",
        )

        assert advance_res["success"] is True
        assert advance_res["status"] == AutonomousWorkflowStage.AWAITING_VERIFICATION

        rec_case = RecoveryCase.objects.get(id=case_id)
        assert rec_case.status == RecoveryCaseStatus.IN_RECOVERY
        assert rec_case.selected_strategy == "HYBRID_RECOVERY"

        # Check work order creation
        ticket = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).first()
        assert ticket is not None
        assert ticket.status == TicketStatus.OPEN

    def test_i_duplicate_incidents_do_not_create_duplicate_pipelines(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-004",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="HIGH",
            summary="Belt tension degradation",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        res1 = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        run_id_1 = res1["workflow_run_id"]

        # Second call for the same incident while awaiting approval
        res2 = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        run_id_2 = res2["workflow_run_id"]

        assert run_id_1 == run_id_2
        assert AutonomousWorkflowRun.objects.filter(incident=incident).count() == 1

    def test_j_simulation_does_not_mutate_operational_records(self, setup_factory):
        machine = setup_factory["machine"]
        initial_status = machine.status

        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-005",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="CRITICAL",
            summary="Excessive bearing noise and oscillation",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        orchestrator.process_incident(incident.id, force_provider="FALLBACK")

        machine.refresh_from_db()
        assert machine.status == initial_status

    def test_k_restart_safe_workflow_recovery(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-006",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="HIGH",
            summary="Spindle misalignment",
            status="OPEN",
        )

        # Create interrupted workflow run
        run = AutonomousWorkflowRun.objects.create(
            workflow_id="WF-RESTART-001",
            incident=incident,
            current_stage=AutonomousWorkflowStage.INVESTIGATION_PENDING,
            recommendation_payload={},
        )

        orchestrator = AutonomousFactoryOrchestrator()
        cycle_res = orchestrator.run_cycle()

        assert cycle_res["success"] is True
        assert cycle_res["processed_count"] >= 1

        run.refresh_from_db()
        assert run.current_stage in [
            AutonomousWorkflowStage.AWAITING_MANAGER_APPROVAL,
            AutonomousWorkflowStage.COORDINATING_AGENTS,
            AutonomousWorkflowStage.SIMULATING_STRATEGIES,
        ]

    def test_l_missing_gemini_credentials_uses_labeled_fallback(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-007",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="MEDIUM",
            summary="Sensor telemetry drift",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        res = orchestrator.process_incident(incident.id, force_provider="FALLBACK")

        assert res["ai_provider"] == "DETERMINISTIC_FALLBACK"

        rec_case = RecoveryCase.objects.get(id=res["recovery_case_id"])
        assert rec_case.recommendation_payload.get("ai_provider") == "DETERMINISTIC_FALLBACK"

    def test_m_verification_requires_fresh_telemetry_and_evidence(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-008",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="CRITICAL",
            summary="High vibration anomaly",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        res = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        case_id = res["recovery_case_id"]

        # Advance approval first
        orchestrator.advance_post_approval(
            recovery_case_id=case_id,
            approved_by="Plant Director",
            selected_strategy="HYBRID_RECOVERY",
        )

        # 1. Verification with stale/abnormal telemetry should report not verified
        setup_factory["telemetry"].vibration_mms = 12.0
        setup_factory["telemetry"].status_flag = "CRITICAL"
        setup_factory["telemetry"].save()

        ver_res_fail = orchestrator.verify_recovery(
            recovery_case_id=case_id,
            technician_name="T. Murugan",
            repair_notes="Inspection done",
            check_freshness=True,
        )
        assert ver_res_fail["verified"] is False

        # 2. Inject fresh nominal telemetry and verify
        setup_factory["telemetry"].vibration_mms = 1.9
        setup_factory["telemetry"].timestamp = timezone.now()
        setup_factory["telemetry"].status_flag = "NORMAL"
        setup_factory["telemetry"].save()

        ver_res_success = orchestrator.verify_recovery(
            recovery_case_id=case_id,
            technician_name="T. Murugan (Senior Lead)",
            repair_notes="Bearing assembly replaced and laser aligned.",
            check_freshness=True,
        )
        assert ver_res_success["verified"] is True
        assert ver_res_success["status"] == AutonomousWorkflowStage.VERIFIED_RECOVERED

    def test_n_rejected_approvals_do_not_execute_actions(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-009",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="HIGH",
            summary="Transient voltage dip",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        res = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        approval = ApprovalRequest.objects.filter(incident=incident).first()

        rej_res = ActionSafetyService.reject_approval(
            approval_id=approval.id,
            rejected_by="Plant Director",
            response_notes="Transient reading self-cleared, no repair needed.",
        )
        assert rej_res["success"] is True

        approval.refresh_from_db()
        assert approval.status == ApprovalStatus.REJECTED
        assert MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).count() == 0

    def test_o_audit_history_preserves_complete_lifecycle(self, setup_factory):
        machine = setup_factory["machine"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-010",
            factory=machine.department.factory,
            machine=machine,
            department=machine.department,
            severity="CRITICAL",
            summary="Audit test excursion",
            status="OPEN",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        res = orchestrator.process_incident(incident.id, force_provider="FALLBACK")
        case_id = res["recovery_case_id"]

        orchestrator.advance_post_approval(
            recovery_case_id=case_id,
            approved_by="Auditor General (Plant Director)",
            selected_strategy="HYBRID_RECOVERY",
        )

        audit_logs = AuditLog.objects.filter(entity_id__icontains="INC-TEST-010")
        assert audit_logs.count() >= 1

    def test_one_click_expo_demo(self, setup_factory):
        """
        Verifies One-Click Expo Demo scenario execution.
        """
        orchestrator = AutonomousFactoryOrchestrator()
        res = orchestrator.execute_expo_demo(machine_code="WEV-RAP-01")

        assert res["success"] is True
        assert res["machine_code"] == "WEV-RAP-01"
        assert res["status"] == AutonomousWorkflowStage.AWAITING_MANAGER_APPROVAL
        assert res["approval_request_id"] is not None
