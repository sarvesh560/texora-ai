"""
Autonomous Maintenance Coordinator Agent for Texora AI.
AI-assisted maintenance planning using Google Gemini with deterministic safety barriers,
technician labor estimations, sensor-guided inspection protocols, and manager approval gates.
"""
import os
import json
import logging
from typing import Dict, Any, List, Optional
from django.db import transaction
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
from apps.ai_agents.schemas import (
    validate_maintenance_coordination_output,
    build_metadata_envelope,
    PROVENANCE_GROQ_LIVE,
    PROVENANCE_GEMINI_LIVE,
    PROVENANCE_DETERMINISTIC_FALLBACK,
    PROVENANCE_MOCK_SUCCESS,
    PROVENANCE_PROVIDER_RATE_LIMITED,
    PROVENANCE_PROVIDER_UNAVAILABLE,
)
from apps.ai_agents.action_service import ActionSafetyService
from apps.incidents.models import FactoryIncident, IncidentStatus, IncidentSeverity
from apps.machines.models import Machine
from apps.maintenance.models import MaintenanceTicket, MaintenanceHistory, TicketPriority, TicketStatus

logger = logging.getLogger(__name__)

MAINTENANCE_SYSTEM_PROMPT = """You are the Texora AI Autonomous Maintenance Coordinator Agent for an industrial textile manufacturing plant.
Your mission is to evaluate diagnosed machinery incidents and synthesize rigorous, safe maintenance work order recommendations.

OPERATIONAL INSTRUCTIONS:
1. Ground your inspection protocols and labor hours in the machine type, fault hypotheses, and historical maintenance patterns.
2. Clearly formulate:
   - recommended_inspection_checklist: Step-by-step diagnostic inspection tasks.
   - suggested_repair_approach: Detailed physical repair procedure.
   - required_skills: Technical certifications and mechanical/electrical competencies.
   - estimated_maintenance_duration_hours: Realistic labor hours (0.5 to 8.0).
   - safety_considerations: Critical Lockout/Tagout (LOTO) and personal safety barriers.
   - escalation_recommendations: Trigger conditions requiring specialist vendor escalation.
   - confidence_score: Numeric confidence (10.0 to 99.0).
   - risk_level: "LOW", "MEDIUM", or "HIGH".
3. Return your response exclusively as valid JSON matching the schema."""


