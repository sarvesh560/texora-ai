"""
Autonomous Production Impact & Order Rescheduling Agent for Texora AI.
Analyzes active production batches, calculates downtime production loss,
identifies client delivery risks, evaluates alternate factory machinery,
and proposes batch rerouting through manager approval gates.
"""
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
from apps.ai_agents.action_service import ActionSafetyService
from apps.incidents.models import FactoryIncident
from apps.machines.models import Machine, MachineStatus
from apps.production.models import ProductionBatch, ProductionOrder, OrderStatus, OrderPriority

logger = logging.getLogger(__name__)


class ProductionImpactAgent:
    """
    Autonomous Production Impact Agent.
    Quantifies the operational and delivery fallout of machinery failures, identifies
    threatened customer orders, discovers capable alternate machines, and plans rerouting.
    """

    def __init__(self):
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.PRODUCTION_IMPACT,
            defaults={
                "name": "Production Rescheduling & Impact Agent",
                "description": "Autonomous manufacturing impact analyst assessing batch delays, capacity buffers, and alternate machine rerouting.",
                "model_name": "deterministic-production-v1",
                "is_enabled": True,
                "permitted_actions": [
                    "REROUTE_PRODUCTION_BATCH",
                    "PAUSE_PRODUCTION_BATCH",
                    "CALCULATE_CAPACITY_BUFFER",
                ],
                "sensitivity_threshold": 0.85,
            },
        )
        return agent_def

    def evaluate_production_impact(
        self, incident_id: int, estimated_downtime_hours: float = 1.5
    ) -> Dict[str, Any]:
        """
        Assesses live production batches on the impaired machine and proposes mitigation actions.
        """
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
            context_payload={
                "incident_code": incident.incident_code,
                "machine_code": machine.code,
                "estimated_downtime_hours": estimated_downtime_hours,
            },
        )

        try:
            # 1. Fetch active batches on affected machine
            batches = ProductionBatch.objects.filter(
                machine=machine, status__in=["RUNNING", "STAGED", "PAUSED"]
            ).select_related("production_order", "production_order__department")

            batches_data = []
            orders_at_risk = []
            total_planned_qty = 0.0
            total_actual_qty = 0.0

            now = timezone.now().date()

            for b in batches:
                order = b.production_order
                planned = float(b.planned_quantity)
                actual = float(b.actual_quantity)
                defects = float(b.defect_quantity)
                total_planned_qty += planned
                total_actual_qty += actual

                days_until_due = (order.due_date - now).days if order.due_date else 99
                is_rush = order.priority in [OrderPriority.URGENT, OrderPriority.HIGH]
                is_at_risk = days_until_due <= 3 or (is_rush and days_until_due <= 5)

                batch_summary = {
                    "batch_id": b.id,
                    "batch_number": b.batch_number,
                    "order_number": order.order_number,
                    "client_name": order.client_name,
                    "spec": order.fabric_or_yarn_spec,
                    "planned_qty": planned,
                    "actual_qty": actual,
                    "defect_qty": defects,
                    "unit": order.unit,
                    "status": b.status,
                    "due_date": order.due_date.isoformat() if order.due_date else None,
                    "days_until_due": days_until_due,
                    "is_at_risk": is_at_risk,
                }
                batches_data.append(batch_summary)

                if is_at_risk:
                    orders_at_risk.append({
                        "order_number": order.order_number,
                        "client_name": order.client_name,
                        "due_date": order.due_date.isoformat(),
                        "days_until_due": days_until_due,
                        "priority": order.priority,
                        "spec": order.fabric_or_yarn_spec,
                        "target_quantity": float(order.target_quantity),
                        "completed_quantity": float(order.completed_quantity),
                        "progress_pct": order.progress_pct,
                    })

            # 2. Estimate lost output during downtime
            # Baseline speed: approx 80-120 units/hour per machine
            estimated_loss_units = round(estimated_downtime_hours * 95.0, 1)

            # 3. Discover Alternate Compatible Machines
            alternate_candidates = []
            if machine.machine_type:
                compatible_machines = Machine.objects.filter(
                    department=machine.department,
                    machine_type=machine.machine_type,
                    status__in=[MachineStatus.OPERATIONAL, MachineStatus.IDLE],
                ).exclude(id=machine.id)

                for cm in compatible_machines:
                    # Check if candidate has active incidents
                    has_active_incident = FactoryIncident.objects.filter(
                        machine=cm, status__in=["OPEN", "INVESTIGATING", "MITIGATING"]
                    ).exists()

                    active_batch_count = ProductionBatch.objects.filter(
                        machine=cm, status__in=["RUNNING", "STAGED"]
                    ).count()

                    if not has_active_incident and active_batch_count <= 2:
                        alternate_candidates.append({
                            "machine_id": cm.id,
                            "machine_code": cm.code,
                            "machine_name": cm.name,
                            "status": cm.status,
                            "active_batches_assigned": active_batch_count,
                            "available_capacity": "HIGH" if active_batch_count == 0 else "MODERATE",
                        })

            # 4. Propose Rerouting Action if At-Risk Batches and Alternates exist
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

            # 5. Persist AgentDecision
            summary_text = (
                f"Evaluated {len(batches_data)} active batches on {machine.code}. "
                f"Estimated Downtime: {estimated_downtime_hours}h (Loss: ~{estimated_loss_units} units). "
                f"Orders at Risk: {len(orders_at_risk)}. Alternate Machines Available: {len(alternate_candidates)}."
            )

            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="PRODUCTION_REROUTE",
                rationale=summary_text,
                confidence_score=92.00,
                risk_level="HIGH" if len(orders_at_risk) > 0 else "LOW",
                requires_human_approval=True,
            )

            execution.status = AgentExecutionStatus.COMPLETED
            execution.execution_summary = summary_text
            execution.completed_at = timezone.now()
            execution.save()

            return {
                "success": True,
                "execution_id": str(execution.execution_id),
                "active_batches": batches_data,
                "orders_at_risk": orders_at_risk,
                "alternate_machines": alternate_candidates,
                "estimated_loss_units": estimated_loss_units,
                "proposed_actions": proposed_actions,
                "summary": summary_text,
            }

        except Exception as exc:
            logger.exception("Error in ProductionImpactAgent: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Production impact analysis failed: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {"success": False, "error": str(exc)}
