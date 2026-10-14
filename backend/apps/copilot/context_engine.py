"""
Texora AI - Factory Context Engine (Phase 14)
Provides bounded, validated, strictly read-only retrieval tools over existing
Django domain models (Machines, Incidents, Maintenance, Inventory, Approvals,
Digital Twin, AI Agents, Audit Logs, and Production).

Guarantees:
- Strictly read-only queries (SELECTs only).
- Bounded result sets ([:10] or [:5] caps).
- Validated parameter inputs (regex sanitization).
- Zero arbitrary SQL or Python execution.
- Clear simulation metadata annotations.
"""

import re
import logging
from typing import Dict, Any, List, Optional
from django.db.models import Avg, Count, Q, Sum
from django.utils import timezone

from apps.machines.models import Machine, MachineTelemetry, MachineOperatingLimits, MachineStatus
from apps.incidents.models import FactoryIncident, AnomalyDetection, IncidentStatus
from apps.maintenance.models import MaintenanceTicket, TicketStatus, VerificationStatus
from apps.inventory.models import InventoryItem
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.ai_agents.models import AgentExecution, AgentDecision, AgentAction, RecoveryCase
from apps.digital_twin.models import DigitalTwinSnapshot
from apps.production.models import (
    ProductionOrder,
    ProductionBatch,
    ProductionBottleneck,
    ProductionImpactAssessment,
    ProductionCapacityProfile,
    DelayRiskLevel,
    OrderStatus,
)
from apps.production.capacity_engine import CapacityIntelligenceEngine

logger = logging.getLogger(__name__)

# Sanitization regex: allows alphanumeric, hyphens, underscores, dots, spaces (up to 64 chars)
SAFE_IDENTIFIER_REGEX = re.compile(r"^[A-Za-z0-9\-_.\s]{1,64}$")


def _sanitize_identifier(value: Optional[str]) -> str:
    """Sanitizes user-provided identifier to prevent query injection or abnormal string payloads."""
    if not value or not isinstance(value, str):
        return ""
    cleaned = value.strip()
    if SAFE_IDENTIFIER_REGEX.match(cleaned):
        return cleaned
    return ""


