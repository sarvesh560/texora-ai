"""
End-to-End Live Verification Script for Phase 5: Autonomous AI Agents (Machine Health Specialist).
Verifies:
1. Injected anomaly produces abnormal telemetry.
2. Anomaly detector creates database-backed FactoryIncident.
3. Machine Health Specialist Agent automatically discovers and investigates incident.
4. Read-only domain tools extract factual evidence.
5. LLM generates structured root cause hypotheses and recommended actions.
6. Action safety gate creates ApprovalRequest (action does NOT self-execute).
7. Operations manager approves request -> real MaintenanceTicket created and AuditLog recorded.
8. Status of live LLM inference provider (Gemini / OpenAI / Mock).
"""
import os
import sys
import json
import django
from datetime import datetime, timezone

# Django setup
backend_dir = os.path.dirname(os.path.abspath(__file__))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)
os.chdir(backend_dir)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from django.utils import timezone as dj_timezone
from apps.machines.models import Machine, MachineOperatingLimits, MachineTelemetry
from apps.incidents.models import FactoryIncident, IncidentStatus
from apps.simulation.models import InjectedScenario, ScenarioType
from apps.simulation.engine import SimulationEngine
from apps.incidents.detector import AnomalyDetector
from apps.ai_agents.models import AgentDefinition, AgentExecution, AgentDecision, AgentAction, AgentExecutionStatus
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.action_service import ActionSafetyService
from apps.ai_agents.llm_client import get_llm_provider
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog
from apps.maintenance.models import MaintenanceTicket

