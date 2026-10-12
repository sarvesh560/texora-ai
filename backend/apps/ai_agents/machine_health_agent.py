"""
Autonomous Machine Health Specialist AI Agent for Texora AI.
Continuously investigates detected textile machinery incidents, gathers multi-domain database evidence
using validated read-only tools, invokes LLM inference with structured JSON output, persists execution records,
and routes high-impact recommendations through human approval gates.
"""
import json
import logging
import threading
from typing import Dict, Any, List, Optional
from django.db import transaction, close_old_connections
from django.utils import timezone

from apps.ai_agents.models import (
    AgentDefinition,
    AgentExecution,
    AgentDecision,
    AgentAction,
    AgentType,
    AgentExecutionStatus,
)
from apps.ai_agents.llm_client import get_llm_provider, BaseLLMProvider, LLMResponse
from apps.ai_agents.tools import (
    get_machine_details,
    get_recent_machine_telemetry,
    get_machine_operating_limits,
    get_machine_maintenance_history,
    get_active_machine_incidents,
    get_affected_production_orders,
    get_relevant_spare_parts,
)
from apps.ai_agents.action_service import ActionSafetyService
from apps.incidents.models import FactoryIncident, IncidentStatus, IncidentCategory
from apps.machines.models import Machine

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are the Texora AI Autonomous Machine Health Specialist Agent for an industrial textile manufacturing plant.
Your mission is to perform rigorous, deterministic root-cause investigation on machine telemetry anomalies and operational incidents.

STRICT OPERATIONAL GUIDELINES:
1. Ground your reasoning strictly in the provided database evidence (telemetry, limits, maintenance logs, production schedule, spare parts).
2. Clearly distinguish between:
   - VERIFIED SENSOR FACTS: Actual physical measurements from the database.
   - RULE-BASED ANOMALIES: Limits breached by the telemetry.
   - AI-GENERATED HYPOTHESES: Suspected mechanical/electrical failure modes.
   - UNCONFIRMED AREAS: Missing sensor dimensions or required floor inspections.
3. NEVER fabricate sensor readings, maintenance inspections, or false certainties.
4. If bearing vibration is elevated, state it as a hypothesis (e.g. potential bearing spalling, cage damage, or belt misalignment), NOT a 100% verified fact until human inspection.
5. All sensitive actions (e.g. creating maintenance tickets, dispatching technicians, parts reservation) MUST have requires_human_approval=true.
6. Return your response exclusively as valid JSON matching the required schema.

