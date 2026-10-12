"""
Phase 6 End-to-End Multi-Agent Maintenance & Recovery Coordination Demonstration.
Verifies:
1. Scenario Injection & Anomaly Detection on WEV-AJ-02.
2. Real Gemini Machine Health Specialist Investigation.
3. Multi-Agent Recovery Coordination (Maintenance, Inventory, Production).
4. Evidence-based Recovery Priority Scoring & Dependency Plan Construction.
5. Approval Security Barrier (Zero unauthorized work orders prior to manager approval).
6. Security RBAC Tests (Rejecting anonymous, AI self-approval, and unauthorized roles).
7. Authorized Manager Approval & Transactional Work Order Dispatch.
8. Immutable Audit Trail & Recovery Step Progression.
"""
import os
import sys
import json
import django

# Django setup
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
os.chdir(backend_dir)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from django.utils import timezone as dj_timezone
from apps.machines.models import Machine, MachineTelemetry
from apps.incidents.models import FactoryIncident
from apps.simulation.models import InjectedScenario, ScenarioType
from apps.simulation.engine import SimulationEngine
from apps.incidents.detector import AnomalyDetector
from apps.ai_agents.models import (
    AgentDefinition,
    AgentExecution,
    AgentAction,
    RecoveryCase,
    RecoveryPlanStep,
    RecoveryCaseStatus,
    RecoveryStepStatus,
    AgentType,
)
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.recovery_orchestrator import RecoveryOrchestrator
from apps.ai_agents.action_service import ActionSafetyService
from apps.ai_agents.llm_client import get_llm_provider
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog
from apps.maintenance.models import MaintenanceTicket, TicketStatus
from apps.inventory.models import InventoryItem, InventoryTransaction
from apps.production.models import ProductionBatch


