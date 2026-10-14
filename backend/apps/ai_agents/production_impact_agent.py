"""
Autonomous Production Impact & Order Rescheduling Agent for Texora AI.
AI-assisted production disruption evaluation using Google Gemini with deterministic
throughput loss calculations, real batch verification, and manager approval gates.
"""
import os
import json
import logging
from typing import Dict, Any, List, Optional
from datetime import timedelta
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
    validate_production_impact_output,
    build_metadata_envelope,
    PROVENANCE_GROQ_LIVE,
    PROVENANCE_GEMINI_LIVE,
    PROVENANCE_DETERMINISTIC_FALLBACK,
    PROVENANCE_MOCK_SUCCESS,
    PROVENANCE_PROVIDER_RATE_LIMITED,
    PROVENANCE_PROVIDER_UNAVAILABLE,
)
from apps.ai_agents.action_service import ActionSafetyService
from apps.incidents.models import FactoryIncident
from apps.machines.models import Machine, MachineStatus
from apps.production.models import ProductionBatch, ProductionOrder, OrderStatus, OrderPriority
from apps.production.capacity_engine import CapacityIntelligenceEngine

logger = logging.getLogger(__name__)

PRODUCTION_SYSTEM_PROMPT = """You are the Texora AI Autonomous Production Impact & Order Rescheduling Agent for an industrial textile manufacturing plant.
Your mission is to analyze active production schedules, quantify the operational disruption caused by machinery downtime, and synthesize mitigation and rerouting recommendations.

STRICT OPERATIONAL RULES:
1. All numerical quantities (throughput loss, batch sizes, due dates) must be grounded strictly in the provided database context. Do not invent orders or machine codes.
2. Clearly formulate:
   - production_disruption_explanation: Clear narrative of production and client delivery exposure.
   - suggested_production_adjustments: Pragmatic manufacturing adjustments (e.g., lot-size adjustments, priority shifts).
   - recommended_alternate_machines: List of objects with machine_code, rationale, and capacity_fit ("HIGH"/"MODERATE").
   - recovery_plan: Step-by-step sequence to return production to baseline schedule.
   - operational_consequences_summary: Executive summary of delivery risks.
   - confidence_score: Confidence score (10.0 to 99.0).
   - risk_level: "LOW", "MEDIUM", or "HIGH".
3. Return your response exclusively as valid JSON matching the schema."""


