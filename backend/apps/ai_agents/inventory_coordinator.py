"""
Autonomous Inventory & Spare Parts Coordinator Agent for Texora AI.
AI-assisted inventory reasoning using Google Gemini grounded strictly in live database records,
preventing phantom stock fabrication, validating part compatibility, and enforcing safety stock gates.
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
    validate_inventory_coordination_output,
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
from apps.machines.models import Machine
from apps.inventory.models import InventoryItem, SparePartRequirement, InventoryCategory

logger = logging.getLogger(__name__)

INVENTORY_SYSTEM_PROMPT = """You are the Texora AI Autonomous Inventory & Spare Parts Coordinator Agent for an industrial textile manufacturing plant.
Your mission is to evaluate warehouse inventory levels, reason about part compatibility, assess safety stock buffers, and suggest verified allocation or procurement actions.

STRICT OPERATIONAL CONSTRAINTS:
1. You must NEVER invent stock quantities or create phantom part numbers. Real warehouse stock counts must come strictly from the provided database records.
2. Clearly formulate:
   - suggested_spare_parts: List of objects with part_code, quantity, urgency ("HIGH"/"MEDIUM"), and reason.
   - shortage_warnings: Explicit alerts for parts where stock is depleted or below safety threshold.
   - procurement_recommendations: Priority purchase orders needed to replenish depleted bins.
   - alternative_part_suggestions: Compatible replacement parts only if supported by equipment specifications.
   - safety_stock_evaluation: Qualitative assessment of warehouse reserve margin.
   - confidence_score: Confidence score (10.0 to 99.0).
   - risk_level: "LOW", "MEDIUM", or "HIGH".