REQUIRED JSON SCHEMA:
{
  "incident_id": <int>,
  "machine_code": "<str>",
  "observed_abnormal_conditions": ["<str>", ...],
  "verified_sensor_facts": ["<str>", ...],
  "possible_root_causes": [
    {
      "hypothesis": "<str>",
      "likelihood": "HIGH" | "MEDIUM" | "LOW",
      "confidence_score": <float 0-100>
    }
  ],
  "missing_information": ["<str>", ...],
  "recommended_maintenance_checks": ["<str>", ...],
  "production_impact_considerations": ["<str>", ...],
  "severity_assessment": "LOW" | "MEDIUM" | "HIGH" | "CRITICAL",
  "confidence_explanation": "<str>",
  "suggested_next_actions": [
    {
      "action_type": "CREATE_MAINTENANCE_DRAFT" | "RESERVE_SPARE_PART" | "SCHEDULE_INSPECTION",
      "description": "<str>",
      "requires_human_approval": true,
      "payload": { ... }
    }
  ]
}
"""


class MachineHealthAgent:
    """
    Autonomous Machine Health Specialist Agent orchestrator.
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(MachineHealthAgent, cls).__new__(cls)
                cls._instance._is_initialized = False
            return cls._instance

    def __init__(self, provider: Optional[BaseLLMProvider] = None):
        if self._is_initialized:
            if provider:
                self.provider = provider
                if getattr(self.provider, "model_name", None):
                    AgentDefinition.objects.filter(agent_type=AgentType.MACHINE_HEALTH).update(
                        model_name=self.provider.model_name
                    )
            return
        self._is_initialized = True
        self.provider = provider or get_llm_provider()
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        """Ensures the Machine Health Agent definition exists in the database and reflects active provider."""
        current_model = getattr(self.provider, "model_name", "gemini-3.5-flash")
        agent_def, created = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.MACHINE_HEALTH,
            defaults={
                "name": "Machine Health Diagnostic Specialist",
                "description": "Autonomous reliability engineer analyzing machine vibration, thermal runaway, and mechanical wear.",
                "model_name": current_model,
                "is_enabled": True,
                "permitted_actions": [
                    "get_machine_details",
                    "get_recent_machine_telemetry",
                    "get_machine_operating_limits",
                    "get_machine_maintenance_history",
                    "get_active_machine_incidents",
                    "get_affected_production_orders",
                    "get_relevant_spare_parts",
                    "CREATE_MAINTENANCE_DRAFT",
                    "RESERVE_SPARE_PART",
                ],
                "sensitivity_threshold": 0.80,
            },
        )
        if not created and current_model and agent_def.model_name != current_model:
            agent_def.model_name = current_model
            agent_def.save(update_fields=["model_name"])
        return agent_def

    def investigate_incident(self, incident_id: int) -> Dict[str, Any]:
        """
        Executes a complete end-to-end investigation for a specific factory incident.
        """
        incident = FactoryIncident.objects.select_related("machine", "department", "factory").filter(id=incident_id).first()
        if not incident:
            return {"success": False, "error": f"Incident #{incident_id} not found."}

        machine = incident.machine
        if not machine:
            return {"success": False, "error": f"Incident #{incident_id} has no associated machine."}

        agent_def = self._ensure_agent_definition()

        # Deduplication check: check if an execution is currently in progress
        in_progress = AgentExecution.objects.filter(
            incident=incident, agent=agent_def, status__in=[AgentExecutionStatus.STARTED, AgentExecutionStatus.RUNNING]
        ).first()
        if in_progress:
            return {
                "success": False,
                "message": f"Investigation already running for incident #{incident_id} (Execution {in_progress.execution_id}).",
                "execution_id": str(in_progress.execution_id),
            }

        start_time = timezone.now()

        # 1. Initialize AgentExecution record
        execution = AgentExecution.objects.create(
            agent=agent_def,
            incident=incident,
            trigger_event=f"ANOMALY_INVESTIGATION on {machine.code} ({incident.incident_code})",
            status=AgentExecutionStatus.RUNNING,
        )

        # Transition incident to INVESTIGATING
        if incident.status == IncidentStatus.OPEN:
            incident.status = IncidentStatus.INVESTIGATING
            incident.save(update_fields=["status"])

        try:
            # 2. Gather Evidence using approved tools
            evidence = self._gather_evidence(machine)
            execution.context_payload = evidence
            execution.save(update_fields=["context_payload"])

            # 3. Assemble LLM Prompt
            user_prompt = self._build_user_prompt(incident, machine, evidence)

            # 4. Invoke Configured LLM Provider
            llm_response = self.provider.generate_structured(
                system_prompt=SYSTEM_PROMPT,
                user_prompt=user_prompt,
                schema_description="MachineHealthInvestigationSchema",
            )

            execution.latency_ms = llm_response.latency_ms
            execution.token_count = llm_response.token_count

            # 4. Handle LLM Response & Fallbacks with exact provenance
            provenance = "GEMINI_SUCCESS"
            if llm_response.status == "SUCCESS" and llm_response.structured_json:
                result_json = llm_response.structured_json
                provenance = "GEMINI_SUCCESS" if getattr(llm_response, "provider", "") == "gemini" else "MOCK_AI_SUCCESS"
            else:
                if llm_response.status == "RATE_LIMITED":
                    provenance = "GEMINI_RATE_LIMITED"
                    logger.warning("[MachineHealthAgent] Gemini rate limited (429). Generating deterministic fallback diagnosis.")
                elif llm_response.status == "UNCONFIGURED":
                    provenance = "GEMINI_UNCONFIGURED"
                    logger.info("[MachineHealthAgent] Gemini unconfigured. Generating deterministic fallback diagnosis.")
                else:
                    provenance = "GEMINI_FAILED"
                    logger.warning("[MachineHealthAgent] Gemini inference error (%s). Generating deterministic fallback diagnosis.", llm_response.error_message)

                result_json = self._generate_deterministic_diagnosis(incident, machine, evidence, provenance)

            # 5. Process and Validate Structured Decisions
            decision_obj = self._persist_decision_and_actions(execution, incident, machine, result_json, provenance)

            # 6. Update Execution Status
            execution.status = AgentExecutionStatus.COMPLETED
            execution.execution_summary = (
                f"[{provenance}] Completed investigation for {machine.code}. "
                f"Assessed Severity: {result_json.get('severity_assessment', 'UNKNOWN')}. "
                f"Hypothesis: {incident.root_cause_hypothesis[:120]}"
            )
            execution.completed_at = timezone.now()
            execution.save()

            return {
                "success": True,
                "execution_id": str(execution.execution_id),
                "incident_id": incident.id,
                "machine_code": machine.code,
                "decision_id": decision_obj.id if decision_obj else None,
                "findings": result_json,
                "provenance": provenance,
                "is_live_gemini": provenance == "GEMINI_SUCCESS",
                "latency_ms": execution.latency_ms,
                "token_count": execution.token_count,
            }

        except Exception as exc:
            logger.exception("Error during Machine Health Agent investigation: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Execution exception: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {
                "success": False,
                "execution_id": str(execution.execution_id),
                "error": str(exc),
            }

    def run_cycle(self) -> Dict[str, Any]:
        """
        Scans for pending unresolved incidents and executes autonomous investigations.
        """
        pending_incidents = (
            FactoryIncident.objects.filter(
                status=IncidentStatus.OPEN,
                machine__isnull=False,
            )
            .exclude(agent_executions__status=AgentExecutionStatus.COMPLETED)
            .order_by("-detected_at")[:10]
        )

        investigated_count = 0
        results = []

        for inc in pending_incidents:
            res = self.investigate_incident(inc.id)
            results.append(res)
            if res.get("success"):
                investigated_count += 1

        return {
            "pending_found": len(pending_incidents),
            "investigated_count": investigated_count,
            "results": results,
            "timestamp": timezone.now().isoformat(),
        }

    def _gather_evidence(self, machine: Machine) -> Dict[str, Any]:
        """Queries the 7 approved domain tools to assemble full factual context."""
        return {
            "machine_details": get_machine_details(machine.id),
            "recent_telemetry": get_recent_machine_telemetry(machine.id, limit=15),
            "operating_limits": get_machine_operating_limits(machine.id),
            "maintenance_history": get_machine_maintenance_history(machine.id, limit=5),
            "active_incidents": get_active_machine_incidents(machine.id),
            "affected_production": get_affected_production_orders(machine.id),
            "spare_parts_inventory": get_relevant_spare_parts(machine.id),
        }

    def _build_user_prompt(self, incident: FactoryIncident, machine: Machine, evidence: Dict[str, Any]) -> str:
        """Constructs the prompt containing verified database evidence."""
        return f"""INVESTIGATION TARGET:
Incident Code: {incident.incident_code} (ID #{incident.id})
Summary: {incident.summary}
Category: {incident.category}
Initial Severity: {incident.severity}
Detected At: {incident.detected_at.isoformat()}
Initial Evidence Data: {json.dumps(incident.evidence_data, indent=2)}

FACTUAL DATABASE EVIDENCE RETRIEVED VIA TOOLS:

1. MACHINE SPECIFICATIONS:
{json.dumps(evidence.get('machine_details', {}), indent=2)}

2. OPERATING LIMITS & THRESHOLDS:
{json.dumps(evidence.get('operating_limits', {}), indent=2)}

3. RECENT MACHINE TELEMETRY READINGS (Latest 15 ticks):
{json.dumps(evidence.get('recent_telemetry', {}), indent=2)}

4. RECENT MAINTENANCE WORK ORDERS:
{json.dumps(evidence.get('maintenance_history', {}), indent=2)}

5. AFFECTED ACTIVE PRODUCTION BATCHES:
{json.dumps(evidence.get('affected_production', {}), indent=2)}

6. WAREHOUSE SPARE PARTS & STOCK LEVELS:
{json.dumps(evidence.get('spare_parts_inventory', {}), indent=2)}

Please perform your comprehensive machine health analysis now. Output valid JSON only."""

    def _generate_deterministic_diagnosis(
        self, incident: FactoryIncident, machine: Machine, evidence: Dict[str, Any], provenance: str = "DETERMINISTIC_FALLBACK"
    ) -> Dict[str, Any]:
        """
        Deterministic, rule-grounded industrial fallback diagnostic engine.
        Constructs factual root cause analysis strictly from database evidence when LLM is unavailable or rate-limited.
        """
        recent_tel = evidence.get("recent_telemetry", {}).get("telemetry_history", [])
        latest_tel = recent_tel[0] if recent_tel else {}
        limits = evidence.get("operating_limits", {})

        vib = latest_tel.get("vibration_mms", 0.0)
        max_vib = limits.get("max_vibration_mms", 5.5)
        warn_vib = limits.get("warning_vibration_mms", 4.0)

        temp = latest_tel.get("temperature_c", 0.0)
        max_temp = limits.get("max_temp_c", 85.0)

        facts = [
            f"Machine: {machine.code} ({machine.name}) in {machine.department.name}",
            f"Observed Vibration: {vib} mm/s (Warning Limit: {warn_vib}, Critical Limit: {max_vib})",
            f"Observed Temperature: {temp} °C (Max Limit: {max_temp})",
            f"Operating Speed: {latest_tel.get('speed_rpm', 0.0)} RPM",
        ]

        abnormal_conditions = []
        possible_causes = []

        if vib > max_vib:
            abnormal_conditions.append(f"Severe main bearing drive vibration ({vib} mm/s exceeds critical limit {max_vib} mm/s)")
            possible_causes.append({
                "hypothesis": "Drive shaft rolling element bearing cage deterioration or race spalling",
                "likelihood": "HIGH",
                "confidence_score": 88.0,
            })
            possible_causes.append({
                "hypothesis": "Timing belt tensioner misalignment or dynamic harmonic resonance",
                "likelihood": "MEDIUM",
                "confidence_score": 65.0,
            })
        elif vib > warn_vib:
            abnormal_conditions.append(f"Elevated vibration ({vib} mm/s exceeds warning limit {warn_vib} mm/s)")
            possible_causes.append({
                "hypothesis": "Incipient bearing wear or loose mechanical mounting fasteners",
                "likelihood": "MEDIUM",
                "confidence_score": 75.0,
            })
        else:
            abnormal_conditions.append("Operational variance detected during monitoring cycle")
            possible_causes.append({
                "hypothesis": "General mechanical inspection required",
                "likelihood": "LOW",
                "confidence_score": 60.0,
            })

        if temp > max_temp:
            abnormal_conditions.append(f"Thermal excursion ({temp} °C exceeds threshold {max_temp} °C)")

        severity = "CRITICAL" if vib > max_vib else ("HIGH" if vib > warn_vib else incident.severity)

        return {
            "incident_id": incident.id,
            "machine_code": machine.code,
            "provenance": provenance,
            "observed_abnormal_conditions": abnormal_conditions,
            "verified_sensor_facts": facts,
            "possible_root_causes": possible_causes,
            "missing_information": [
                "Acoustic ultrasonic emission spectrum",
                "Lubrication grease particulate analysis",
            ],
            "recommended_maintenance_checks": [
                f"Inspect drive end bearing for mechanical play, flaking, and lubrication status",
                f"Verify drive belt tension and pulley alignment with dial indicator",
                f"Check mechanical foundation bolts on {machine.code}",
            ],
            "production_impact_considerations": [
                f"Active department: {machine.department.code}. Potential downstream buffer depletion.",
                "Estimated repair downtime: 1.5 to 2.5 hours",
            ],
            "severity_assessment": severity,
            "confidence_explanation": (
                f"Deterministic rule-based diagnosis derived from verified sensor limits: "
                f"vibration {vib} mm/s (limit {max_vib} mm/s) on {machine.code}."
            ),
            "suggested_next_actions": [
                {
                    "action_type": "CREATE_MAINTENANCE_DRAFT",
                    "description": f"Create priority maintenance inspection on {machine.code}",
                    "requires_human_approval": True,
                    "payload": {
                        "priority": "HIGH" if severity == "CRITICAL" else "MEDIUM",
                        "estimated_hours": 1.5,
                        "required_parts": ["SPR-BRG-6204"],
                    },
                },
                {
                    "action_type": "RESERVE_SPARE_PART",
                    "description": f"Propose reservation for 1x 6204-2RS Deep Groove Bearing for {machine.code}",
                    "requires_human_approval": True,
                    "payload": {
                        "part_code": "SPR-BRG-6204",
                        "quantity": 1,
                        "machine_code": machine.code,
                    },
                },
            ],
        }

    def _persist_decision_and_actions(
        self,
        execution: AgentExecution,
        incident: FactoryIncident,
        machine: Machine,
        findings: Dict[str, Any],
        provenance: str = "GEMINI_SUCCESS",
    ) -> AgentDecision:
        """Saves AgentDecision, correlates with FactoryIncident, and queues proposed actions."""
        with transaction.atomic():
            possible_causes = findings.get("possible_root_causes", [])
            top_cause = possible_causes[0].get("hypothesis", "") if possible_causes else "Unknown mechanical deviation"
            confidence = possible_causes[0].get("confidence_score", 85.0) if possible_causes else 85.0

            # 1. Update Incident with AI investigation findings
            hypothesis_prefix = "[AI Root Cause Hypothesis]" if provenance in ["GEMINI_SUCCESS", "MOCK_AI_SUCCESS"] else f"[{provenance} Hypothesis]"
            incident.root_cause_hypothesis = (
                f"{hypothesis_prefix} {top_cause}\n"
                f"Explanation: {findings.get('confidence_explanation', '')}"
            )
            ev = incident.evidence_data or {}
            ev["ai_investigation"] = {
                "execution_id": str(execution.execution_id),
                "provenance": provenance,
                "is_live_gemini": provenance == "GEMINI_SUCCESS",
                "assessed_severity": findings.get("severity_assessment", incident.severity),
                "verified_facts": findings.get("verified_sensor_facts", []),
                "abnormal_conditions": findings.get("observed_abnormal_conditions", []),
                "possible_causes": possible_causes,
                "missing_info": findings.get("missing_information", []),
                "maintenance_checks": findings.get("recommended_maintenance_checks", []),
                "production_impact": findings.get("production_impact_considerations", []),
                "investigated_at": timezone.now().isoformat(),
            }
            incident.evidence_data = ev
            incident.save(update_fields=["root_cause_hypothesis", "evidence_data"])

            # 2. Create AgentDecision record
            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="ROOT_CAUSE_DIAGNOSIS",
                rationale=(
                    f"Provenance: {provenance}\n"
                    f"Observed Anomalies: {', '.join(findings.get('observed_abnormal_conditions', []))}\n\n"
                    f"Root Cause Hypothesis: {top_cause}\n\n"
                    f"Confidence Justification: {findings.get('confidence_explanation', '')}"
                ),
                confidence_score=confidence,
                risk_level="HIGH" if findings.get("severity_assessment") == "CRITICAL" else "MEDIUM",
                requires_human_approval=True,
            )

            # 3. Process suggested next actions through ActionSafetyService
            suggested_actions = findings.get("suggested_next_actions", [])
            for act in suggested_actions:
                ActionSafetyService.propose_action(
                    execution=execution,
                    action_type=act.get("action_type", "CREATE_MAINTENANCE_DRAFT"),
                    description=act.get("description", "Recommended maintenance inspection"),
                    payload=act.get("payload", {}),
                    requires_approval=act.get("requires_human_approval", True),
                )

            return decision
