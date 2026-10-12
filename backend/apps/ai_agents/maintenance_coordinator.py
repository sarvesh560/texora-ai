"""
Autonomous Maintenance Coordinator Agent for Texora AI.
Coordinates maintenance work orders, technician assignments, inspection protocols,
and labor estimations for detected factory incidents without duplicating active tickets.
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
from apps.incidents.models import FactoryIncident, IncidentStatus, IncidentSeverity
from apps.machines.models import Machine
from apps.maintenance.models import MaintenanceTicket, MaintenanceHistory, TicketPriority, TicketStatus

logger = logging.getLogger(__name__)


class MaintenanceCoordinatorAgent:
    """
    Autonomous Maintenance Coordinator Agent.
    Evaluates incident severity, reviews machine maintenance history, verifies active tickets,
    determines required inspection steps, and proposes work orders through human approval gates.
    """

    def __init__(self):
        self._ensure_agent_definition()

    def _ensure_agent_definition(self) -> AgentDefinition:
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.MAINTENANCE,
            defaults={
                "name": "Maintenance & Work Order Coordinator",
                "description": "Autonomous maintenance planner proposing inspection protocols, labor hours, and technician dispatch.",
                "model_name": "deterministic-maintenance-v1",
                "is_enabled": True,
                "permitted_actions": [
                    "CREATE_MAINTENANCE_TICKET",
                    "SCHEDULE_INSPECTION",
                    "ASSIGN_TECHNICIAN",
                ],
                "sensitivity_threshold": 0.75,
            },
        )
        return agent_def

    def coordinate_maintenance(
        self, incident_id: int, health_diagnosis: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Coordinates maintenance actions for a specific factory incident.
        """
        incident = FactoryIncident.objects.select_related("machine", "department").filter(id=incident_id).first()
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
            context_payload={
                "incident_code": incident.incident_code,
                "severity": incident.severity,
                "machine_code": machine.code,
                "health_diagnosis": health_diagnosis or {},
            },
        )

        try:
            # 2. Check active maintenance tickets for machine (Deduplication)
            active_ticket = MaintenanceTicket.objects.filter(
                machine=machine,
                status__in=[TicketStatus.OPEN, TicketStatus.ASSIGNED, TicketStatus.IN_PROGRESS, TicketStatus.PENDING_PARTS],
            ).first()

            if active_ticket:
                is_same_incident = active_ticket.incident_reference == incident.incident_code
                execution.status = AgentExecutionStatus.COMPLETED
                execution.execution_summary = (
                    f"Active maintenance ticket {active_ticket.ticket_number} already in progress for {machine.code}. "
                    f"Status: {active_ticket.status}."
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
                }

            # 3. Analyze Maintenance History
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

            # 4. Determine inspection steps and fault classification from diagnosis
            hypotheses = (health_diagnosis or {}).get("possible_root_causes", [])
            primary_hypothesis = hypotheses[0].get("hypothesis") if hypotheses else incident.root_cause_hypothesis

            # Synthesize recommended inspection checklist
            inspection_steps = []
            suggested_checks = (health_diagnosis or {}).get("recommended_maintenance_checks", [])
            if suggested_checks:
                inspection_steps.extend(suggested_checks)
            else:
                if "vibration" in incident.summary.lower() or "bearing" in str(primary_hypothesis).lower():
                    inspection_steps = [
                        "Perform dial indicator runout check on drive shaft bearing",
                        "Inspect bearing housing 6309 for race flaking and cage play",
                        "Verify drive belt tension and pulley alignment",
                        "Replenish synthetic high-temperature lithium grease",
                    ]
                elif "thermal" in incident.summary.lower() or "temperature" in incident.summary.lower():
                    inspection_steps = [
                        "Measure thermal gradient across motor stator using infrared pyrometer",
                        "Inspect ventilation ducting for textile lint accumulation",
                        "Verify winding insulation resistance with megohmmeter",
                    ]
                else:
                    inspection_steps = [
                        "Perform visual inspection and sensor calibration check",
                        "Inspect mechanical linkages and drive components for play",
                    ]

            # 5. Determine technician assignment and labor estimation
            dept_name = machine.department.name if machine.department else "Textile Operations"
            assigned_team = f"{dept_name} Fast-Response Mechanical Team"
            estimated_hours = 1.5 if incident.severity == IncidentSeverity.CRITICAL else 1.0

            # Determine Priority
            if incident.severity == IncidentSeverity.CRITICAL:
                ticket_priority = TicketPriority.CRITICAL
            elif incident.severity == IncidentSeverity.HIGH:
                ticket_priority = TicketPriority.HIGH
            else:
                ticket_priority = TicketPriority.MEDIUM

            # 6. Propose Work Order Creation via ActionSafetyService (requires manager approval)
            action_payload = {
                "machine_code": machine.code,
                "incident_code": incident.incident_code,
                "title": f"Corrective Repair: {machine.code} ({primary_hypothesis[:80] if primary_hypothesis else 'Telemetry Anomaly'})",
                "fault_category": "MECHANICAL_DRIVE_BEARING" if "bearing" in str(primary_hypothesis).lower() else "GENERAL_MALFUNCTION",
                "priority": ticket_priority,
                "estimated_hours": estimated_hours,
                "assigned_technician": assigned_team,
                "inspection_checklist": inspection_steps,
                "primary_hypothesis": primary_hypothesis,
            }

            action = ActionSafetyService.propose_action(
                execution=execution,
                action_type="CREATE_MAINTENANCE_TICKET",
                description=f"Create {ticket_priority} Maintenance Work Order for {machine.code} ({machine.name})",
                payload=action_payload,
                requires_approval=True,
            )

            # 7. Record AgentDecision
            decision = AgentDecision.objects.create(
                execution=execution,
                decision_type="MAINTENANCE_DISPATCH",
                rationale=(
                    f"Evaluated incident {incident.incident_code} on {machine.code}. "
                    f"Suspected root cause: {primary_hypothesis}. "
                    f"Assigned to {assigned_team} with {len(inspection_steps)} inspection steps. "
                    f"Estimated labor: {estimated_hours}h. Proposed Work Order requires manager approval."
                ),
                confidence_score=88.50,
                risk_level="HIGH" if ticket_priority in [TicketPriority.HIGH, TicketPriority.CRITICAL] else "MEDIUM",
                requires_human_approval=True,
            )

            execution.status = AgentExecutionStatus.COMPLETED
            execution.execution_summary = (
                f"Proposed {ticket_priority} Work Order for {machine.code}. "
                f"Assigned: {assigned_team}. Action ID {action.id} queued for approval."
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
            }

        except Exception as exc:
            logger.exception("Error in MaintenanceCoordinatorAgent: %s", exc)
            execution.status = AgentExecutionStatus.FAILED
            execution.execution_summary = f"Maintenance coordination failed: {str(exc)}"
            execution.completed_at = timezone.now()
            execution.save()
            return {"success": False, "error": str(exc)}