3. Return your response exclusively as valid JSON matching the schema."""


class InventoryCoordinatorAgent:
    """
    Autonomous Inventory Coordinator Agent.
    Combines Google Gemini reasoning with live database verification to validate
    spare parts, detect shortages, enforce safety stock barriers, and route reservations through approval gates.
    """

    def __init__(self, provider: Optional[BaseLLMProvider] = None):
        self.provider = provider or get_llm_provider()
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.INVENTORY,
            defaults={
                "name": "Inventory & Spare Parts Coordinator",
                "description": "Autonomous warehouse inventory evaluator verifying spare parts, safety stock levels, and procurement needs.",
                "model_name": "gemini-3.8-flash",
                "is_enabled": True,
                "permitted_actions": [
                    "RESERVE_SPARE_PART",
                    "CREATE_PROCUREMENT_REQUEST",
                    "CHECK_STOCK_LEVELS",
                ],
                "sensitivity_threshold": 0.80,
            },
        )
        if agent_def.model_name == "deterministic-inventory-v1":
            agent_def.model_name = "gemini-3.8-flash"
            agent_def.save(update_fields=["model_name"])
        return agent_def

    def coordinate_inventory(
        self,
        incident_id: int,
        health_diagnosis: Optional[Dict[str, Any]] = None,
        maintenance_recommendation: Optional[Dict[str, Any]] = None,
        force_provider: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Evaluates spare part availability and queues verified reservation/procurement actions.
        Uses Gemini reasoning grounded strictly in real database records.
        """
        if force_provider:
            self.provider = get_llm_provider(force_provider)

        incident = FactoryIncident.objects.select_related("machine", "machine__machine_type").filter(id=incident_id).first()
        if not incident:
            return {"success": False, "error": f"Incident #{incident_id} not found."}

        machine = incident.machine
        if not machine:
            return {"success": False, "error": f"Incident #{incident_id} has no associated machine."}

        agent_def = self._ensure_agent_definition()

        execution = AgentExecution.objects.create(
            agent=agent_def,
            incident=incident,
            trigger_event=f"INVENTORY_COORDINATION on {machine.code} ({incident.incident_code})",
            status=AgentExecutionStatus.RUNNING,
        )

        try:
            # 1. Identify Candidate Parts from DB requirements & Diagnosis
            candidate_part_codes = set()

            # Check explicit suggestions in LLM actions/diagnosis
            for action in (health_diagnosis or {}).get("suggested_next_actions", []):
                req_parts = action.get("payload", {}).get("required_parts", [])
                if isinstance(req_parts, list):
                    for p in req_parts:
                        if isinstance(p, str):
                            candidate_part_codes.add(p.strip())

            # Check SparePartRequirement table for machine type
            machine_type = machine.machine_type
            if machine_type:
                reqs = SparePartRequirement.objects.filter(machine_type=machine_type).select_related("item")
                for r in reqs:
                    candidate_part_codes.add(r.item.item_code)

            # Fallback based on machine department / type if empty
            if not candidate_part_codes:
                if "WEV" in machine.code or "loom" in str(machine.name).lower():
                    candidate_part_codes.update(["SPR-BRG-6204", "SPR-BELT-SPN"])
                elif "SPN" in machine.code:
                    candidate_part_codes.update(["SPR-BRG-6204", "SPR-BELT-SPN"])
                elif "KNT" in machine.code:
                    candidate_part_codes.add("SPR-NDL-KNIT")

            # 2. Evaluate each candidate part against real database records
            evaluated_parts = []
            shortages_detected = []
            unverified_parts = []

            for part_code in candidate_part_codes:
                item = InventoryItem.objects.filter(item_code__iexact=part_code, is_active=True).first()
                if not item:
                    item = InventoryItem.objects.filter(name__icontains=part_code, is_active=True).first()

                if not item:
                    unverified_parts.append({
                        "part_code": part_code,
                        "status": "UNVERIFIED_IN_CATALOG",
                        "warning": f"Part '{part_code}' is not registered in the Texora warehouse inventory system.",
                    })
                    continue

                curr_stock = float(item.current_stock)
                min_stock = float(item.minimum_safety_stock)
                reorder = float(item.reorder_point)

                is_shortage = curr_stock < 1.0
                is_low_stock = curr_stock <= min_stock

                part_status = "OUT_OF_STOCK" if is_shortage else ("LOW_STOCK" if is_low_stock else "IN_STOCK")

                part_info = {
                    "item_id": item.id,
                    "item_code": item.item_code,
                    "name": item.name,
                    "category": item.category,
                    "current_stock": curr_stock,
                    "minimum_safety_stock": min_stock,
                    "reorder_point": reorder,
                    "unit": item.unit,
                    "unit_cost": float(item.unit_cost),
                    "location_shelf": item.location_shelf,
                    "status": part_status,
                }
                evaluated_parts.append(part_info)

                if is_shortage:
                    shortages_detected.append(part_info)

            # 3. Assemble Gemini Prompt with verified database evidence
            evidence_context = {
                "machine_code": machine.code,
                "incident_severity": incident.severity,
                "diagnosed_root_cause": (health_diagnosis or {}).get("possible_root_causes", [{}])[0].get("hypothesis", incident.root_cause_hypothesis),
                "maintenance_checklist": (maintenance_recommendation or {}).get("inspection_steps", []),
                "warehouse_inventory_records": evaluated_parts,
                "unverified_parts": unverified_parts,
            }

            user_prompt = f"""INVENTORY EVALUATION REQUEST:
Machine: {machine.code} ({machine.name})
Incident Summary: {incident.summary}
Diagnosed Problem: {evidence_context['diagnosed_root_cause']}

VERIFIED REAL WAREHOUSE INVENTORY RECORDS:
{json.dumps(evaluated_parts, indent=2)}

UNVERIFIED COMPONENT ALERTS:
{json.dumps(unverified_parts, indent=2)}

Evaluate part adequacy, identify shortages, and provide structured inventory recommendations. Return valid JSON only."""

            # 4. Invoke LLM Provider
            llm_response = self.provider.generate_structured(
                system_prompt=INVENTORY_SYSTEM_PROMPT,
                user_prompt=user_prompt,
                schema_description="InventoryCoordinationSchema",
            )

            execution.latency_ms = llm_response.latency_ms
            execution.token_count = llm_response.token_count

            if llm_response.status == "SUCCESS" and llm_response.structured_json:
                ai_output = validate_inventory_coordination_output(llm_response.structured_json, machine.code)
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
                    "suggested_spare_parts": [{"part_code": p["item_code"], "quantity": 1, "urgency": "HIGH"} for p in evaluated_parts if p["status"] != "OUT_OF_STOCK"],
                    "shortage_warnings": [f"Stock depleted for {s['item_code']}" for s in shortages_detected],
                    "procurement_recommendations": [f"Procure {s['item_code']} immediately" for s in shortages_detected],
                    "alternative_part_suggestions": [],
                    "confidence_score": 95.0,
                    "risk_level": "HIGH" if shortages_detected else "LOW",
                    "safety_stock_evaluation": "Evaluated against warehouse safety stock thresholds.",
                }

            # 5. Enforce deterministic action creation based on actual database catalog
            proposed_actions = []
            for part_info in evaluated_parts:
                item = InventoryItem.objects.get(id=part_info["item_id"])
                if part_info["status"] == "OUT_OF_STOCK":
                    proc_action = ActionSafetyService.propose_action(
                        execution=execution,
                        action_type="CREATE_PROCUREMENT_REQUEST",
                        description=f"Urgent Spare Part Procurement: {item.name} ({item.item_code}) - Qty: {item.reorder_point}",
                        payload={
                            "item_code": item.item_code,
                            "item_name": item.name,
                            "quantity": float(item.reorder_point),
                            "estimated_cost": float(item.reorder_point * item.unit_cost),
                            "reason": f"Stock depleted during incident {incident.incident_code} on {machine.code}",
                        },
                        requires_approval=True,
                    )
                    proposed_actions.append({
                        "action_id": proc_action.id,
                        "action_type": "CREATE_PROCUREMENT_REQUEST",
                        "item_code": item.item_code,
                        "status": proc_action.status,
                    })
                else:
                    res_action = ActionSafetyService.propose_action(
                        execution=execution,
                        action_type="RESERVE_SPARE_PART",
                        description=f"Reserve 1x {item.name} ({item.item_code}) from {item.location_shelf}",
                        payload={
                            "part_code": item.item_code,
                            "item_id": item.id,
                            "quantity": 1,
                            "machine_code": machine.code,
                            "location_shelf": item.location_shelf,
                            "unit_cost": float(item.unit_cost),
                        },
                        requires_approval=True,
                    )
                    proposed_actions.append({
                        "action_id": res_action.id,
                        "action_type": "RESERVE_SPARE_PART",
                        "item_code": item.item_code,
                        "status": res_action.status,
                    })

            # 6. Record AgentDecision
            summary_text = (
                f"[{reasoning_source}] Evaluated {len(evaluated_parts)} registered spare parts for {machine.code}. "
                f"In-Stock: {len(evaluated_parts) - len(shortages_detected)}, Shortages: {len(shortages_detected)}, "
                f"Unverified: {len(unverified_parts)}. Generated {len(proposed_actions)} approval-gated actions."
            )

            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="INVENTORY_RESERVE",
                rationale=(
                    f"{summary_text}\nSafety Stock Evaluation: {ai_output['safety_stock_evaluation']}. "
                    f"Shortages: {len(ai_output['shortage_warnings'])}."
                ),
                confidence_score=ai_output["confidence_score"],
                risk_level=ai_output["risk_level"],
                requires_human_approval=True,
            )

            # 7. Store Uniform Metadata Envelope
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
                "evaluated_parts": evaluated_parts,
                "proposed_actions": proposed_actions,
                "shortages_count": len(shortages_detected),
                "unverified_parts": unverified_parts,
                "summary": summary_text,
                "reasoning_source": reasoning_source,
                "provider_attempt_status": provider_attempt_status,
                "ai_output": ai_output,
            }

        except Exception as exc:
            logger.exception("Error in InventoryCoordinatorAgent: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Inventory coordination failed: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {"success": False, "error": str(exc)}