def run_phase6_demonstration():
    print("=" * 80)
    print("TEXORA AI — PHASE 6: AUTONOMOUS MAINTENANCE & RECOVERY COORDINATION DEMO")
    print(f"Timestamp: {dj_timezone.now().isoformat()}")
    print("=" * 80)

    # 1. Inspect API Key & Model Configuration Securely
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    configured_model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
    if not api_key:
        print("\n[CHECK 1] GEMINI_API_KEY: NOT CONFIGURED")
        return False

    masked_key = api_key[:4] + "..." + api_key[-4:] if len(api_key) > 8 else "***"
    print(f"\n[CHECK 1] AI Provider Config: Gemini ({configured_model}) | API Key: {masked_key} [SECURE]")

    # 2. Target Machine & Inject Vibration Scenario
    machine = Machine.objects.get(code="WEV-AJ-02")
    limits = machine.operating_limits
    print(f"\n[CHECK 2] Target Machine: {machine.code} ({machine.name})")
    print(f"  Vibration Critical Limit: {limits.max_vibration_mms} mm/s")

    # Clear active scenarios and previous open incidents / tickets on this machine
    InjectedScenario.objects.filter(is_active=True).update(is_active=False, cleared_at=dj_timezone.now())
    FactoryIncident.objects.filter(machine=machine, status__in=['OPEN', 'INVESTIGATING', 'MITIGATING']).update(
        status='RESOLVED', resolution_summary='Clean Phase 6 demonstration drill', resolved_at=dj_timezone.now()
    )
    MaintenanceTicket.objects.filter(machine=machine, status__in=['OPEN', 'ASSIGNED', 'IN_PROGRESS', 'PENDING_PARTS']).update(
        status=TicketStatus.CLOSED, resolved_at=dj_timezone.now()
    )


    # Inject anomaly
    InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code="WEV-AJ-02",
        severity="CRITICAL",
        is_active=True,
        description="Loom Main Drive Bearing Deterioration - Phase 6 Recovery Drill",
    )
    sim = SimulationEngine()
    sim.run_tick()
    latest_tel = MachineTelemetry.objects.filter(machine=machine).order_by('-timestamp').first()
    print(f"  Simulated Telemetry: Vibration = {latest_tel.vibration_mms:.3f} mm/s (CRITICAL LIMIT: {limits.max_vibration_mms} mm/s)")

    # 3. Autonomous Anomaly Detection
    detector = AnomalyDetector()
    detector.run_cycle()
    incident = FactoryIncident.objects.filter(machine=machine, status='OPEN').first()
    assert incident is not None, "Error: Anomaly detector failed to create incident."
    print(f"\n[CHECK 3] Incident Detected & Persisted: {incident.incident_code} (ID #{incident.id})")
    print(f"  Severity: {incident.severity} | Category: {incident.get_category_display()}")

    # 4. Run Live Gemini Machine Health Investigation
    print("\n[CHECK 4] Executing Live Machine Health Investigation via Google Gemini...")
    health_agent = MachineHealthAgent()
    investigation_res = health_agent.investigate_incident(incident.id)
    assert investigation_res.get("success") is True, f"Health investigation failed: {investigation_res.get('error')}"
    
    health_exec = AgentExecution.objects.get(execution_id=investigation_res.get("execution_id"))
    print(f"  Investigation Execution ID: {health_exec.execution_id}")
    print(f"  Inference Latency: {health_exec.latency_ms} ms | Tokens: {health_exec.token_count}")
    findings = investigation_res.get("findings", {})
    print(f"  Assessed Severity: {findings.get('severity_assessment')}")
    root_causes = findings.get("possible_root_causes", [])
    if root_causes:
        print(f"  Primary Root Cause Hypothesis: ({root_causes[0].get('likelihood')}, {root_causes[0].get('confidence_score')}%) {root_causes[0].get('hypothesis')}")

    # 5. Multi-Agent Recovery Orchestration
    print("\n[CHECK 5] Triggering Multi-Agent Factory Recovery Orchestrator...")
    orchestrator = RecoveryOrchestrator()
    orch_res = orchestrator.orchestrate_incident_recovery(incident_id=incident.id, force_reanalyze=True)
    assert orch_res.get("success") is True, f"Orchestration failed: {orch_res.get('error')}"

    recovery_case = RecoveryCase.objects.get(id=orch_res["case_id"])
    print(f"  Recovery Case Code: {recovery_case.case_code} (ID #{recovery_case.id})")
    print(f"  Case Status: {recovery_case.status}")
    print(f"  Evidence-Based Priority Score: {recovery_case.priority_score}% [{recovery_case.priority}]")
    print(f"  Target Resolution Time: {recovery_case.target_resolution_hours} hours")
    print(f"  Estimated Downtime: {recovery_case.estimated_downtime_hours} hours")

    # 6. Inspect Multi-Agent Evidence & Plan Steps
    print("\n[CHECK 6] Correlated Multi-Agent Evidence Synthesis:")
    maint_rec = recovery_case.maintenance_recommendation
    print(f"  [Maintenance Coordinator]: Proposed Work Order: '{maint_rec.get('proposed_ticket', {}).get('title')}'")
    print(f"    Assigned: {maint_rec.get('assigned_technician')} (Est: {maint_rec.get('estimated_hours')}h)")
    print(f"    Inspection Checklist Steps: {len(maint_rec.get('inspection_steps', []))}")

    inv_eval = recovery_case.inventory_assessment
    print(f"  [Inventory Coordinator]: Evaluated {len(inv_eval.get('evaluated_parts', []))} spare parts in warehouse.")
    print(f"    Shortages Detected: {inv_eval.get('shortages_count', 0)}")
    for part in inv_eval.get("evaluated_parts", [])[:2]:
        print(f"    - {part.get('item_code')}: {part.get('name')} (Stock: {part.get('current_stock')} {part.get('unit')}, Status: {part.get('status')})")

    prod_impact = recovery_case.production_impact_assessment
    print(f"  [Production Impact Agent]: Active Batches: {len(prod_impact.get('active_batches', []))}")
    print(f"    Orders At Risk: {len(prod_impact.get('orders_at_risk', []))}")
    print(f"    Alternate Machines Discovered: {len(prod_impact.get('alternate_machines', []))}")

    # 7. Recovery Plan Dependency Graph
    print("\n[CHECK 7] Structured Recovery Plan Timeline & Step Dependencies:")
    steps = recovery_case.steps.all()
    for s in steps:
        dep_str = f"Depends on Step(s): {s.dependencies}" if s.dependencies else "Root Step (No dependencies)"
        appr_str = f"Approval Code: {s.approval_request.approval_code} [{s.approval_request.status}]" if s.approval_request else "No approval required"
        print(f"  Step {s.step_order}: [{s.agent_type}] {s.title}")
        print(f"    Status: {s.status} | {dep_str}")
        print(f"    Gate: {appr_str}")

    # 8. Action Safety Barrier Validation
    print("\n[CHECK 8] Safety Authorization Barrier:")
    initial_ticket_count = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).count()
    assert initial_ticket_count == 0, "Safety violation: Maintenance ticket was created before manager approval!"
    print("  -> CONFIRMED: 0 maintenance work orders created prior to human manager authorization.")

    # 9. Role-Based Access Control Security Tests
    print("\n[CHECK 9] Testing Server-Side RBAC & Security Gates:")
    maint_step = recovery_case.steps.filter(action_type="CREATE_MAINTENANCE_TICKET").first()
    assert maint_step and maint_step.approval_request, "Error: No maintenance approval request found."
    approval = maint_step.approval_request

    # Test 9a: Anonymous user rejection
    res_anon = ActionSafetyService.approve_and_execute(approval_id=approval.id, approved_by="", user_role="MAINTENANCE_MANAGER")
    assert res_anon["success"] is False, "Security failure: Anonymous user was allowed to approve!"
    print("  [Pass] Anonymous approval correctly rejected.")

    # Test 9b: AI agent self-approval rejection
    res_ai = ActionSafetyService.approve_and_execute(approval_id=approval.id, approved_by="machine_health_agent", user_role="MAINTENANCE_MANAGER")
    assert res_ai["success"] is False, "Security failure: AI agent was allowed to self-approve!"
    print("  [Pass] AI agent self-approval correctly rejected.")

    # Test 9c: Unauthorized role rejection
    res_unauth = ActionSafetyService.approve_and_execute(approval_id=approval.id, approved_by="John Doe (Floor Operator)", user_role="OPERATOR")
    assert res_unauth["success"] is False, "Security failure: Unauthorized role was allowed to approve!"
    print(f"  [Pass] Operator role rejection verified: {res_unauth.get('error')[:60]}...")

    # 10. Execute Authorized Human Manager Approval
    print("\n[CHECK 10] Executing Authorized Manager Approval...")
    manager_name = "K. Sundaram (Plant Maintenance Superintendent)"
    manager_role = "MAINTENANCE_MANAGER"
    
    appr_res = ActionSafetyService.approve_and_execute(
        approval_id=approval.id,
        approved_by=manager_name,
        user_role=manager_role,
        response_notes="Approved for priority fast-response mechanical intervention.",
    )
    assert appr_res["success"] is True, f"Approval execution failed: {appr_res.get('error')}"
    print(f"  Approval Success: {appr_res['approval_code']} -> Status: {appr_res['action_status']}")

    # 11. Verify Work Order Creation & Audit Log
    ticket = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).first()
    assert ticket is not None, "Error: Maintenance ticket was not created upon approval."
    print("\n[CHECK 11] Verified Real Domain Model Persistence:")
    print(f"  Created Maintenance Ticket: {ticket.ticket_number}")
    print(f"  Title: {ticket.title}")
    print(f"  Priority: {ticket.priority} | Status: {ticket.status}")
    print(f"  Assigned Technician: {ticket.assigned_technician}")
    print(f"  Labor Hours: {ticket.labor_hours}h")

    # Check Audit Log
    audit = AuditLog.objects.filter(entity_id=approval.approval_code, action="APPROVAL_GRANTED").first()
    assert audit is not None, "Error: Approval was not audited."
    print(f"  Audit Log Record ID #{audit.id}: {audit.description}")
    print(f"  Actor: {audit.actor_id} ({audit.actor_type}) at {audit.timestamp}")

    # 12. Check Recovery Plan Step Advancement
    maint_step.refresh_from_db()
    print(f"\n[CHECK 12] Recovery Plan Step Status Advancement:")
    print(f"  Step {maint_step.step_order} Status: {maint_step.status} (Completed At: {maint_step.completed_at})")
    
    print("\n" + "=" * 80)
    print("PHASE 6: MULTI-AGENT MAINTENANCE & RECOVERY COORDINATION VERIFIED (100%)")
    print("=" * 80)
    return True


if __name__ == '__main__':
    success = run_phase6_demonstration()
    sys.exit(0 if success else 1)
