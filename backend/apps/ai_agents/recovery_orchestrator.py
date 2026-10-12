"""
Factory Recovery Orchestrator for Texora AI.
Coordinates multi-agent autonomous investigations across Machine Health, Maintenance,
Inventory, and Production Impact agents to produce unified, dependency-aware recovery plans.
"""
import uuid
import logging
from typing import Dict, Any, List, Optional
from decimal import Decimal
from django.db import transaction
from django.utils import timezone

from apps.ai_agents.models import (
    RecoveryCase,
    RecoveryPlanStep,
    RecoveryCaseStatus,
    RecoveryStepStatus,
    AgentExecution,
    AgentAction,
    AgentType,
    AgentExecutionStatus,
)
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.maintenance_coordinator import MaintenanceCoordinatorAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.production_impact_agent import ProductionImpactAgent
from apps.incidents.models import FactoryIncident, IncidentStatus, IncidentSeverity
from apps.machines.models import Machine
from apps.approvals.models import ApprovalRequest, ApprovalStatus

logger = logging.getLogger(__name__)


class RecoveryOrchestrator:
    """
    Central Multi-Agent Recovery Coordinator.
    Synthesizes autonomous agent findings into structured, auditable recovery workflows.
    """

    def __init__(self):
        self.health_agent = MachineHealthAgent()
        self.maintenance_coordinator = MaintenanceCoordinatorAgent()
        self.inventory_coordinator = InventoryCoordinatorAgent()
        self.production_agent = ProductionImpactAgent()

    def orchestrate_incident_recovery(
        self, incident_id: int, force_reanalyze: bool = False
    ) -> Dict[str, Any]:
        """
        Executes end-to-end multi-agent coordination for an incident and builds a RecoveryCase.
        """
        incident = FactoryIncident.objects.select_related("machine", "department", "factory").filter(id=incident_id).first()
        if not incident:
            return {"success": False, "error": f"Incident #{incident_id} not found."}

        machine = incident.machine
        if not machine:
            return {"success": False, "error": f"Incident #{incident_id} has no associated machine."}

        # 1. Deduplication: Check if active RecoveryCase exists
        existing_case = RecoveryCase.objects.filter(
            incident=incident,
            status__in=[
                RecoveryCaseStatus.ANALYZING,
                RecoveryCaseStatus.PLAN_READY,
                RecoveryCaseStatus.AWAITING_APPROVALS,
                RecoveryCaseStatus.IN_RECOVERY,
                RecoveryCaseStatus.VERIFYING_TELEMETRY,
            ],
        ).first()

        if existing_case and not force_reanalyze:
            logger.info("Existing active RecoveryCase %s found for incident #%d", existing_case.case_code, incident_id)
            return {
                "success": True,
                "case_id": existing_case.id,
                "case_code": existing_case.case_code,
                "status": existing_case.status,
                "priority_score": float(existing_case.priority_score),
                "is_existing": True,
                "steps": [
                    {
                        "step_order": s.step_order,
                        "title": s.title,
                        "agent_type": s.agent_type,
                        "action_type": s.action_type,
                        "status": s.status,
                        "dependencies": s.dependencies,
                        "approval_code": s.approval_request.approval_code if s.approval_request else None,
                    }
                    for s in existing_case.steps.all()
                ],
            }

        # 2. Retrieve or Trigger Machine Health Diagnostic Investigation
        health_exec = AgentExecution.objects.filter(
            incident=incident,
            agent__agent_type=AgentType.MACHINE_HEALTH,
            status=AgentExecutionStatus.COMPLETED,
        ).order_by("-completed_at").first()

        health_data = {}
        if health_exec and health_exec.context_payload:
            health_decision = health_exec.decisions.first()
            health_data = {
                "execution_id": str(health_exec.execution_id),
                "summary": health_exec.execution_summary,
                "severity_assessment": incident.severity,
                "confidence_score": float(health_decision.confidence_score) if health_decision else 85.0,
                "possible_root_causes": [{"hypothesis": incident.root_cause_hypothesis, "likelihood": "HIGH", "confidence_score": 85.0}],
            }
        else:
            investigation_res = self.health_agent.investigate_incident(incident_id)
            health_data = investigation_res.get("findings", {})

        # 3. Trigger Maintenance Coordination
        maint_res = self.maintenance_coordinator.coordinate_maintenance(
            incident_id=incident_id, health_diagnosis=health_data
        )

        # 4. Trigger Inventory Coordination
        inv_res = self.inventory_coordinator.coordinate_inventory(
            incident_id=incident_id,
            health_diagnosis=health_data,
            maintenance_recommendation=maint_res,
        )

        # 5. Trigger Production Impact Assessment
        estimated_downtime = float(maint_res.get("estimated_hours", 1.5))
        prod_res = self.production_agent.evaluate_production_impact(
            incident_id=incident_id, estimated_downtime_hours=estimated_downtime
        )

        # 6. Calculate Evidence-Based Priority Score (0.00 to 100.00)
        priority_score = Decimal("40.00")
        if incident.severity == IncidentSeverity.CRITICAL:
            priority_score += Decimal("30.00")
        elif incident.severity == IncidentSeverity.HIGH:
            priority_score += Decimal("20.00")
        else:
            priority_score += Decimal("10.00")

        # Add production risk weight
        if prod_res.get("orders_at_risk"):
            priority_score += Decimal("15.00")
        elif prod_res.get("active_batches"):
            priority_score += Decimal("8.00")

        # Add inventory shortage weight
        if inv_res.get("shortages_count", 0) > 0:
            priority_score += Decimal("10.00")

        priority_score = min(Decimal("99.50"), priority_score)

        # 7. Persist or Update RecoveryCase Record
        case_code = f"REC-{timezone.now().strftime('%Y%m%d')}-{uuid.uuid4().hex[:4].upper()}"

        with transaction.atomic():
            recovery_case = RecoveryCase.objects.create(
                case_code=case_code,
                incident=incident,
                machine=machine,
                status=RecoveryCaseStatus.ANALYZING,
                priority="CRITICAL" if priority_score >= 80 else ("HIGH" if priority_score >= 60 else "MEDIUM"),
                priority_score=priority_score,
                estimated_downtime_hours=Decimal(str(estimated_downtime)),
                target_resolution_hours=Decimal(str(round(estimated_downtime + 0.5, 1))),
                health_diagnosis=health_data,
                maintenance_recommendation=maint_res,
                inventory_assessment=inv_res,
                production_impact_assessment=prod_res,
                summary=(
                    f"Correlated Multi-Agent Recovery Plan for {machine.code} ({incident.incident_code}). "
                    f"Severity: {incident.severity}. Priority Score: {priority_score}%. "
                    f"Target Repair Time: {estimated_downtime}h."
                ),
            )

            # 8. Build Sequential Dependency-Aware Plan Steps
            step_order = 1
            has_pending_approval = False

            # Step 1: Inventory Reservation / Procurement
            inv_actions = inv_res.get("proposed_actions", [])
            inv_action_obj = None
            inv_approval_obj = None
            if inv_actions:
                inv_act_id = inv_actions[0].get("action_id")
                inv_action_obj = AgentAction.objects.filter(id=inv_act_id).first()
                if inv_action_obj:
                    inv_approval_obj = getattr(inv_action_obj, "approval_request", None)

            step1 = RecoveryPlanStep.objects.create(
                recovery_case=recovery_case,
                step_order=step_order,
                title="Spare Parts Allocation & Warehouse Reservation",
                description=(
                    f"Reserve required replacement parts for {machine.code} from warehouse inventory. "
                    f"Parts evaluated: {len(inv_res.get('evaluated_parts', []))}."
                ),
                agent_type="INVENTORY",
                action_type="RESERVE_SPARE_PART",
                agent_action=inv_action_obj,
                approval_request=inv_approval_obj,
                status=RecoveryStepStatus.AWAITING_APPROVAL if inv_approval_obj else RecoveryStepStatus.COMPLETED,
                dependencies=[],
            )
            if inv_approval_obj:
                has_pending_approval = True
            step_order += 1

            # Step 2: Maintenance Work Order & Technician Dispatch
            maint_action_id = maint_res.get("action_id")
            maint_action_obj = AgentAction.objects.filter(id=maint_action_id).first() if maint_action_id else None
            maint_approval_obj = getattr(maint_action_obj, "approval_request", None) if maint_action_obj else None

            step2 = RecoveryPlanStep.objects.create(
                recovery_case=recovery_case,
                step_order=step_order,
                title="Mechanical Work Order Execution & Inspection Protocols",
                description=(
                    f"Dispatch {maint_res.get('assigned_technician', 'Mechanical Team')} to perform "
                    f"{len(maint_res.get('inspection_steps', []))} diagnostic inspection and repair steps on {machine.code}."
                ),
                agent_type="MAINTENANCE",
                action_type="CREATE_MAINTENANCE_TICKET",
                agent_action=maint_action_obj,
                approval_request=maint_approval_obj,
                status=RecoveryStepStatus.AWAITING_APPROVAL if maint_approval_obj else RecoveryStepStatus.PENDING_DEPENDENCY,
                dependencies=[1] if inv_approval_obj else [],
            )
            if maint_approval_obj:
                has_pending_approval = True
            step_order += 1

            # Step 3: Production Batch Rescheduling (if applicable)
            prod_actions = prod_res.get("proposed_actions", [])
            if prod_actions:
                prod_act_id = prod_actions[0].get("action_id")
                prod_action_obj = AgentAction.objects.filter(id=prod_act_id).first()
                prod_approval_obj = getattr(prod_action_obj, "approval_request", None) if prod_action_obj else None

                step3 = RecoveryPlanStep.objects.create(
                    recovery_case=recovery_case,
                    step_order=step_order,
                    title="Production Batch Rescheduling & Capacity Rerouting",
                    description=(
                        f"Reroute at-risk batches on {machine.code} to alternate machine "
                        f"{prod_actions[0].get('target_machine', 'alternate line')} to protect client delivery schedules."
                    ),
                    agent_type="PRODUCTION_IMPACT",
                    action_type="REROUTE_PRODUCTION_BATCH",
                    agent_action=prod_action_obj,
                    approval_request=prod_approval_obj,
                    status=RecoveryStepStatus.AWAITING_APPROVAL if prod_approval_obj else RecoveryStepStatus.PENDING_DEPENDENCY,
                    dependencies=[],
                )
                if prod_approval_obj:
                    has_pending_approval = True
                step_order += 1

            # Step 4: Post-Maintenance Telemetry Sign-off
            step_final = RecoveryPlanStep.objects.create(
                recovery_case=recovery_case,
                step_order=step_order,
                title="Post-Maintenance Sensor Calibration & Telemetry Sign-Off",
                description=(
                    f"Verify machine telemetry on {machine.code} returns below operating limits "
                    f"and confirm physical sign-off before marking incident resolved."
                ),
                agent_type="MACHINE_HEALTH",
                action_type="VERIFY_TELEMETRY_RECOVERY",
                status=RecoveryStepStatus.PENDING_DEPENDENCY,
                dependencies=[2],
            )

            # Update overall case status
            recovery_case.status = (
                RecoveryCaseStatus.AWAITING_APPROVALS if has_pending_approval else RecoveryCaseStatus.PLAN_READY
            )
            recovery_case.save(update_fields=["status"])

        logger.info(
            "Orchestrated RecoveryCase %s for incident #%d with %d steps. Status: %s",
            recovery_case.case_code,
            incident_id,
            recovery_case.steps.count(),
            recovery_case.status,
        )

        return {
            "success": True,
            "case_id": recovery_case.id,
            "case_code": recovery_case.case_code,
            "status": recovery_case.status,
            "priority": recovery_case.priority,
            "priority_score": float(recovery_case.priority_score),
            "estimated_downtime_hours": float(recovery_case.estimated_downtime_hours),
            "pending_approvals_count": recovery_case.pending_approvals_count,
            "steps_count": recovery_case.steps.count(),
            "summary": recovery_case.summary,
        }

    def evaluate_step_dependencies(self, recovery_case_id: int):
        """
        Updates step statuses when prerequisite dependent steps complete,
        and synchronizes the overall RecoveryCase status.
        """
        case = RecoveryCase.objects.prefetch_related("steps", "steps__approval_request").filter(id=recovery_case_id).first()
        if not case:
            return

        steps = list(case.steps.all())
        completed_orders = {s.step_order for s in steps if s.status == RecoveryStepStatus.COMPLETED}

        for s in steps:
            if s.status == RecoveryStepStatus.PENDING_DEPENDENCY:
                all_deps_met = all(dep in completed_orders for dep in s.dependencies)
                if all_deps_met:
                    if s.approval_request and s.approval_request.status == ApprovalStatus.PENDING:
                        s.status = RecoveryStepStatus.AWAITING_APPROVAL
                    elif s.approval_request and s.approval_request.status == ApprovalStatus.APPROVED:
                        s.status = RecoveryStepStatus.APPROVED
                    else:
                        s.status = RecoveryStepStatus.EXECUTING
                    s.save(update_fields=["status"])
            elif s.approval_request and s.approval_request.status == ApprovalStatus.APPROVED and s.status == RecoveryStepStatus.AWAITING_APPROVAL:
                s.status = RecoveryStepStatus.COMPLETED
                s.save(update_fields=["status"])

        # Re-fetch updated steps to evaluate accurate overall case status
        case.refresh_from_db()
        updated_steps = list(case.steps.all())
        
        if case.is_all_steps_completed:
            case.status = RecoveryCaseStatus.RECOVERED
            if not case.recovered_at:
                case.recovered_at = timezone.now()
            case.save(update_fields=["status", "recovered_at"])
        elif any(s.status == RecoveryStepStatus.AWAITING_APPROVAL for s in updated_steps):
            case.status = RecoveryCaseStatus.AWAITING_APPROVALS
            case.save(update_fields=["status"])
        elif any(s.status in [RecoveryStepStatus.EXECUTING, RecoveryStepStatus.APPROVED, RecoveryStepStatus.COMPLETED] for s in updated_steps):
            non_telemetry_steps = [s for s in updated_steps if s.action_type != "VERIFY_TELEMETRY_RECOVERY"]
            if non_telemetry_steps and all(s.status == RecoveryStepStatus.COMPLETED for s in non_telemetry_steps):
                case.status = RecoveryCaseStatus.VERIFYING_TELEMETRY
            else:
                case.status = RecoveryCaseStatus.IN_RECOVERY
            case.save(update_fields=["status"])
        else:
            case.status = RecoveryCaseStatus.PLAN_READY
            case.save(update_fields=["status"])