class ProductionImpactAgent:
    """
    Autonomous Production Impact Agent.
    Combines Google Gemini reasoning with deterministic manufacturing calculations
    to quantify operational fallout, identify threatened orders, and propose batch rerouting through approval gates.
    """

    def __init__(self, provider: Optional[BaseLLMProvider] = None):
        self.provider = provider or get_llm_provider()
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.PRODUCTION_IMPACT,
            defaults={
                "name": "Production Rescheduling & Impact Agent",
                "description": "Autonomous manufacturing impact analyst assessing batch delays, capacity buffers, and alternate machine rerouting.",
                "model_name": "gemini-3.8-flash",
                "is_enabled": True,
                "permitted_actions": [
                    "REROUTE_PRODUCTION_BATCH",
                    "PAUSE_PRODUCTION_BATCH",
                    "CALCULATE_CAPACITY_BUFFER",
                ],
                "sensitivity_threshold": 0.85,
            },
        )
        if agent_def.model_name == "deterministic-production-v1":
            agent_def.model_name = "gemini-3.8-flash"
            agent_def.save(update_fields=["model_name"])
        return agent_def

    def evaluate_production_impact(
        self,
        incident_id: int,
        estimated_downtime_hours: float = 1.5,
        health_diagnosis: Optional[Dict[str, Any]] = None,
        maintenance_recommendation: Optional[Dict[str, Any]] = None,
        inventory_assessment: Optional[Dict[str, Any]] = None,
        force_provider: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Assesses live production batches on the impaired machine and proposes mitigation actions
        using Gemini reasoning grounded in real production database schedules.
        """
        if force_provider:
            self.provider = get_llm_provider(force_provider)

        incident = FactoryIncident.objects.select_related("machine", "department").filter(id=incident_id).first()
        if not incident:
            return {"success": False, "error": f"Incident #{incident_id} not found."}

        machine = incident.machine
        if not machine:
            return {"success": False, "error": f"Incident #{incident_id} has no associated machine."}

        agent_def = self._ensure_agent_definition()

        execution = AgentExecution.objects.create(
            agent=agent_def,
            incident=incident,
            trigger_event=f"PRODUCTION_IMPACT_ANALYSIS on {machine.code} ({incident.incident_code})",
            status=AgentExecutionStatus.RUNNING,
        )

        try:
            # 1. Deterministic Calculation via CapacityIntelligenceEngine
            assessment = CapacityIntelligenceEngine.evaluate_machine_breakdown_impact(
                machine=machine,
                estimated_downtime_hours=estimated_downtime_hours,
                incident=incident,
            )
            estimated_loss_units = float(assessment.output_quantity_at_risk)
            deterministic_loss_inr = float(assessment.deterministic_loss_inr)
            batches_data = assessment.affected_batches
            alternate_candidates = assessment.alternate_capacities
            all_affected_orders = assessment.affected_orders
            orders_at_risk = [o for o in all_affected_orders if o.get("is_at_risk")]

            # Query real batches for possible rerouting action
            batches = ProductionBatch.objects.filter(
                machine=machine, status__in=["RUNNING", "STAGED", "PAUSED"]
            ).select_related("production_order", "production_order__department")

            # 2. Assemble Evidence Context
            evidence_context = {
                "machine_code": machine.code,
                "incident_severity": incident.severity,
                "estimated_downtime_hours": estimated_downtime_hours,
                "estimated_loss_units": estimated_loss_units,
                "deterministic_loss_inr": deterministic_loss_inr,
                "active_batches_count": len(batches_data),
                "orders_at_risk_count": len(orders_at_risk),
                "orders_at_risk": orders_at_risk,
                "all_affected_orders": all_affected_orders,
                "alternate_machines_available": alternate_candidates,
                "assessment_code": assessment.assessment_code,
            }

            user_prompt = f"""PRODUCTION IMPACT EVALUATION REQUEST:
Impaired Machine: {machine.code} ({machine.name})
Estimated Repair Downtime: {estimated_downtime_hours} hours
Throughput Loss Calculation: ~{estimated_loss_units} units

ACTIVE PRODUCTION BATCHES ON MACHINE:
{json.dumps(batches_data, indent=2)}

THREATENED CUSTOMER ORDERS:
{json.dumps(orders_at_risk, indent=2)}

DISCOVERED COMPATIBLE ALTERNATE MACHINERY:
{json.dumps(alternate_candidates, indent=2)}

Evaluate schedule fallout, formulate production adjustments, and specify a recovery plan. Return valid JSON only."""

            # 5. Invoke LLM Provider
            llm_response = self.provider.generate_structured(
                system_prompt=PRODUCTION_SYSTEM_PROMPT,
                user_prompt=user_prompt,
                schema_description="ProductionImpactSchema",
            )

            execution.latency_ms = llm_response.latency_ms
            execution.token_count = llm_response.token_count

            if llm_response.status == "SUCCESS" and llm_response.structured_json:
                ai_output = validate_production_impact_output(llm_response.structured_json, machine.code)
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
                ai_output = {
                    "machine_code": machine.code,
                    "production_disruption_explanation": f"Impairment on {machine.code} induces ~{estimated_loss_units} units lost output over {estimated_downtime_hours}h downtime.",
                    "suggested_production_adjustments": [
                        "Prioritize critical batches upon machine recovery",
                        "Stage backup bobbin spools to minimize post-restart setup lag",
                    ],
                    "recommended_alternate_machines": [
                        {"machine_code": ac["machine_code"], "rationale": "Compatible department capacity", "capacity_fit": ac["available_capacity"]}
                        for ac in alternate_candidates[:2]
                    ],
                    "recovery_plan": [
                        f"Complete maintenance on {machine.code} within {estimated_downtime_hours}h",
                        "Verify post-repair telemetry normalization",
                        "Resume paused batch with nominal speed verification",
                    ],
                    "operational_consequences_summary": f"Estimated output deficit: {estimated_loss_units} units. Customer orders at risk: {len(orders_at_risk)}.",
                    "confidence_score": 92.0,
                    "risk_level": "HIGH" if len(orders_at_risk) > 0 else "LOW",
                }

            # 6. Propose Rerouting Action if At-Risk Batches and Alternates exist
            proposed_actions = []
            if orders_at_risk and alternate_candidates:
                target_alt = alternate_candidates[0]
                target_batch = batches[0]

                reroute_action = ActionSafetyService.propose_action(
                    execution=execution,
                    action_type="REROUTE_PRODUCTION_BATCH",
                    description=(
                        f"Reroute Batch {target_batch.batch_number} (Order {target_batch.production_order.order_number}) "
                        f"from {machine.code} to {target_alt['machine_code']} ({target_alt['machine_name']})"
                    ),
                    payload={
                        "batch_id": target_batch.id,
                        "batch_number": target_batch.batch_number,
                        "order_number": target_batch.production_order.order_number,
                        "source_machine_code": machine.code,
                        "target_machine_id": target_alt["machine_id"],
                        "target_machine_code": target_alt["machine_code"],
                        "client_name": target_batch.production_order.client_name,
                        "justification": f"Mitigate delivery deadline risk during {estimated_downtime_hours}h repair on {machine.code}",
                    },
                    requires_approval=True,
                )
                proposed_actions.append({
                    "action_id": reroute_action.id,
                    "action_type": "REROUTE_PRODUCTION_BATCH",
                    "status": reroute_action.status,
                    "target_machine": target_alt["machine_code"],
                })

            # 7. Persist AgentDecision
            summary_text = (
                f"[{reasoning_source}] Evaluated {len(batches_data)} active batches on {machine.code}. "
                f"Estimated Downtime: {estimated_downtime_hours}h (Loss: ~{estimated_loss_units} units). "
                f"Orders at Risk: {len(orders_at_risk)}. Alternate Machines Available: {len(alternate_candidates)}."
            )

            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="PRODUCTION_REROUTE",
                rationale=(
                    f"{summary_text}\n"
                    f"Disruption Analysis: {ai_output['production_disruption_explanation']}\n"
                    f"Consequences: {ai_output['operational_consequences_summary']}"
                ),
                confidence_score=ai_output["confidence_score"],
                risk_level=ai_output["risk_level"],
                requires_human_approval=True,
            )

            # Update ProductionImpactAssessment with AI narrative and recommendations
            if ai_output.get("production_disruption_explanation"):
                assessment.ai_explanation = ai_output["production_disruption_explanation"]
            recs = ai_output.get("recommended_next_steps") or ai_output.get("suggested_production_adjustments") or []
            if recs:
                assessment.recommendations = recs
            assessment.save(update_fields=["ai_explanation", "recommendations"])

            # 8. Store Uniform Metadata Envelope
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
            execution.execution_summary = summary_text
            execution.completed_at = timezone.now()
            execution.save()

            return {
                "success": True,
                "execution_id": str(execution.execution_id),
                "assessment_id": assessment.id,
                "assessment_code": assessment.assessment_code,
                "active_batches": batches_data,
                "orders_at_risk": orders_at_risk,
                "all_affected_orders": all_affected_orders,
                "alternate_machines": alternate_candidates,
                "estimated_loss_units": estimated_loss_units,
                "deterministic_loss_inr": deterministic_loss_inr,
                "proposed_actions": proposed_actions,
                "summary": summary_text,
                "reasoning_source": reasoning_source,
                "provider_attempt_status": provider_attempt_status,
                "ai_output": ai_output,
            }

        except Exception as exc:
            logger.exception("Error in ProductionImpactAgent: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Production impact analysis failed: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {"success": False, "error": str(exc)}