class FactoryContextEngine:
    """
    Unified read-only context retrieval engine for the Factory AI Copilot.
    Extracts structured, grounded evidence across factory operational layers.
    """

    SIMULATION_DISCLOSURE = (
        "Notice: Telemetry, operational metrics, and incident records are "
        "simulated industrial demonstration data for Texora AI."
    )

    @classmethod
    def get_factory_health_summary(cls) -> Dict[str, Any]:
        """Returns a high-level summary of factory-wide operational status."""
        total_machines = Machine.objects.filter(is_active=True).count()
        operational_count = Machine.objects.filter(is_active=True, status=MachineStatus.OPERATIONAL).count()
        warning_count = Machine.objects.filter(is_active=True, status=MachineStatus.WARNING).count()
        critical_count = Machine.objects.filter(is_active=True, status=MachineStatus.CRITICAL).count()
        maintenance_count = Machine.objects.filter(is_active=True, status=MachineStatus.MAINTENANCE).count()
        avg_health = Machine.objects.filter(is_active=True).aggregate(avg_h=Avg("current_health_score"))["avg_h"] or 0.0

        active_incidents = FactoryIncident.objects.filter(
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING]
        ).count()
        open_tickets = MaintenanceTicket.objects.exclude(
            status__in=[TicketStatus.CLOSED, TicketStatus.RESOLVED, TicketStatus.CANCELLED]
        ).count()
        pending_approvals = ApprovalRequest.objects.filter(status=ApprovalStatus.PENDING).count()
        low_stock_items = [item.item_code for item in InventoryItem.objects.filter(is_active=True)[:25] if item.is_low_stock]

        # Recent incidents summary
        recent_incidents = [
            {
                "incident_code": inc.incident_code,
                "machine_code": inc.machine.code if inc.machine else "FACTORY",
                "severity": inc.severity,
                "status": inc.status,
                "summary": inc.summary,
            }
            for inc in FactoryIncident.objects.order_by("-detected_at")[:5]
        ]

        return {
            "entity": "factory_summary",
            "is_simulated": True,
            "simulation_disclosure": cls.SIMULATION_DISCLOSURE,
            "metrics": {
                "total_machines": total_machines,
                "operational_machines": operational_count,
                "warning_machines": warning_count,
                "critical_machines": critical_count,
                "maintenance_machines": maintenance_count,
                "average_health_score": round(float(avg_health), 1),
                "active_incidents_count": active_incidents,
                "open_maintenance_tickets_count": open_tickets,
                "pending_approvals_count": pending_approvals,
                "low_stock_parts_count": len(low_stock_items),
            },
            "recent_incidents": recent_incidents,
            "low_stock_items": low_stock_items[:5],
        }

    @classmethod
    def get_machine_status_and_telemetry(cls, machine_code: str) -> Optional[Dict[str, Any]]:
        """Retrieves machine status, limits, and recent 5 telemetry readings."""
        sanitized_code = _sanitize_identifier(machine_code)
        if not sanitized_code:
            return None

        machine = Machine.objects.filter(code__iexact=sanitized_code).first()
        if not machine:
            return None

        # Fetch operating limits if available
        limits_data = None
        limits = getattr(machine, "operating_limits", None)
        if limits:
            limits_data = {
                "warning_temp_c": limits.warning_temp_c,
                "max_temp_c": limits.max_temp_c,
                "warning_vibration_mms": limits.warning_vibration_mms,
                "max_vibration_mms": limits.max_vibration_mms,
            }

        # Recent 5 readings
        readings = []
        for tel in machine.telemetry_readings.order_by("-timestamp")[:5]:
            readings.append({
                "timestamp": tel.timestamp.isoformat(),
                "temperature_c": tel.temperature_c,
                "vibration_mms": tel.vibration_mms,
                "speed_rpm": tel.speed_rpm,
                "power_kw": tel.power_kw,
                "status_flag": tel.status_flag,
            })

        # Active incident on machine if any
        active_inc = machine.incidents.filter(
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING]
        ).first()

        # Active work order on machine if any
        active_ticket = machine.maintenance_tickets.exclude(
            status__in=[TicketStatus.CLOSED, TicketStatus.RESOLVED, TicketStatus.CANCELLED]
        ).first()

        return {
            "entity": "machine",
            "is_simulated": True,
            "machine_code": machine.code,
            "name": machine.name,
            "department": machine.department.name if machine.department else "",
            "department_code": machine.department.code if machine.department else "",
            "status": machine.status,
            "current_health_score": float(machine.current_health_score),
            "rated_speed_rpm": machine.rated_speed_rpm,
            "operating_limits": limits_data,
            "active_incident_code": active_inc.incident_code if active_inc else None,
            "active_ticket_number": active_ticket.ticket_number if active_ticket else None,
            "recent_readings": readings,
            "simulation_disclosure": cls.SIMULATION_DISCLOSURE,
        }

    @classmethod
    def get_machine_anomaly_history(cls, machine_code: str) -> List[Dict[str, Any]]:
        """Retrieves recent 10 detected anomalies for a given machine."""
        sanitized_code = _sanitize_identifier(machine_code)
        if not sanitized_code:
            return []

        anomalies = AnomalyDetection.objects.filter(
            machine__code__iexact=sanitized_code
        ).order_by("-detected_at")[:10]

        results = []
        for anom in anomalies:
            results.append({
                "anomaly_id": anom.id,
                "metric_name": anom.metric_name,
                "observed_value": anom.observed_value,
                "expected_threshold": anom.threshold_value,
                "anomaly_score": anom.anomaly_score,
                "confidence_score": float(anom.confidence_pct),
                "detected_at": anom.detected_at.isoformat(),
                "incident_code": anom.incident.incident_code if anom.incident else None,
            })
        return results

    @classmethod
    def get_incident_details(cls, incident_code: str) -> Optional[Dict[str, Any]]:
        """Retrieves full incident timeline, anomalies, and active status."""
        sanitized_code = _sanitize_identifier(incident_code)
        if not sanitized_code:
            return None

        incident = FactoryIncident.objects.filter(incident_code__iexact=sanitized_code).first()
        if not incident:
            return None

        # Anomalies
        anomalies_list = [
            {
                "metric": a.metric_name,
                "observed": a.observed_value,
                "threshold": a.threshold_value,
                "anomaly_score": a.anomaly_score,
            }
            for a in incident.anomalies.all()[:5]
        ]

        # Linked approvals
        approvals = [
            {
                "approval_code": app.approval_code,
                "title": app.title,
                "status": app.status,
                "requested_by_agent": app.requested_by_agent,
                "approved_by": app.approved_by,
            }
            for app in incident.approval_requests.all()[:5]
        ]

        # Linked tickets
        linked_ticket = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).first()

        return {
            "entity": "incident",
            "is_simulated": True,
            "incident_code": incident.incident_code,
            "machine_code": incident.machine.code if incident.machine else "FACTORY",
            "department": incident.department.name if incident.department else "",
            "severity": incident.severity,
            "status": incident.status,
            "category": incident.category,
            "summary": incident.summary,
            "root_cause_hypothesis": incident.root_cause_hypothesis,
            "detected_at": incident.detected_at.isoformat(),
            "resolved_at": incident.resolved_at.isoformat() if incident.resolved_at else None,
            "resolution_summary": incident.resolution_summary,
            "anomalies": anomalies_list,
            "approvals": approvals,
            "linked_ticket_number": linked_ticket.ticket_number if linked_ticket else None,
            "simulation_disclosure": cls.SIMULATION_DISCLOSURE,
        }

    @classmethod
    def get_agent_findings(cls, machine_code: Optional[str] = None, incident_code: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves structured conclusions from the four specialist AI agents."""
        qs = AgentExecution.objects.all()

        if incident_code:
            qs = qs.filter(incident__incident_code__iexact=_sanitize_identifier(incident_code))
        elif machine_code:
            qs = qs.filter(incident__machine__code__iexact=_sanitize_identifier(machine_code))

        executions = qs.select_related("agent", "incident").order_by("-started_at")[:8]

        findings = []
        for exe in executions:
            decisions = [
                {
                    "decision_type": d.decision_type,
                    "title": d.title,
                    "confidence_score": d.confidence_score,
                    "reasoning": d.reasoning,
                }
                for d in exe.decisions.all()[:3]
            ]
            actions = [
                {
                    "action_code": a.action_code,
                    "action_type": a.action_type,
                    "description": a.description,
                    "status": a.status,
                    "requires_approval": a.requires_human_approval,
                }
                for a in exe.actions.all()[:3]
            ]
            findings.append({
                "execution_id": str(exe.execution_id),
                "agent_name": exe.agent.name,
                "agent_type": exe.agent.agent_type,
                "incident_code": exe.incident.incident_code if exe.incident else None,
                "status": exe.status,
                "summary": exe.execution_summary,
                "decisions": decisions,
                "actions": actions,
                "started_at": exe.started_at.isoformat(),
            })
        return findings

    @classmethod
    def get_maintenance_history(cls, machine_code: Optional[str] = None, ticket_number: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves recent maintenance tickets, repair details, and verification status."""
        qs = MaintenanceTicket.objects.select_related("machine")

        if ticket_number:
            qs = qs.filter(ticket_number__iexact=_sanitize_identifier(ticket_number))
        elif machine_code:
            qs = qs.filter(machine__code__iexact=_sanitize_identifier(machine_code))

        tickets = qs.order_by("-created_at")[:6]

        results = []
        for t in tickets:
            results.append({
                "ticket_number": t.ticket_number,
                "machine_code": t.machine.code,
                "title": t.title,
                "priority": t.priority,
                "status": t.status,
                "assigned_technician": t.assigned_technician,
                "confirmed_fault": t.confirmed_fault,
                "repair_performed": t.repair_performed,
                "parts_replaced": t.parts_replaced,
                "parts_cost": float(t.parts_cost),
                "verification_status": t.verification_status,
                "verification_summary": t.verification_summary,
                "authorized_signoff_by": t.authorized_signoff_by,
                "created_at": t.created_at.isoformat(),
            })
        return results

    @classmethod
    def get_inventory_status(cls, query_or_code: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves spare-part inventory availability and stock levels."""
        qs = InventoryItem.objects.filter(is_active=True)

        if query_or_code:
            clean = _sanitize_identifier(query_or_code)
            qs = qs.filter(Q(item_code__icontains=clean) | Q(name__icontains=clean))

        items = qs.order_by("category", "name")[:10]

        results = []
        for itm in items:
            results.append({
                "item_code": itm.item_code,
                "name": itm.name,
                "category": itm.category,
                "current_stock": float(itm.current_stock),
                "minimum_safety_stock": float(itm.minimum_safety_stock),
                "reorder_point": float(itm.reorder_point),
                "unit": itm.unit,
                "unit_cost": float(itm.unit_cost),
                "is_low_stock": itm.is_low_stock,
                "location_shelf": itm.location_shelf,
            })
        return results

    @classmethod
    def get_production_impact(cls, machine_code: Optional[str] = None) -> Dict[str, Any]:
        """Estimates production schedule impact for a machine or department."""
        sanitized_code = _sanitize_identifier(machine_code)
        if not sanitized_code:
            # Factory-wide active orders
            active_orders = ProductionOrder.objects.filter(
                status__in=["PLANNED", "IN_PROGRESS", "PAUSED"]
            ).order_by("-due_date")[:5]
            return {
                "scope": "factory",
                "active_orders": [
                    {
                        "order_number": o.order_number,
                        "client_name": o.client_name,
                        "fabric": o.fabric_or_yarn_spec,
                        "department": o.department.name if o.department else "",
                        "progress_pct": round(o.progress_pct, 1),
                        "priority": o.priority,
                        "due_date": o.due_date.isoformat(),
                    }
                    for o in active_orders
                ],
            }

        machine = Machine.objects.filter(code__iexact=sanitized_code).first()
        if not machine:
            return {"error": f"Machine {sanitized_code} not found"}

        # Orders in machine's department
        dept_orders = ProductionOrder.objects.filter(
            department=machine.department,
            status__in=["PLANNED", "IN_PROGRESS", "PAUSED"],
        ).order_by("-priority")[:5]

        # Active batches
        active_batches = ProductionBatch.objects.filter(
            production_order__department=machine.department
        ).order_by("-created_at")[:3]

        return {
            "scope": "machine",
            "machine_code": machine.code,
            "department": machine.department.name if machine.department else "",
            "rated_capacity_per_hour": float(machine.rated_capacity_units_per_hour),
            "department_orders": [
                {
                    "order_number": o.order_number,
                    "client_name": o.client_name,
                    "fabric": o.fabric_or_yarn_spec,
                    "progress_pct": round(o.progress_pct, 1),
                    "due_date": o.due_date.isoformat(),
                }
                for o in dept_orders
            ],
            "active_batches": [b.batch_number for b in active_batches],
        }

    @classmethod
    def get_digital_twin_recovery_strategies(cls, machine_code: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves evaluated Digital Twin recovery scenarios and ranked strategies."""
        qs = RecoveryCase.objects.select_related("incident", "machine").order_by("-created_at")
        if machine_code:
            qs = qs.filter(machine__code__iexact=_sanitize_identifier(machine_code))

        cases = qs[:5]
        results = []
        for c in cases:
            payload = c.recommendation_payload or {}
            strats_eval = payload.get("strategies_evaluated") or []
            prod_loss = payload.get("estimated_production_loss_inr") or 0.0
            results.append({
                "case_id": c.case_code,
                "case_code": c.case_code,
                "incident_code": c.incident.incident_code if c.incident else None,
                "machine_code": c.machine.code if c.machine else None,
                "recommended_strategy": c.recommended_strategy,
                "status": c.status,
                "strategies_evaluated": strats_eval,
                "production_loss_inr": float(prod_loss),
                "created_at": c.created_at.isoformat(),
            })
        return results

    @classmethod
    def get_approval_requests(cls, incident_code: Optional[str] = None, status: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves manager approval requests and governance decisions."""
        qs = ApprovalRequest.objects.select_related("incident").order_by("-created_at")
        if incident_code:
            qs = qs.filter(incident__incident_code__iexact=_sanitize_identifier(incident_code))
        if status:
            qs = qs.filter(status=status)

        approvals = qs[:10]
        results = []
        for app in approvals:
            results.append({
                "approval_code": app.approval_code,
                "incident_code": app.incident.incident_code if app.incident else None,
                "title": app.title,
                "requested_action": app.requested_action,
                "risk_level": app.risk_level,
                "status": app.status,
                "requested_by_agent": app.requested_by_agent,
                "approved_by": app.approved_by,
                "response_notes": app.response_notes,
                "created_at": app.created_at.isoformat(),
            })
        return results

    @classmethod
    def get_recovery_verification_results(cls, query: str) -> Optional[Dict[str, Any]]:
        """Retrieves multi-sample post-repair verification evidence and signoff."""
        clean = _sanitize_identifier(query)
        if not clean:
            return None

        # Look up by ticket number or machine code
        ticket = (
            MaintenanceTicket.objects.filter(ticket_number__iexact=clean).first()
            or MaintenanceTicket.objects.filter(machine__code__iexact=clean).order_by("-created_at").first()
        )
        if not ticket:
            return None

        return {
            "entity": "verification_result",
            "is_simulated": True,
            "ticket_number": ticket.ticket_number,
            "machine_code": ticket.machine.code,
            "ticket_status": ticket.status,
            "verification_status": ticket.verification_status,
            "verification_summary": ticket.verification_summary,
            "verification_data": ticket.verification_data,
            "authorized_signoff_by": ticket.authorized_signoff_by,
            "authorized_signoff_at": ticket.authorized_signoff_at.isoformat() if ticket.authorized_signoff_at else None,
            "signoff_notes": ticket.signoff_notes,
            "simulation_disclosure": cls.SIMULATION_DISCLOSURE,
        }

    @classmethod
    def get_production_overview(cls) -> Dict[str, Any]:
        """Retrieves factory-wide textile production metrics, targets, utilization, and bottlenecks."""
        now_date = timezone.now().date()
        dept_caps = CapacityIntelligenceEngine.calculate_department_capacities(target_date=now_date)
        
        total_orders = ProductionOrder.objects.count()
        active_orders = ProductionOrder.objects.filter(status=OrderStatus.IN_PROGRESS).count()
        at_risk_orders = ProductionOrder.objects.filter(
            delay_risk_level__in=[DelayRiskLevel.HIGH, DelayRiskLevel.CRITICAL]
        )
        at_risk_count = at_risk_orders.count()

        tot_target = float(ProductionOrder.objects.filter(
            status__in=[OrderStatus.IN_PROGRESS, OrderStatus.PLANNED, OrderStatus.PAUSED]
        ).aggregate(tot=Sum("target_quantity"))["tot"] or 0.0)

        tot_done = float(ProductionOrder.objects.filter(
            status__in=[OrderStatus.IN_PROGRESS, OrderStatus.PLANNED, OrderStatus.PAUSED]
        ).aggregate(tot=Sum("completed_quantity"))["tot"] or 0.0)

        avg_util = round(sum(d["utilization_pct"] for d in dept_caps) / max(1, len(dept_caps)), 1) if dept_caps else 0.0

        bottlenecks = ProductionBottleneck.objects.filter(is_active=True).select_related("department", "machine")[:5]
        b_list = [
            {
                "department": b.department.code,
                "machine": b.machine.code if b.machine else "DEPARTMENT_WIDE",
                "severity": b.severity,
                "cause": b.primary_cause,
                "deficit_per_hr": float(b.throughput_deficit_units_per_hour),
            }
            for b in bottlenecks
        ]

        at_risk_summaries = [
            {
                "order_number": o.order_number,
                "client_name": o.client_name,
                "due_date": o.due_date.isoformat(),
                "delay_risk_level": o.delay_risk_level,
                "estimated_delay_hours": float(o.estimated_delay_hours),
            }
            for o in at_risk_orders[:5]
        ]

        return {
            "entity": "production_overview",
            "is_simulated": True,
            "simulation_disclosure": cls.SIMULATION_DISCLOSURE,
            "total_orders": total_orders,
            "active_orders": active_orders,
            "at_risk_orders_count": at_risk_count,
            "total_target_units": tot_target,
            "total_completed_units": tot_done,
            "progress_pct": round((tot_done / max(1.0, tot_target)) * 100.0, 1),
            "plant_utilization_pct": avg_util,
            "department_capacities": dept_caps,
            "at_risk_orders": at_risk_summaries,
            "active_bottlenecks": b_list,
        }

    @classmethod
    def get_orders_at_risk(cls) -> List[Dict[str, Any]]:
        """Retrieves active customer orders threatened by machine failure or deadline delay."""
        now_date = timezone.now().date()
        orders = ProductionOrder.objects.filter(
            status__in=[OrderStatus.IN_PROGRESS, OrderStatus.PAUSED, OrderStatus.PLANNED],
            delay_risk_level__in=[DelayRiskLevel.HIGH, DelayRiskLevel.CRITICAL],
        ).select_related("department")[:10]

        results = []
        for o in orders:
            days_until_due = (o.due_date - now_date).days if o.due_date else 0
            results.append({
                "order_number": o.order_number,
                "client_name": o.client_name,
                "spec": o.fabric_or_yarn_spec,
                "department": o.department.code,
                "target_quantity": float(o.target_quantity),
                "completed_quantity": float(o.completed_quantity),
                "remaining_quantity": float(o.remaining_quantity),
                "progress_pct": o.progress_pct,
                "due_date": o.due_date.isoformat() if o.due_date else None,
                "days_until_due": days_until_due,
                "delay_risk_level": o.delay_risk_level,
                "delay_risk_score": float(o.delay_risk_score),
                "estimated_delay_hours": float(o.estimated_delay_hours),
                "is_simulated": True,
            })
        return results

    @classmethod
    def get_production_bottlenecks(cls) -> List[Dict[str, Any]]:
        """Retrieves active bottlenecks across factory production departments."""
        bottlenecks = ProductionBottleneck.objects.filter(is_active=True).select_related("department", "machine")[:8]
        results = []
        for b in bottlenecks:
            results.append({
                "department_code": b.department.code,
                "department_name": b.department.name,
                "machine_code": b.machine.code if b.machine else None,
                "bottleneck_type": b.bottleneck_type,
                "severity": b.severity,
                "primary_cause": b.primary_cause,
                "affected_orders_count": b.affected_orders_count,
                "estimated_delay_hours": float(b.estimated_delay_impact_hours),
                "throughput_deficit_per_hr": float(b.throughput_deficit_units_per_hour),
                "is_simulated": True,
            })
        return results

    @classmethod
    def get_machine_production_impact(cls, machine_code: Optional[str] = None) -> List[Dict[str, Any]]:
        """Retrieves latest production impact assessment for a machine or plant-wide."""
        qs = ProductionImpactAssessment.objects.filter(is_latest=True).select_related("machine", "incident")
        if machine_code:
            clean = _sanitize_identifier(machine_code)
            if clean:
                qs = qs.filter(machine__code__iexact=clean)
        
        assessments = qs[:5]
        results = []
        for a in assessments:
            results.append({
                "assessment_code": a.assessment_code,
                "machine_code": a.machine.code,
                "machine_name": a.machine.name,
                "incident_code": a.incident.incident_code if a.incident else None,
                "estimated_downtime_hours": float(a.estimated_downtime_hours),
                "output_quantity_at_risk": float(a.output_quantity_at_risk),
                "orders_affected_count": a.orders_affected_count,
                "overall_delay_risk": a.overall_delay_risk,
                "deterministic_loss_inr": float(a.deterministic_loss_inr),
                "ai_explanation": a.ai_explanation,
                "recommendations": a.recommendations,
                "alternate_capacities": a.alternate_capacities,
                "is_simulated": True,
                "simulation_disclosure": cls.SIMULATION_DISCLOSURE,
            })
        return results