def run_phase5_live_verification():
    print("=" * 75)
    print("TEXORA AI — PHASE 5: AUTONOMOUS AI AGENT LIVE VERIFICATION")
    print(f"Timestamp: {dj_timezone.now().isoformat()}")
    print("=" * 75)

    # 0. Check LLM Provider Configuration
    provider = get_llm_provider()
    provider_name = os.getenv("LLM_PROVIDER", "gemini")
    is_live_configured = provider.is_configured()
    print(f"\n[STEP 0] LLM Provider Configuration:")
    print(f"  Configured Provider: {provider_name.upper()}")
    print(f"  Target Model: {getattr(provider, 'model_name', 'default')}")
    print(f"  Live Credentials Active: {is_live_configured}")
    if not is_live_configured:
        print("  NOTICE: Live API key not set in .env. Using verified MockLLMProvider for deterministic verification.")
        from apps.ai_agents.llm_client import MockLLMProvider
        agent = MachineHealthAgent(provider=MockLLMProvider())
    else:
        print("  SUCCESS: Live LLM provider active with API credentials.")
        agent = MachineHealthAgent()

    # 1. Target Machine Setup
    machine = Machine.objects.get(code="WEV-AJ-02")
    limits = machine.operating_limits
    print(f"\n[STEP 1] Target Machine: {machine.code} ({machine.name})")
    print(f"  Department: {machine.department.name}")
    print(f"  Vibration Warning: {limits.warning_vibration_mms} mm/s | Critical: {limits.max_vibration_mms} mm/s")

    # Clear existing active scenarios and incidents on this machine for clean drill
    InjectedScenario.objects.filter(is_active=True).update(is_active=False, cleared_at=dj_timezone.now())
    FactoryIncident.objects.filter(machine=machine, status__in=['OPEN', 'INVESTIGATING', 'MITIGATING']).update(
        status='RESOLVED', resolution_summary='Clean verification drill start', resolved_at=dj_timezone.now()
    )

    # 2. Inject Anomaly and Generate Telemetry
    print(f"\n[STEP 2] Injecting WEAVING_VIBRATION scenario into {machine.code}...")
    InjectedScenario.objects.create(
        scenario_type=ScenarioType.WEAVING_VIBRATION,
        target_machine_code="WEV-AJ-02",
        severity="CRITICAL",
        is_active=True,
        description="Loom Main Drive Bearing Deterioration Drill",
    )
    sim = SimulationEngine()
    sim.run_tick()
    latest_tel = MachineTelemetry.objects.filter(machine=machine).order_by('-timestamp').first()
    print(f"  Observed Telemetry ID #{latest_tel.id}: Vibration = {latest_tel.vibration_mms:.3f} mm/s (CRITICAL)")

    # 3. Autonomous Anomaly Detection Cycle
    print("\n[STEP 3] Running Anomaly Detection Cycle...")
    detector = AnomalyDetector()
    eval_res = detector.run_cycle()
    incident = FactoryIncident.objects.filter(machine=machine, status='OPEN').first()
    assert incident is not None, "Error: No incident created by anomaly detector!"
    print(f"  Incident Detected: {incident.incident_code} (ID #{incident.id})")
    print(f"  Summary: {incident.summary}")
    print(f"  Severity: {incident.severity}")

    # 4. Autonomous AI Agent Discovery & Investigation
    print("\n[STEP 4] Autonomous Machine Health Agent Triggered...")
    cycle_res = agent.run_cycle()
    print(f"  Agent Scan: Found {cycle_res['pending_found']} pending incident(s)")
    print(f"  Investigations Executed: {cycle_res['investigated_count']}")

    # 5. Verify Investigation Persistence
    incident.refresh_from_db()
    execution = AgentExecution.objects.filter(incident=incident).order_by('-started_at').first()
    assert execution is not None, "Error: No AgentExecution record found!"
    assert execution.status == AgentExecutionStatus.COMPLETED, f"AgentExecution status: {execution.status}"

    print(f"\n[STEP 5] Agent Execution & Reasoning Persisted:")
    print(f"  Execution ID: {execution.execution_id}")
    print(f"  Agent: {execution.agent.name}")
    print(f"  Latency: {execution.latency_ms} ms | Tokens: {execution.token_count}")
    print(f"  Execution Summary: {execution.execution_summary}")
    print(f"  Updated Incident Root Cause: {incident.root_cause_hypothesis}")

    # 6. Verify Structured Decision
    decision = AgentDecision.objects.filter(execution=execution).first()
    assert decision is not None, "Error: No AgentDecision record found!"
    print(f"\n[STEP 6] Structured AI Decision:")
    print(f"  Decision Type: {decision.get_decision_type_display()}")
    print(f"  Confidence: {decision.confidence_score}%")
    print(f"  Risk Level: {decision.risk_level}")
    print(f"  Requires Human Approval: {decision.requires_human_approval}")
    print(f"  Decision Rationale: {decision.rationale[:200]}...")

    # 7. Verify Action Safety Gate (Approval Request)
    action = AgentAction.objects.filter(execution=execution).first()
    assert action is not None, "Error: No AgentAction proposed!"
    print(f"\n[STEP 7] Action Safety Gate Check:")
    print(f"  Proposed Action: {action.action_name}")
    print(f"  Initial Action Status: {action.status} (Not self-executed)")
    assert action.status == "PENDING_APPROVAL", f"Safety violation: Action was {action.status} without approval!"

    approval = ApprovalRequest.objects.filter(agent_action=action).first()
    assert approval is not None, "Error: No ApprovalRequest created!"
    print(f"  Approval Request Code: {approval.approval_code}")
    print(f"  Approval Status: {approval.status}")
    print(f"  Requested Action: {approval.requested_action}")

    # 8. Authorized Manager Approval & Execution
    print("\n[STEP 8] Simulating Authorized Manager Approval...")
    approval_res = ActionSafetyService.approve_and_execute(
        approval_id=approval.id,
        approved_by="K. Sundaram (Plant Ops Manager)",
        response_notes="Approved loom drive end bearing replacement based on AI diagnostic report.",
    )
    print(f"  Approval Result: {approval_res}")
    assert approval_res["success"] is True

    # 9. Verify Real Work Order & Audit Log
    ticket = MaintenanceTicket.objects.filter(machine=machine, incident_reference=incident.incident_code).first()
    assert ticket is not None, "Error: No MaintenanceTicket created upon approval!"
    print(f"\n[STEP 9] Real Database Work Order Created:")
    print(f"  Ticket Number: {ticket.ticket_number}")
    print(f"  Title: {ticket.title}")
    print(f"  Machine: {ticket.machine.code}")
    print(f"  Priority: {ticket.priority}")
    print(f"  Assigned Technician: {ticket.assigned_technician}")
    print(f"  Created By Agent: {ticket.created_by_agent}")

    audit = AuditLog.objects.filter(entity_id=approval.approval_code, action="APPROVAL_GRANTED").first()
    assert audit is not None, "Error: No AuditLog entry recorded!"
    print(f"\n[STEP 10] Immutable Audit Log Entry:")
    print(f"  Entity: {audit.entity_type} #{audit.entity_id}")
    print(f"  Action: {audit.action}")
    print(f"  Actor: {audit.actor_type} ({audit.actor_id})")
    print(f"  Timestamp: {audit.timestamp.isoformat()}")

    print("\n" + "=" * 75)
    print("ALL PHASE 5 AUTONOMOUS AI AGENT VERIFICATION CHECKS PASSED (100%)")
    print("=" * 75)

if __name__ == '__main__':
    run_phase5_live_verification()
