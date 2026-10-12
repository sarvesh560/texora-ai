"""
Autonomous Inventory & Spare Parts Coordinator Agent for Texora AI.
Cross-references diagnosed machine failures against warehouse stock records,
evaluates safety stock margins, proposes spare-part reservations or procurement requests,
and prevents stock shortages without fabricating part availability.
"""
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
from apps.ai_agents.action_service import ActionSafetyService
from apps.incidents.models import FactoryIncident
from apps.machines.models import Machine
from apps.inventory.models import InventoryItem, SparePartRequirement, InventoryCategory

logger = logging.getLogger(__name__)


class InventoryCoordinatorAgent:
    """
    Autonomous Inventory Coordinator Agent.
    Validates spare parts required for machine recovery against live warehouse records,
    detects shortages, enforces safety stock barriers, and routes reservations through approval gates.
    """

    def __init__(self):
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.INVENTORY,
            defaults={
                "name": "Inventory & Spare Parts Coordinator",
                "description": "Autonomous warehouse inventory evaluator verifying spare parts, safety stock levels, and procurement needs.",
                "model_name": "deterministic-inventory-v1",
                "is_enabled": True,
                "permitted_actions": [
                    "RESERVE_SPARE_PART",
                    "CREATE_PROCUREMENT_REQUEST",
                    "CHECK_STOCK_LEVELS",
                ],
                "sensitivity_threshold": 0.80,
            },
        )
        return agent_def

    def coordinate_inventory(
        self,
        incident_id: int,
        health_diagnosis: Optional[Dict[str, Any]] = None,
        maintenance_recommendation: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Evaluates spare part availability and queues verified reservation/procurement actions.
        """
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
            context_payload={
                "incident_code": incident.incident_code,
                "machine_code": machine.code,
                "health_diagnosis": health_diagnosis or {},
            },
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
            proposed_actions = []
            shortages_detected = []
            unverified_parts = []

            for part_code in candidate_part_codes:
                item = InventoryItem.objects.filter(item_code__iexact=part_code, is_active=True).first()
                if not item:
                    # Search by partial code or name
                    item = InventoryItem.objects.filter(name__icontains=part_code, is_active=True).first()

                if not item:
                    # Part suggested by diagnosis does not exist in warehouse catalog
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
                    # Propose procurement order
                    proc_action = ActionSafetyService.propose_action(
                        execution=execution,
                        action_type="CREATE_PROCUREMENT_REQUEST",
                        description=f"Urgent Spare Part Procurement: {item.name} ({item.item_code}) - Qty: {reorder}",
                        payload={
                            "item_code": item.item_code,
                            "item_name": item.name,
                            "quantity": reorder,
                            "estimated_cost": float(reorder * float(item.unit_cost)),
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
                    # Propose reservation for 1 unit
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

            # 3. Record AgentDecision
            summary_text = (
                f"Evaluated {len(evaluated_parts)} registered spare parts for {machine.code}. "
                f"In-Stock: {len(evaluated_parts) - len(shortages_detected)}, Shortages: {len(shortages_detected)}, "
                f"Unverified: {len(unverified_parts)}. Generated {len(proposed_actions)} approval-gated actions."
            )

            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="INVENTORY_RESERVE",
                rationale=summary_text,
                confidence_score=95.00,
                risk_level="HIGH" if len(shortages_detected) > 0 else "LOW",
                requires_human_approval=True,
            )

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
            }

        except Exception as exc:
            logger.exception("Error in InventoryCoordinatorAgent: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Inventory coordination failed: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {"success": False, "error": str(exc)}
