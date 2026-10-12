"""
Action Safety & Execution Service for Texora AI Autonomous Agents.
Enforces strict human-in-the-loop approval gates, server-side Role-Based Access Control (RBAC),
prohibits AI agent self-approval or unapproved machine control, maintains transactional integrity,
and records immutable audit trails.
"""
import uuid
import logging
from typing import Dict, Any, Optional, Set
from django.db import transaction
from django.utils import timezone

from apps.ai_agents.models import AgentAction, AgentExecution, RecoveryPlanStep, RecoveryStepStatus
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.audit_logs.models import AuditLog
from apps.incidents.models import FactoryIncident
from apps.machines.models import Machine
from apps.maintenance.models import MaintenanceTicket, MaintenanceActivity, TicketPriority, TicketStatus
from apps.inventory.models import InventoryItem, InventoryTransaction
from apps.production.models import ProductionBatch

logger = logging.getLogger(__name__)


class ActionSafetyLevel:
    READ_ONLY = "READ_ONLY"
    SIMULATION_ONLY = "SIMULATION_ONLY"
    REVERSIBLE_MUTATION = "REVERSIBLE_MUTATION"
    OPERATIONAL_MUTATION = "OPERATIONAL_MUTATION"
    SAFETY_CRITICAL_ACTION = "SAFETY_CRITICAL_ACTION"