class MaintenanceCoordinatorAgent:
    """
    Autonomous Maintenance Coordinator Agent.
    Combines Google Gemini reasoning with deterministic industrial safety checks
    to propose work orders, inspection protocols, and labor hours through human approval gates.
    """

    def __init__(self, provider: Optional[BaseLLMProvider] = None):
        self.provider = provider or get_llm_provider()
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.MAINTENANCE,
            defaults={
                "name": "Maintenance & Work Order Coordinator",
                "description": "Autonomous maintenance planner proposing inspection protocols, labor hours, and technician dispatch.",
                "model_name": "gemini-3.8-flash",
                "is_enabled": True,
                "permitted_actions": [
                    "CREATE_MAINTENANCE_TICKET",
                    "SCHEDULE_INSPECTION",
                    "ASSIGN_TECHNICIAN",
                ],
                "sensitivity_threshold": 0.75,
            },
        )
        if agent_def.model_name == "deterministic-maintenance-v1":
            agent_def.model_name = "gemini-3.8-flash"
            agent_def.save(update_fields=["model_name"])
        return agent_def

    def coordinate_maintenance(
        self,
        incident_id: int,
        health_diagnosis: Optional[Dict[str, Any]] = None,
        force_provider: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Coordinates maintenance actions for a specific factory incident using Gemini AI
        with deterministic safety validation.
        """
        if force_provider:
            self.provider = get_llm_provider(force_provider)

        incident = FactoryIncident.objects.select_related("machine", "department", "machine__machine_type").filter(id=incident_id).first()
        if not incident:
            return {"success": False, "error": f"Incident #{incident_id} not found."}

        machine = incident.machine
        if not machine:
            return {"success": False, "error": f"Incident #{incident_id} has no associated machine."}

        agent_def = self._ensure_agent_definition()

        # 1. Start AgentExecution
        execution = AgentExecution.objects.create(
            agent=agent_def,
            incident=incident,
            trigger_event=f"MAINTENANCE_COORDINATION on {machine.code} ({incident.incident_code})",
            status=AgentExecutionStatus.RUNNING,
        )

        try:
            # 2. Check active maintenance tickets for this incident (Deduplication Guard)
            active_ticket = MaintenanceTicket.objects.filter(
                incident_reference=incident.incident_code,
                status__in=[
                    TicketStatus.CREATED,
                    TicketStatus.OPEN,
                    TicketStatus.ASSIGNED,
                    TicketStatus.ACCEPTED,
                    TicketStatus.IN_PROGRESS,
                    TicketStatus.INSPECTION_IN_PROGRESS,
                    TicketStatus.REPAIR_IN_PROGRESS,
                    TicketStatus.PENDING_PARTS,
                ],
            ).first()

            if active_ticket:
                execution.status = AgentExecutionStatus.COMPLETED
                execution.execution_summary = (
                    f"Active maintenance ticket {active_ticket.ticket_number} already in progress for {machine.code}. "
                    f"Status: {active_ticket.status}."
                )
                execution.context_payload = build_metadata_envelope(
                    agent_name=agent_def.name,
                    incident_id=incident.id,
                    machine_code=machine.code,
                    model_name=getattr(self.provider, "model_name", "deterministic"),
                    provider_attempt_status="DEDUPLICATION_GUARD",
                    reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                    latency_ms=0,
                    token_count=0,
                    execution_errors="",
                    input_context={"existing_ticket": active_ticket.ticket_number},
                    structured_output={"status": active_ticket.status},
                    provider_name="deterministic",
                )
                execution.completed_at = timezone.now()
                execution.save()

                return {
                    "success": True,
                    "execution_id": str(execution.execution_id),
                    "duplicate_prevented": True,
                    "existing_ticket_number": active_ticket.ticket_number,
                    "existing_ticket_status": active_ticket.status,
                    "message": f"Active ticket {active_ticket.ticket_number} already open for {machine.code}.",
                    "priority": active_ticket.priority,
                    "assigned_technician": active_ticket.assigned_technician,
                    "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                    "provider_attempt_status": "DEDUPLICATION_GUARD",
                }

            # 3. Retrieve Maintenance History
            past_history = MaintenanceHistory.objects.filter(machine=machine).order_by("-date_performed")[:5]
            history_summary = [
                {
                    "type": h.maintenance_type,
                    "summary": h.summary,
                    "date": h.date_performed.isoformat() if h.date_performed else None,
                    "downtime_minutes": h.downtime_minutes,
                }
                for h in past_history
            ]

            # 4. Assemble Evidence & Prompt
            hypotheses = (health_diagnosis or {}).get("possible_root_causes", [])
            primary_hypothesis = hypotheses[0].get("hypothesis") if hypotheses else incident.root_cause_hypothesis

            dept_name = machine.department.name if machine.department else "Textile Operations"
            assigned_team = f"{dept_name} Fast-Response Mechanical Team"

            evidence_context = {
                "machine_code": machine.code,
                "machine_name": machine.name,
                "machine_type": machine.machine_type.name if machine.machine_type else "Industrial Textile Equipment",
                "department": dept_name,
                "incident_severity": incident.severity,
                "incident_summary": incident.summary,
                "primary_hypothesis": primary_hypothesis,
                "health_findings": health_diagnosis or {},
                "maintenance_history": history_summary,
            }

            user_prompt = f"""MAINTENANCE EVALUATION REQUEST:
Target Machine: {machine.code} ({machine.name})
Department: {dept_name}
Incident Summary: {incident.summary}
Severity: {incident.severity}
Diagnosed Root Cause: {primary_hypothesis}

DIAGNOSTIC EVIDENCE FROM HEALTH AGENT:
{json.dumps(health_diagnosis or {}, indent=2)}

PAST MAINTENANCE HISTORY:
{json.dumps(history_summary, indent=2)}

Synthesize a comprehensive maintenance plan now. Return valid JSON only."""

            # 5. Invoke LLM Provider
            llm_response = self.provider.generate_structured(
                system_prompt=MAINTENANCE_SYSTEM_PROMPT,
                user_prompt=user_prompt,
                schema_description="MaintenanceCoordinationSchema",
            )

            execution.latency_ms = llm_response.latency_ms
            execution.token_count = llm_response.token_count

            # 6. Validate Output & Fallback Routing
            if llm_response.status == "SUCCESS" and llm_response.structured_json:
                ai_output = validate_maintenance_coordination_output(llm_response.structured_json, machine.code)
                prov = getattr(llm_response, "provider", "")
                if prov == "groq" or getattr(llm_response, "reasoning_source", "") == PROVENANCE_GROQ_LIVE:
                    reasoning_source = PROVENANCE_GROQ_LIVE
                elif prov == "gemini" or getattr(llm_response, "reasoning_source", "") == PROVENANCE_GEMINI_LIVE:
                    reasoning_source = PROVENANCE_GEMINI_LIVE
                elif prov == "mock":
                    reasoning_source = PROVENANCE_MOCK_SUCCESS
                else:
                    reasoning_source = getattr(llm_response, "reasoning_source", PROVENANCE_GROQ_LIVE)
                provider_attempt_status = llm_response.provider_attempt_status or reasoning_source
            else:
                provider_attempt_status = llm_response.provider_attempt_status or PROVENANCE_DETERMINISTIC_FALLBACK
                reasoning_source = PROVENANCE_DETERMINISTIC_FALLBACK
                logger.info(
                    "[MaintenanceCoordinator] Provider status '%s'. Using deterministic maintenance protocol.",
                    provider_attempt_status,
                )
                custom_checks = health_diagnosis.get("recommended_maintenance_checks") if isinstance(health_diagnosis, dict) else None
                ai_output = self._deterministic_fallback_plan(machine, incident, primary_hypothesis, custom_checks=custom_checks)

            inspection_steps = ai_output["recommended_inspection_checklist"]
            estimated_hours = ai_output["estimated_maintenance_duration_hours"]

            # 7. Determine Priority from Incident Severity
            if incident.severity == IncidentSeverity.CRITICAL:
                ticket_priority = TicketPriority.CRITICAL
            elif incident.severity == IncidentSeverity.HIGH:
                ticket_priority = TicketPriority.HIGH
            else:
                ticket_priority = TicketPriority.MEDIUM

            # 8. Propose Work Order Creation via ActionSafetyService (requires manager approval)
            action_payload = {
                "machine_code": machine.code,
                "incident_code": incident.incident_code,
                "title": f"Corrective Repair: {machine.code} ({primary_hypothesis[:80] if primary_hypothesis else 'Telemetry Anomaly'})",
                "fault_category": "MECHANICAL_DRIVE_BEARING" if "bearing" in str(primary_hypothesis).lower() else "GENERAL_MALFUNCTION",
                "priority": ticket_priority,
                "estimated_hours": estimated_hours,
                "assigned_technician": assigned_team,
                "inspection_checklist": inspection_steps,
                "suggested_repair_approach": ai_output["suggested_repair_approach"],
                "required_skills": ai_output["required_skills"],
                "safety_considerations": ai_output["safety_considerations"],
                "primary_hypothesis": primary_hypothesis,
            }

            action = ActionSafetyService.propose_action(
                execution=execution,
                action_type="CREATE_MAINTENANCE_TICKET",
                description=f"Create {ticket_priority} Maintenance Work Order for {machine.code} ({machine.name})",
                payload=action_payload,
                requires_approval=True,
            )

            # 9. Record AgentDecision
            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="MAINTENANCE_DISPATCH",
                rationale=(
                    f"[{reasoning_source}] Evaluated incident {incident.incident_code} on {machine.code}. "
                    f"Primary fault: {primary_hypothesis}. "
                    f"Recommended approach: {ai_output['suggested_repair_approach']}. "
                    f"Assigned team: {assigned_team}. Checklist: {len(inspection_steps)} steps. "
                    f"Estimated labor: {estimated_hours}h. Requires manager approval."
                ),
                confidence_score=ai_output["confidence_score"],
                risk_level=ai_output["risk_level"],
                requires_human_approval=True,
            )

            # 10. Store Uniform Metadata Envelope
            envelope = build_metadata_envelope(
                agent_name=agent_def.name,
                incident_id=incident.id,
                machine_code=machine.code,
                model_name=getattr(llm_response, "model", getattr(self.provider, "model_name", "qwen/qwen3.8-27b")),
                provider_attempt_status=provider_attempt_status,
                reasoning_source=reasoning_source,
                latency_ms=execution.latency_ms,
                token_count=execution.token_count,
                execution_errors=llm_response.error_message,
                input_context=evidence_context,
                structured_output=ai_output,
                provider_name=getattr(llm_response, "provider", "groq"),
            )
            execution.context_payload = envelope

            execution.status = AgentExecutionStatus.COMPLETED
            execution.execution_summary = (
                f"[{reasoning_source} / {provider_attempt_status}] Proposed {ticket_priority} Work Order for {machine.code}. "
                f"Assigned: {assigned_team}. Labor: {estimated_hours}h. Action ID {action.id} queued for approval."
            )
            execution.completed_at = timezone.now()
            execution.save()

            approval_req = getattr(action, "approval_request", None)

            return {
                "success": True,
                "execution_id": str(execution.execution_id),
                "duplicate_prevented": False,
                "proposed_ticket": action_payload,
                "inspection_steps": inspection_steps,
                "priority": ticket_priority,
                "assigned_technician": assigned_team,
                "estimated_hours": estimated_hours,
                "action_id": action.id,
                "approval_code": approval_req.approval_code if approval_req else None,
                "history_count": len(history_summary),
                "reasoning_source": reasoning_source,
                "provider_attempt_status": provider_attempt_status,
                "ai_output": ai_output,
            }

        except Exception as exc:
            logger.exception("Error in MaintenanceCoordinatorAgent: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Maintenance coordination failed: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {"success": False, "error": str(exc)}

    def _deterministic_fallback_plan(
        self, machine: Machine, incident: FactoryIncident, primary_hypothesis: str, custom_checks: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Deterministic industrial maintenance protocol used as fallback."""
        if custom_checks and isinstance(custom_checks, list) and len(custom_checks) > 0:
            steps = [str(x) for x in custom_checks if x]
            repair = f"Perform sensor-guided inspection and defect correction according to findings: {', '.join(steps[:2])}."
        elif "vibration" in incident.summary.lower() or "bearing" in str(primary_hypothesis).lower():
            steps = [
                "Perform dial indicator runout check on drive shaft bearing",
                "Inspect bearing housing 6309 for race flaking and cage play",
                "Verify drive belt tension and pulley alignment",
                "Replenish synthetic high-temperature lithium grease",
            ]
            repair = "Disassemble drive end housing, extract damaged bearing with hydraulic puller, induction-heat and press new bearing, torque locking ring to 45 Nm."
        elif "thermal" in incident.summary.lower() or "temperature" in incident.summary.lower():
            steps = [
                "Measure thermal gradient across motor stator using infrared pyrometer",
                "Inspect ventilation ducting for textile lint accumulation",
                "Verify winding insulation resistance with megohmmeter",
            ]
            repair = "Clear lint blockage from air passages, test stator cooling fan, re-verify thermal gradient."
        else:
            steps = [
                "Perform visual inspection and sensor calibration check",
                "Inspect mechanical linkages and drive components for play",
            ]
            repair = "Inspect and calibrate telemetry sensors, verify mechanical alignment."

        return {
            "machine_code": machine.code,
            "recommended_inspection_checklist": steps,
            "suggested_repair_approach": repair,
            "required_skills": ["Precision Mechanical Alignment", "Bearing Replacement", "Textile Machinery Diagnostics"],
            "estimated_maintenance_duration_hours": 1.5 if incident.severity == IncidentSeverity.CRITICAL else 1.0,
            "safety_considerations": [
                "Lockout/Tagout (LOTO) electrical main drive switch before touching mechanical assemblies",
                "Verify shaft rotational standstill with optical tachometer prior to belt guard removal",
            ],
            "escalation_recommendations": [
                "Escalate to OEM service engineer if shaft runout exceeds 0.05 mm after bearing press-fit"
            ],
            "confidence_score": 88.50,
            "risk_level": "HIGH" if incident.severity == IncidentSeverity.CRITICAL else "MEDIUM",
        }
