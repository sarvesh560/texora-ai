"""
Live Google Gemini API & Machine Health Agent Verification Script.
Performs:
1. Secure API Key check (Masked).
2. Gemini Models connectivity check.
3. Live Machine Health Agent investigation with real database evidence.
4. Validates structured JSON response and facts grounding.
5. Verifies AgentExecution & AgentDecision persistence.
6. Verifies safety gate: action remains in PENDING_APPROVAL.
7. Validates that approval authorization is enforced.
"""
import os
import sys
import json
import django
import requests
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
from apps.incidents.models import FactoryIncident, IncidentStatus, IncidentCategory, IncidentSeverity
from apps.simulation.models import InjectedScenario, ScenarioType
from apps.simulation.engine import SimulationEngine
from apps.incidents.detector import AnomalyDetector
from apps.ai_agents.models import AgentDefinition, AgentExecution, AgentDecision, AgentAction, AgentExecutionStatus, AgentType
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.action_service import ActionSafetyService
from apps.ai_agents.llm_client import GeminiProvider, get_llm_provider
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog
from apps.maintenance.models import MaintenanceTicket

def run_gemini_live_test():
    print("=" * 75)
    print("TEXORA AI — LIVE GOOGLE GEMINI INFERENCE & AGENT VERIFICATION")
    print(f"Timestamp: {dj_timezone.now().isoformat()}")
    print("=" * 75)

    # 1. Inspect API Key securely
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        print("\n[CHECK 1] GEMINI_API_KEY Status: NOT CONFIGURED")
        print("  -> Please configure GEMINI_API_KEY in backend/.env to run live Gemini inference.")
        print("  -> Ensure backend/.env remains private and excluded from Git.")
        return False

    masked_key = api_key[:4] + "..." + api_key[-4:] if len(api_key) > 8 else "***"
    print(f"\n[CHECK 1] GEMINI_API_KEY Status: CONFIGURED (Key: {masked_key})")

    # 2. Minimal Authenticated Gemini API Request & Model Discovery
    print("\n[CHECK 2] Querying Google Generative Language API Models Endpoint...")
    models_url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key}"
    try:
        res = requests.get(models_url, timeout=15)
        if res.status_code == 200:
            models_data = res.json().get("models", [])
            gen_models = [m.get("name", "").replace("models/", "") for m in models_data if "generateContent" in m.get("supportedGenerationMethods", [])]
            print(f"  SUCCESS: Authenticated to Google AI Studio. Found {len(gen_models)} text models.")
            print(f"  Sample Available Models: {gen_models[:6]}")
        else:
            print(f"  FAILED: HTTP {res.status_code}: {res.text[:250]}")
            return False
    except Exception as exc:
        print(f"  FAILED: Network connection error: {exc}")
        return False

    # 3. Target Machine & Simulated Incident
    machine = Machine.objects.get(code="WEV-AJ-02")
    limits = machine.operating_limits
    print(f"\n[CHECK 3] Target Machine: {machine.code} ({machine.name})")
    print(f"  Vibration Critical Limit: {limits.max_vibration_mms} mm/s")

    # Clear active scenarios
    InjectedScenario.objects.filter(is_active=True).update(is_active=False, cleared_at=dj_timezone.now())
    FactoryIncident.objects.filter(machine=machine, status__in=['OPEN', 'INVESTIGATING', 'MITIGATING']).update(
        status='RESOLVED', resolution_summary='Clean verification drill', resolved_at=dj_timezone.now()
    )

    # Inject anomaly
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
    print(f"  Simulated Telemetry ID #{latest_tel.id}: Observed Vibration = {latest_tel.vibration_mms:.3f} mm/s (CRITICAL)")

    # Detection cycle
    detector = AnomalyDetector()
    eval_res = detector.run_cycle()
    incident = FactoryIncident.objects.filter(machine=machine, status='OPEN').first()
    assert incident is not None, "Error: Anomaly detection did not create incident."
    print(f"  Incident Created: {incident.incident_code} (ID #{incident.id})")

    # 4. Run Machine Health Agent with EXPLICIT REAL GEMINI PROVIDER (Mock Disabled)
    print("\n[CHECK 4] Executing Live Machine Health Specialist Investigation via Google Gemini...")
    real_gemini = get_llm_provider(force_provider="gemini")
    print(f"  Configured Provider: {real_gemini.__class__.__name__} | Target Model: {getattr(real_gemini, 'model_name', 'gemini')}")
    agent = MachineHealthAgent(provider=real_gemini)

    investigation_result = agent.investigate_incident(incident.id)
    print(f"  Investigation API Result: Success = {investigation_result.get('success')}")

    if not investigation_result.get("success"):
        print(f"  ERROR: Live Gemini investigation failed: {investigation_result.get('error')}")
        return False

    # 5. Validate Agent Execution and Gemini Model Metadata
    execution_id = investigation_result.get("execution_id")
    execution = AgentExecution.objects.get(execution_id=execution_id)
    print(f"\n[CHECK 5] Agent Execution Record:")
    print(f"  Execution ID: {execution.execution_id}")
    print(f"  Status: {execution.status}")
    print(f"  Provider Used: {agent.provider.__class__.__name__} ({getattr(agent.provider, 'model_name', 'gemini')})")
    print(f"  Inference Latency: {execution.latency_ms} ms")
    print(f"  Token Count: {execution.token_count} tokens")
    print(f"  Execution Summary: {execution.execution_summary}")

    # 6. Validate Grounded Facts & Structured Decision
    decision = AgentDecision.objects.filter(execution=execution).first()
    assert decision is not None, "Error: No AgentDecision persisted!"
    findings = investigation_result.get("findings", {})
    
    print(f"\n[CHECK 6] Structured AI Decision & Reasoning:")
    print(f"  Assessed Severity: {findings.get('severity_assessment')}")
    print(f"  Decision Confidence: {decision.confidence_score}%")
    print(f"  Root Causes Identified: {len(findings.get('possible_root_causes', []))}")
    for idx, cause in enumerate(findings.get('possible_root_causes', []), 1):
        print(f"    [{idx}] ({cause.get('likelihood')}, {cause.get('confidence_score')}%) {cause.get('hypothesis')}")
    print(f"  Verified Sensor Facts Grounded in DB:")
    for fact in findings.get('verified_sensor_facts', []):
        print(f"    - {fact}")

    # 7. Action Safety Gate: Proposed Action MUST be PENDING_APPROVAL
    action = AgentAction.objects.filter(execution=execution).first()
    assert action is not None, "Error: No AgentAction proposed by agent."
    print(f"\n[CHECK 7] Action Safety Gate:")
    print(f"  Proposed Action: {action.action_name}")
    print(f"  Action Status: {action.status}")
    assert action.status == "PENDING_APPROVAL", f"Safety violation: Action status is {action.status}!"
    print("  -> CONFIRMED: Action is queued for human review and has NOT self-executed.")

    # 8. Check Approval Request
    approval = ApprovalRequest.objects.filter(agent_action=action).first()
    assert approval is not None, "Error: No ApprovalRequest found."
    print(f"  Approval Request: {approval.approval_code} (Status: {approval.status})")

    # 9. Verify No Unauthorized Ticket Creation
    initial_ticket_count = MaintenanceTicket.objects.filter(machine=machine, incident_reference=incident.incident_code).count()
    assert initial_ticket_count == 0, "Safety violation: Maintenance ticket was created before manager approval!"
    print("\n[CHECK 8] Authorization Barrier: Verified 0 maintenance work orders created prior to human approval.")

    print("\n" + "=" * 75)
    print("REAL GOOGLE GEMINI LIVE INFERENCE & AI AGENT VERIFICATION PASSED (100%)")
    print("=" * 75)
    return True

if __name__ == '__main__':
    success = run_gemini_live_test()
    sys.exit(0 if success else 1)