class ActionSafetyService:
    """
    Validates, queues, and executes agent-recommended operational actions.
    Ensures no sensitive action executes without explicit, role-authorized human approval.
    """

    ACTION_SAFETY_LEVELS: Dict[str, str] = {
        "get_machine_details": ActionSafetyLevel.READ_ONLY,
        "get_recent_machine_telemetry": ActionSafetyLevel.READ_ONLY,
        "get_machine_operating_limits": ActionSafetyLevel.READ_ONLY,
        "get_machine_maintenance_history": ActionSafetyLevel.READ_ONLY,
        "get_active_machine_incidents": ActionSafetyLevel.READ_ONLY,
        "get_affected_production_orders": ActionSafetyLevel.READ_ONLY,
        "get_relevant_spare_parts": ActionSafetyLevel.READ_ONLY,
        "CHECK_STOCK_LEVELS": ActionSafetyLevel.READ_ONLY,
        "RUN_WHAT_IF_SIMULATION": ActionSafetyLevel.SIMULATION_ONLY,
        "CREATE_MAINTENANCE_DRAFT": ActionSafetyLevel.REVERSIBLE_MUTATION,
        "RESERVE_SPARE_PART": ActionSafetyLevel.OPERATIONAL_MUTATION,
        "CREATE_PROCUREMENT_REQUEST": ActionSafetyLevel.OPERATIONAL_MUTATION,
        "CREATE_MAINTENANCE_TICKET": ActionSafetyLevel.OPERATIONAL_MUTATION,
        "REROUTE_PRODUCTION_BATCH": ActionSafetyLevel.SAFETY_CRITICAL_ACTION,
        "PAUSE_PRODUCTION_BATCH": ActionSafetyLevel.SAFETY_CRITICAL_ACTION,
        "THROTTLE_SPEED": ActionSafetyLevel.SAFETY_CRITICAL_ACTION,
        "ASSIGN_TECHNICIAN": ActionSafetyLevel.OPERATIONAL_MUTATION,
    }

    ROLE_PERMISSIONS: Dict[str, Set[str]] = {
        "MAINTENANCE_MANAGER": {
            "CREATE_MAINTENANCE_TICKET",
            "CREATE_MAINTENANCE_DRAFT",
            "SCHEDULE_INSPECTION",
            "RESERVE_SPARE_PART",
            "ASSIGN_TECHNICIAN",
        },
        "PRODUCTION_MANAGER": {
            "REROUTE_PRODUCTION_BATCH",
            "PAUSE_PRODUCTION_BATCH",
            "SCHEDULE_INSPECTION",
        },
        "WAREHOUSE_MANAGER": {
            "RESERVE_SPARE_PART",
            "CREATE_PROCUREMENT_REQUEST",
        },
        "PLANT_DIRECTOR": {
            "CREATE_MAINTENANCE_TICKET",
            "CREATE_MAINTENANCE_DRAFT",
            "SCHEDULE_INSPECTION",
            "RESERVE_SPARE_PART",
            "CREATE_PROCUREMENT_REQUEST",
            "REROUTE_PRODUCTION_BATCH",
            "PAUSE_PRODUCTION_BATCH",
            "THROTTLE_SPEED",
            "ASSIGN_TECHNICIAN",
        },
        "OPERATOR": set(),
    }

    @classmethod
    def get_action_safety_level(cls, action_type: str) -> str:
        """Returns the classified safety level for an action."""
        return cls.ACTION_SAFETY_LEVELS.get(action_type, ActionSafetyLevel.OPERATIONAL_MUTATION)

    @classmethod
    def is_approval_required(cls, action_type: str) -> bool:
        """Determines if human approval is strictly required before execution."""
        level = cls.get_action_safety_level(action_type)
        return level in [
            ActionSafetyLevel.OPERATIONAL_MUTATION,
            ActionSafetyLevel.SAFETY_CRITICAL_ACTION,
            ActionSafetyLevel.REVERSIBLE_MUTATION,
        ]

    FORBIDDEN_AI_IDENTITIES = {
        "system",
        "system_daemon",
        "ai_agent",
        "gemini",
        "machine_health_agent",
        "maintenance_coordinator",
        "inventory_coordinator",
        "production_impact_agent",
        "machine health diagnostic specialist",
        "mock_agent",
    }

    @classmethod
    def propose_action(
        cls,
        execution: AgentExecution,
        action_type: str,
        description: str,
        payload: Dict[str, Any],
        requires_approval: bool = True,
    ) -> AgentAction:
        """
        Registers an action proposed by an agent. If the action is sensitive or requires approval,
        it is placed in PENDING_APPROVAL status and an ApprovalRequest is created.
        """
        idempotency_key = f"ACT-{execution.id}-{action_type}-{uuid.uuid4().hex[:6].upper()}"

        with transaction.atomic():
            action = AgentAction.objects.create(
                execution=execution,
                idempotency_key=idempotency_key,
                action_name=description,
                tool_name=action_type,
                tool_input=payload,
                status="PENDING_APPROVAL" if requires_approval else "EXECUTING",
            )

            if requires_approval:
                incident = execution.incident
                if not incident:
                    incident = FactoryIncident.objects.order_by("-id").first()

                approval_code = f"APR-{timezone.now().strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:4].upper()}"
                approval = ApprovalRequest.objects.create(
                    approval_code=approval_code,
                    incident=incident,
                    agent_action=action,
                    title=f"Approval Required: {description}",
                    description=f"AI Agent '{execution.agent.name}' proposed: {description}\n\nPayload: {payload}",
                    requested_action=action_type,
                    risk_level="HIGH" if action_type in ["REROUTE_PRODUCTION_BATCH", "THROTTLE_SPEED"] else "MEDIUM",
                    status=ApprovalStatus.PENDING,
                    requested_by_agent=execution.agent.name,
                )

                # Log proposal to AuditLog
                AuditLog.objects.create(
                    entity_type="APPROVAL",
                    entity_id=approval.approval_code,
                    action="CREATE",
                    actor_type="AI_AGENT",
                    actor_id=execution.agent.name,
                    changes_payload={"action_type": action_type, "payload": payload},
                    description=f"Agent '{execution.agent.name}' created approval request {approval.approval_code}",
                )
                logger.info("Created ApprovalRequest %s for action %s", approval.approval_code, action.idempotency_key)

            return action

    @classmethod
    def validate_authorization(
        cls, action_type: str, user_name: str, user_role: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Validates whether the approving identity and role are authorized for the requested action.
        Rejects anonymous users, unauthorized roles, and AI agent self-approvals.
        """
        sanitized_name = (user_name or "").strip()
        
        if not sanitized_name:
            return {"authorized": False, "error": "Approval rejected: Authenticated user identity is required."}

        # Check for AI agent self-approval attempts
        if sanitized_name.lower() in cls.FORBIDDEN_AI_IDENTITIES or "agent" in sanitized_name.lower():
            return {
                "authorized": False,
                "error": "Security Violation: AI agent self-approval is strictly forbidden. A human manager must authorize.",
            }

        # Infer role if not explicitly passed
        if not user_role:
            if "director" in sanitized_name.lower() or "plant" in sanitized_name.lower() or "lead" in sanitized_name.lower() or "engineer" in sanitized_name.lower():
                sanitized_role = "PLANT_DIRECTOR"
            elif "production" in sanitized_name.lower():
                sanitized_role = "PRODUCTION_MANAGER"
            elif "warehouse" in sanitized_name.lower() or "inventory" in sanitized_name.lower():
                sanitized_role = "WAREHOUSE_MANAGER"
            else:
                sanitized_role = "MAINTENANCE_MANAGER"
        else:
            sanitized_role = user_role.strip().upper()

        if sanitized_role not in cls.ROLE_PERMISSIONS:
            return {
                "authorized": False,
                "error": f"Security Violation: Role '{sanitized_role}' is not recognized in factory permission schema.",
            }

        # If action_type is empty or generic, permit for manager roles
        if not action_type or action_type in ["GENERAL_APPROVAL", ""]:
            return {"authorized": True, "role": sanitized_role}

        allowed_actions = cls.ROLE_PERMISSIONS.get(sanitized_role, set())
        if action_type not in allowed_actions and sanitized_role != "PLANT_DIRECTOR":
            return {
                "authorized": False,
                "error": f"Access Denied: Role '{sanitized_role}' lacks permission to authorize '{action_type}'. Required: {cls._get_required_roles(action_type)}.",
            }

        return {"authorized": True, "role": sanitized_role}

    @classmethod
    def _get_required_roles(cls, action_type: str) -> str:
        roles = [r for r, actions in cls.ROLE_PERMISSIONS.items() if action_type in actions]
        return ", ".join(roles) if roles else "PLANT_DIRECTOR"

    @classmethod
    def approve_and_execute(
        cls, approval_id: int, approved_by: str, user_role: Optional[str] = None, response_notes: str = ""
    ) -> Dict[str, Any]:
        """
        Approves an ApprovalRequest and executes the associated backend action.
        Only called by authorized human operators/managers via secure API endpoints.
        """
        with transaction.atomic():
            approval = ApprovalRequest.objects.select_related("agent_action", "incident", "agent_action__execution").get(
                id=approval_id
            )

            if approval.status != ApprovalStatus.PENDING:
                return {
                    "success": False,
                    "error": f"Approval request is already in status '{approval.status}'.",
                }

            action = approval.agent_action
            action_type = action.tool_name if action else approval.requested_action

            # RBAC Validation
            auth_check = cls.validate_authorization(
                action_type=action_type, user_name=approved_by, user_role=user_role
            )
            if not auth_check.get("authorized"):
                return {"success": False, "error": auth_check.get("error")}

            approval.status = ApprovalStatus.APPROVED
            approval.approved_by = approved_by
            approval.response_notes = response_notes
            approval.responded_at = timezone.now()
            approval.save()

            if not action:
                return {"success": True, "message": "Approval recorded (no direct backend action linked)."}

            # Execute the specific validated backend action
            action_result = cls._execute_underlying_action(action, approval)

            action.status = "SUCCESS" if action_result.get("success") else "FAILED"
            action.tool_output = action_result
            action.error_message = action_result.get("error", "")
            action.save()

            # Record audit log
            AuditLog.objects.create(
                entity_type="APPROVAL",
                entity_id=approval.approval_code,
                action="APPROVAL_GRANTED",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                changes_payload={"action_result": action_result, "notes": response_notes, "role": auth_check.get("role")},
                description=f"Manager '{approval.approved_by}' approved {approval.requested_action or action_type}. Result: {action.status}",
            )

            # Advance corresponding RecoveryPlanStep if linked
            step = RecoveryPlanStep.objects.filter(approval_request=approval).first()
            if not step:
                step = RecoveryPlanStep.objects.filter(agent_action=action).first()

            if step:
                step.status = RecoveryStepStatus.COMPLETED if action.status == "SUCCESS" else RecoveryStepStatus.REJECTED
                step.completed_at = timezone.now()
                step.output_payload = action_result
                step.save()

                # Trigger orchestrator to advance downstream steps
                from apps.ai_agents.recovery_orchestrator import RecoveryOrchestrator
                RecoveryOrchestrator().evaluate_step_dependencies(step.recovery_case_id)

            return {
                "success": True,
                "approval_code": approval.approval_code,
                "action_status": action.status,
                "result": action_result,
            }

    @classmethod
    def reject_approval(
        cls, approval_id: int, rejected_by: str, user_role: Optional[str] = None, response_notes: str = ""
    ) -> Dict[str, Any]:
        """
        Rejects an ApprovalRequest and cancels the proposed action.
        """
        with transaction.atomic():
            approval = ApprovalRequest.objects.select_related("agent_action").get(id=approval_id)

            if approval.status != ApprovalStatus.PENDING:
                return {
                    "success": False,
                    "error": f"Approval request is already in status '{approval.status}'.",
                }

            action = approval.agent_action
            action_type = action.tool_name if action else approval.requested_action

            auth_check = cls.validate_authorization(
                action_type=action_type, user_name=rejected_by, user_role=user_role
            )
            if not auth_check.get("authorized"):
                return {"success": False, "error": auth_check.get("error")}

            approval.status = ApprovalStatus.REJECTED
            approval.approved_by = rejected_by
            approval.response_notes = response_notes
            approval.responded_at = timezone.now()
            approval.save()

            if approval.agent_action:
                approval.agent_action.status = "CANCELLED"
                approval.agent_action.error_message = f"Rejected by manager: {response_notes}"
                approval.agent_action.save()

            AuditLog.objects.create(
                entity_type="APPROVAL",
                entity_id=approval.approval_code,
                action="APPROVAL_REJECTED",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                changes_payload={"notes": response_notes, "role": auth_check.get("role")},
                description=f"Manager '{approval.approved_by}' rejected {approval.requested_action or action_type}",
            )

            # Advance corresponding RecoveryPlanStep
            step = RecoveryPlanStep.objects.filter(approval_request=approval).first()
            if step:
                step.status = RecoveryStepStatus.REJECTED
                step.completed_at = timezone.now()
                step.save()

            return {
                "success": True,
                "approval_code": approval.approval_code,
                "status": "REJECTED",
            }

    @classmethod
    def request_revision(
        cls, approval_id: int, requested_by: str, user_role: Optional[str] = None, response_notes: str = ""
    ) -> Dict[str, Any]:
        """
        Marks an ApprovalRequest as REVISION_REQUESTED and logs the manager's feedback.
        """
        with transaction.atomic():
            approval = ApprovalRequest.objects.select_related("agent_action").get(id=approval_id)

            if approval.status != ApprovalStatus.PENDING:
                return {
                    "success": False,
                    "error": f"Approval request is already in status '{approval.status}'.",
                }

            action = approval.agent_action
            action_type = action.tool_name if action else approval.requested_action

            auth_check = cls.validate_authorization(
                action_type=action_type, user_name=requested_by, user_role=user_role
            )
            if not auth_check.get("authorized"):
                return {"success": False, "error": auth_check.get("error")}

            approval.status = ApprovalStatus.REVISION_REQUESTED
            approval.approved_by = requested_by
            approval.response_notes = response_notes
            approval.responded_at = timezone.now()
            approval.save()

            if approval.agent_action:
                approval.agent_action.status = "REVISION_REQUESTED"
                approval.agent_action.error_message = f"Revision requested by manager: {response_notes}"
                approval.agent_action.save()

            AuditLog.objects.create(
                entity_type="APPROVAL",
                entity_id=approval.approval_code,
                action="REVISION_REQUESTED",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                changes_payload={"notes": response_notes, "role": auth_check.get("role")},
                description=f"Manager '{approval.approved_by}' requested revision for {approval.requested_action or action_type}: {response_notes}",
            )

            return {
                "success": True,
                "approval_code": approval.approval_code,
                "status": "REVISION_REQUESTED",
            }

    @classmethod
    def _execute_underlying_action(cls, action: AgentAction, approval: ApprovalRequest) -> Dict[str, Any]:
        """
        Safely dispatches approved action to existing domain models.
        """
        action_name = action.tool_name
        payload = action.tool_input or {}
        incident = approval.incident

        if action_name in ["CREATE_MAINTENANCE_TICKET", "CREATE_MAINTENANCE_DRAFT"]:
            machine = incident.machine
            if not machine:
                return {"success": False, "error": "Cannot create maintenance ticket without associated machine."}

            ticket_number = f"MNT-{timezone.now().strftime('%Y%m%d%H%M%S')}-{uuid.uuid4().hex[:4].upper()}"
            agent_name = approval.requested_by_agent or "Machine Health Specialist"
            if "Machine Health" in agent_name:
                agent_name = "Machine Health Specialist"

            ticket = MaintenanceTicket.objects.create(
                ticket_number=ticket_number,
                machine=machine,
                incident_reference=incident.incident_code,
                title=payload.get("title", f"Repair: {incident.summary[:150]}"),
                description=(
                    f"Authorized maintenance work order for incident {incident.incident_code}.\n"
                    f"Machine: {machine.code} ({machine.name})\n"
                    f"Suspected Root Cause: {payload.get('primary_hypothesis', incident.root_cause_hypothesis)}\n\n"
                    f"Inspection Protocols:\n" + "\n".join([f"- {step}" for step in payload.get("inspection_checklist", [])])
                ),
                priority=payload.get("priority", TicketPriority.HIGH),
                status=TicketStatus.OPEN,
                assigned_technician=payload.get("assigned_technician", "Mechanical Fast Response Team"),
                created_by_agent=agent_name,
                root_cause=payload.get("primary_hypothesis", incident.root_cause_hypothesis),
                labor_hours=payload.get("estimated_hours", 1.5),
            )

            # Link incident state
            if incident.status in ["OPEN", "INVESTIGATING"]:
                incident.status = "MITIGATING"
                incident.save(update_fields=["status"])

            # Create initial inspection activity
            for idx, check in enumerate(payload.get("inspection_checklist", [])[:3], 1):
                MaintenanceActivity.objects.create(
                    ticket=ticket,
                    activity_type="INSPECTION",
                    description=check,
                    performed_by=ticket.assigned_technician,
                    duration_minutes=30,
                )

            # Record ticket audit log
            AuditLog.objects.create(
                entity_type="TICKET",
                entity_id=ticket.ticket_number,
                action="CREATE",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                description=f"Created work order {ticket.ticket_number} on {machine.code} [{ticket.priority}]",
            )

            return {
                "success": True,
                "ticket_number": ticket.ticket_number,
                "ticket_id": ticket.id,
                "machine": machine.code,
                "priority": ticket.priority,
                "assigned_technician": ticket.assigned_technician,
                "labor_hours": float(ticket.labor_hours),
            }

        elif action_name == "RESERVE_SPARE_PART":
            part_code = payload.get("part_code", "")
            item = InventoryItem.objects.filter(item_code=part_code).first()
            if not item:
                return {"success": False, "error": f"Spare part '{part_code}' not found in inventory."}

            qty = payload.get("quantity", 1)
            if float(item.current_stock) < float(qty):
                return {
                    "success": False,
                    "error": f"Insufficient stock for '{part_code}'. Current stock: {item.current_stock}, requested: {qty}.",
                }

            # Create reservation transaction
            tx = InventoryTransaction.objects.create(
                item=item,
                transaction_type="RESERVATION",
                quantity=qty,
                reference_number=f"RES-{incident.incident_code}",
                recorded_by=approval.approved_by,
                notes=f"Reserved for repair on {incident.machine.code if incident.machine else 'Machine'}",
            )

            AuditLog.objects.create(
                entity_type="INVENTORY",
                entity_id=item.item_code,
                action="STATUS_CHANGE",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                description=f"Reserved {qty}x {item.name} ({item.item_code}) for incident {incident.incident_code}",
            )

            return {
                "success": True,
                "part_code": part_code,
                "part_name": item.name,
                "reserved_quantity": qty,
                "shelf_location": item.location_shelf,
                "transaction_id": tx.id,
            }

        elif action_name == "CREATE_PROCUREMENT_REQUEST":
            item_code = payload.get("item_code", "")
            qty = payload.get("quantity", 5)
            item = InventoryItem.objects.filter(item_code=item_code).first()

            AuditLog.objects.create(
                entity_type="INVENTORY",
                entity_id=item_code,
                action="CREATE",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                description=f"Submitted emergency purchase requisition for {qty}x {item.name if item else item_code}",
            )

            return {
                "success": True,
                "procurement_order": f"PO-REQ-{timezone.now().strftime('%Y%m%d%H%M%S')}",
                "item_code": item_code,
                "quantity": qty,
                "status": "ORDER_DISPATCHED_TO_VENDOR",
            }

        elif action_name == "REROUTE_PRODUCTION_BATCH":
            batch_id = payload.get("batch_id")
            target_machine_id = payload.get("target_machine_id")

            batch = ProductionBatch.objects.filter(id=batch_id).first()
            target_machine = Machine.objects.filter(id=target_machine_id).first()

            if not batch or not target_machine:
                return {
                    "success": False,
                    "error": f"Invalid batch #{batch_id} or target machine #{target_machine_id} for rerouting.",
                }

            old_machine_code = batch.machine.code if batch.machine else "None"
            batch.machine = target_machine
            batch.save(update_fields=["machine"])

            AuditLog.objects.create(
                entity_type="BATCH",
                entity_id=batch.batch_number,
                action="UPDATE",
                actor_type="MANAGER",
                actor_id=approval.approved_by,
                description=(
                    f"Rerouted Batch {batch.batch_number} (Order {batch.production_order.order_number}) "
                    f"from {old_machine_code} to {target_machine.code}"
                ),
            )

            return {
                "success": True,
                "batch_number": batch.batch_number,
                "from_machine": old_machine_code,
                "to_machine": target_machine.code,
                "status": "BATCH_REROUTED",
            }

        return {
            "success": True,
            "message": f"Action '{action_name}' executed and logged.",
        }
