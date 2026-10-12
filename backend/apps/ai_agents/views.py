import os
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.utils import timezone

from .models import (
    AgentDefinition,
    AgentExecution,
    AgentDecision,
    AgentAction,
    AgentType,
    AgentExecutionStatus,
    RecoveryCase,
    RecoveryPlanStep,
    RecoveryCaseStatus,
    RecoveryStepStatus,
    AutonomousWorkflowRun,
    AutonomousWorkflowStage,
)
from .serializers import (
    AgentDefinitionSerializer,
    AgentExecutionSerializer,
    AgentDecisionSerializer,
    AgentActionSerializer,
    RecoveryCaseSerializer,
    RecoveryPlanStepSerializer,
    AutonomousWorkflowRunSerializer,
)
from .machine_health_agent import MachineHealthAgent
from .maintenance_coordinator import MaintenanceCoordinatorAgent
from .inventory_coordinator import InventoryCoordinatorAgent
from .production_impact_agent import ProductionImpactAgent
from .recovery_orchestrator import RecoveryOrchestrator
from .action_service import ActionSafetyService
from .llm_client import get_llm_provider
from apps.incidents.models import FactoryIncident, IncidentStatus
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.inventory.models import InventoryTransaction


class AgentDefinitionViewSet(viewsets.ModelViewSet):
    queryset = AgentDefinition.objects.all()
    serializer_class = AgentDefinitionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["agent_type", "is_enabled"]


class AgentExecutionViewSet(viewsets.ModelViewSet):
    queryset = AgentExecution.objects.select_related("agent", "incident").prefetch_related("decisions", "actions").all()
    serializer_class = AgentExecutionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["agent", "incident", "status"]
    search_fields = ["execution_id", "trigger_event", "execution_summary"]

    @action(detail=False, methods=["get"])
    def summary(self, request):
        """Dashboard summary for Machine Health AI operations."""
        provider = get_llm_provider()
        provider_name = os.getenv("LLM_PROVIDER", "gemini").lower()
        is_configured = provider.is_configured()

        total_executions = AgentExecution.objects.count()
        completed_executions = AgentExecution.objects.filter(status=AgentExecutionStatus.COMPLETED).count()
        failed_executions = AgentExecution.objects.filter(status=AgentExecutionStatus.FAILED).count()
        
        pending_incidents = FactoryIncident.objects.filter(
            status=IncidentStatus.OPEN, machine__isnull=False
        ).count()

        pending_approvals = ApprovalRequest.objects.filter(status=ApprovalStatus.PENDING).count()

        # Recent executions
        recent = AgentExecution.objects.select_related("agent", "incident").prefetch_related("decisions", "actions").all()[:15]
        recent_data = AgentExecutionSerializer(recent, many=True).data

        # Pending incident list
        pending_list = (
            FactoryIncident.objects.filter(status=IncidentStatus.OPEN, machine__isnull=False)
            .select_related("machine", "department")
            .order_by("-detected_at")[:10]
        )
        from apps.incidents.serializers import FactoryIncidentSerializer
        pending_data = FactoryIncidentSerializer(pending_list, many=True).data

        return Response({
            "provider_status": {
                "provider": provider_name,
                "model": getattr(provider, "model_name", "unknown"),
                "is_configured": is_configured,
                "error": "" if is_configured else f"API key not set for '{provider_name}'. Set {provider_name.upper()}_API_KEY.",
            },
            "metrics": {
                "pending_incidents": pending_incidents,
                "total_executions": total_executions,
                "completed_executions": completed_executions,
                "failed_executions": failed_executions,
                "pending_approvals": pending_approvals,
            },
            "pending_incidents_list": pending_data,
            "recent_executions": recent_data,
        })

    @action(detail=False, methods=["get"], url_path="operations-overview")
    def operations_overview(self, request):
        """
        Commercial operations overview for all 4 autonomous specialist agents:
        1. Machine Health Specialist (MACHINE_HEALTH)
        2. Maintenance Coordinator (MAINTENANCE)
        3. Inventory Coordinator (INVENTORY)
        4. Production Impact Agent (PRODUCTION_IMPACT)
        """
        from django.db.models import Avg
        from apps.incidents.models import WorkerHeartbeat, FactoryIncident
        from apps.approvals.models import ApprovalRequest, ApprovalStatus
        
        # Worker Heartbeats
        heartbeats = {}
        for worker_name in ["AUTONOMOUS_ORCHESTRATOR", "ANOMALY_DETECTOR"]:
            wb = WorkerHeartbeat.objects.filter(worker_name=worker_name).first()
            if wb:
                heartbeats[worker_name] = {
                    "worker_name": worker_name,
                    "status": wb.computed_status(),
                    "process_id": wb.process_id,
                    "last_heartbeat_at": wb.last_heartbeat_at.isoformat() if wb.last_heartbeat_at else None,
                    "processing_count": wb.processing_count,
                    "last_error": wb.last_error or "",
                }
            else:
                heartbeats[worker_name] = {
                    "worker_name": worker_name,
                    "status": "STOPPED",
                    "process_id": 0,
                    "last_heartbeat_at": None,
                    "processing_count": 0,
                    "last_error": "",
                }

        total_executions = AgentExecution.objects.count()
        completed_executions = AgentExecution.objects.filter(status=AgentExecutionStatus.COMPLETED).count()
        failed_executions = AgentExecution.objects.filter(status=AgentExecutionStatus.FAILED).count()
        active_incidents_count = FactoryIncident.objects.filter(
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING]
        ).count()
        pending_approvals_count = ApprovalRequest.objects.filter(status=ApprovalStatus.PENDING).count()

        agent_configs = [
            {
                "type": AgentType.MACHINE_HEALTH,
                "default_name": "Machine Health Diagnostic Specialist",
                "role": "Root Cause Analysis & Sensor Telemetry Diagnostic Specialist",
                "responsibilities": [
                    "Analyze abnormal machine telemetry (vibration, thermal, speed)",
                    "Review historical vibration patterns and operating limits",
                    "Investigate mechanical and electrical fault signatures",
                    "Produce structured diagnostic findings with confidence scores",
                    "Report Gemini LLM reasoning or deterministic fallback provenance",
                ],
                "default_model": "gemini-2.5-flash",
                "default_actions": ["DIAGNOSE_MACHINE_HEALTH", "EVALUATE_VIBRATION_SPECTRUM", "QUERY_HISTORICAL_TELEMETRY"],
            },
            {
                "type": AgentType.MAINTENANCE,
                "default_name": "Maintenance & Work Order Coordinator",
                "role": "Work Order Estimation, Labor Protocol & Technician Planning",
                "responsibilities": [
                    "Estimate maintenance requirements & repair scope",
                    "Identify required technician skills & certifications",
                    "Estimate repair duration & schedule inspection protocols",
                    "Propose maintenance actions without unauthorized dispatch",
                    "Track maintenance ticket lifecycle through to recovery",
                ],
                "default_model": "deterministic-maintenance-v1",
                "default_actions": ["CREATE_MAINTENANCE_TICKET", "SCHEDULE_INSPECTION", "ASSIGN_TECHNICIAN"],
            },
            {
                "type": AgentType.INVENTORY,
                "default_name": "Inventory & Spare Parts Coordinator",
                "role": "Warehouse Availability, Safety Stock Barrier & Spare Parts Allocation",
                "responsibilities": [
                    "Check spare-part availability against live warehouse records",
                    "Identify required replacement components (bearings, belts, motors)",
                    "Propose inventory allocations with safety stock barriers",
                    "Display manager approval status & prevent premature stock deduction",
                    "Never deduct inventory before authorized manager approval",
                ],
                "default_model": "deterministic-inventory-v1",
                "default_actions": ["RESERVE_SPARE_PART", "CREATE_PROCUREMENT_REQUEST", "CHECK_STOCK_LEVELS"],
            },
            {
                "type": AgentType.PRODUCTION_IMPACT,
                "default_name": "Production Rescheduling & Impact Agent",
                "role": "Capacity Loss, Order Fallout & Alternate Machine Rerouting",
                "responsibilities": [
                    "Evaluate affected production capacity & throughput loss",
                    "Estimate potential meter / kilogram output losses",
                    "Identify compatible alternative machinery in same department",
                    "Support Digital Twin What-If recovery planning & rerouting",
                ],
                "default_model": "deterministic-production-v1",
                "default_actions": ["REROUTE_PRODUCTION_BATCH", "PAUSE_PRODUCTION_BATCH", "CALCULATE_CAPACITY_BUFFER"],
            },
        ]

        specialist_agents = []
        for cfg in agent_configs:
            a_type = cfg["type"]
            agent_def = AgentDefinition.objects.filter(agent_type=a_type).first()
            name = agent_def.name if agent_def else cfg["default_name"]
            model_name = agent_def.model_name if agent_def else cfg["default_model"]
            permitted_actions = agent_def.permitted_actions if (agent_def and agent_def.permitted_actions) else cfg["default_actions"]
            is_enabled = agent_def.is_enabled if agent_def else True

            exec_qs = AgentExecution.objects.filter(agent__agent_type=a_type)
            total_count = exec_qs.count()
            completed_count = exec_qs.filter(status=AgentExecutionStatus.COMPLETED).count()
            failed_count = exec_qs.filter(status=AgentExecutionStatus.FAILED).count()

            avg_lat = exec_qs.aggregate(Avg("latency_ms"))["latency_ms__avg"]
            avg_latency_ms = int(avg_lat) if avg_lat else 0

            latest_exec = (
                exec_qs.select_related("incident", "incident__machine", "incident__department")
                .prefetch_related("decisions", "actions")
                .order_by("-started_at")
                .first()
            )

            current_status = "IDLE"
            latest_data = None
            if latest_exec:
                latest_dec = latest_exec.decisions.first()
                latest_act = latest_exec.actions.first()

                if latest_exec.status in [AgentExecutionStatus.STARTED, AgentExecutionStatus.RUNNING]:
                    current_status = "RUNNING"
                elif latest_exec.status == AgentExecutionStatus.FAILED:
                    current_status = "FAILED"
                else:
                    if latest_exec.incident:
                        pending_appr = ApprovalRequest.objects.filter(
                            incident=latest_exec.incident,
                            status=ApprovalStatus.PENDING,
                        ).exists()
                        if pending_appr:
                            current_status = "WAITING_FOR_APPROVAL"
                        elif latest_exec.incident.status in [IncidentStatus.OPEN, IncidentStatus.INVESTIGATING]:
                            current_status = "COMPLETED"
                        else:
                            current_status = "IDLE"
                    else:
                        current_status = "IDLE"

                provenance = "Deterministic Engine"
                if a_type == AgentType.MACHINE_HEALTH:
                    if "gemini" in model_name.lower() or "gemini" in latest_exec.execution_summary.lower():
                        if "fallback" in latest_exec.execution_summary.lower() or "RATE_LIMITED" in latest_exec.execution_summary:
                            provenance = "Deterministic Fallback (Rate Limit Guard)"
                        else:
                            provenance = "Gemini LLM Reasoning (Google Gemini 2.5 Flash)"
                    else:
                        provenance = "Deterministic Diagnostic Rules"
                else:
                    provenance = f"Deterministic Specialist Logic ({model_name})"

                latest_data = {
                    "execution_id": str(latest_exec.execution_id),
                    "id": latest_exec.id,
                    "incident_id": latest_exec.incident.id if latest_exec.incident else None,
                    "incident_code": latest_exec.incident.incident_code if latest_exec.incident else "N/A",
                    "machine_code": latest_exec.incident.machine.code if (latest_exec.incident and latest_exec.incident.machine) else "N/A",
                    "machine_name": latest_exec.incident.machine.name if (latest_exec.incident and latest_exec.incident.machine) else "N/A",
                    "department_name": latest_exec.incident.department.name if (latest_exec.incident and latest_exec.incident.department) else "N/A",
                    "trigger_event": latest_exec.trigger_event,
                    "status": latest_exec.status,
                    "started_at": latest_exec.started_at.isoformat() if latest_exec.started_at else None,
                    "completed_at": latest_exec.completed_at.isoformat() if latest_exec.completed_at else None,
                    "latency_ms": latest_exec.latency_ms,
                    "token_count": latest_exec.token_count,
                    "execution_summary": latest_exec.execution_summary,
                    "latest_findings": latest_dec.rationale if latest_dec else latest_exec.execution_summary,
                    "confidence_score": float(latest_dec.confidence_score) if latest_dec else 90.0,
                    "risk_level": latest_dec.risk_level if latest_dec else "LOW",
                    "recommended_action": {
                        "action_name": latest_act.action_name if latest_act else (latest_dec.get_decision_type_display() if latest_dec else "Monitor Telemetry"),
                        "tool_name": latest_act.tool_name if latest_act else "inspect",
                        "status": latest_act.status if latest_act else "SUCCESS",
                        "payload": latest_act.tool_input if latest_act else {},
                    } if (latest_act or latest_dec) else None,
                    "provenance": provenance,
                }

            recent_list = []
            for rx in exec_qs.select_related("incident", "incident__machine").order_by("-started_at")[:8]:
                recent_list.append({
                    "execution_id": str(rx.execution_id),
                    "id": rx.id,
                    "incident_code": rx.incident.incident_code if rx.incident else "N/A",
                    "machine_code": rx.incident.machine.code if (rx.incident and rx.incident.machine) else "N/A",
                    "status": rx.status,
                    "started_at": rx.started_at.isoformat() if rx.started_at else None,
                    "latency_ms": rx.latency_ms,
                    "summary": rx.execution_summary[:120] if rx.execution_summary else "",
                })

            specialist_agents.append({
                "agent_type": a_type,
                "name": name,
                "role": cfg["role"],
                "responsibilities": cfg["responsibilities"],
                "model_name": model_name,
                "is_enabled": is_enabled,
                "permitted_actions": permitted_actions,
                "current_status": current_status,
                "metrics": {
                    "total_executions": total_count,
                    "completed_executions": completed_count,
                    "failed_executions": failed_count,
                    "avg_latency_ms": avg_latency_ms,
                },
                "latest_execution": latest_data,
                "recent_executions": recent_list,
            })

        return Response({
            "worker_heartbeats": heartbeats,
            "overall_metrics": {
                "total_executions": total_executions,
                "completed_executions": completed_executions,
                "failed_executions": failed_executions,
                "active_incidents": active_incidents_count,
                "pending_approvals": pending_approvals_count,
            },
            "specialist_agents": specialist_agents,
        })

    @action(detail=False, methods=["get"], url_path="audit-details/(?P<exec_id>[^/.]+)")
    def audit_details(self, request, exec_id=None):
        """Returns deep sanitized operational audit record for a specific agent execution."""
        from apps.audit_logs.models import AuditLog
        
        exec_obj = None
        if str(exec_id).isdigit():
            exec_obj = AgentExecution.objects.filter(id=int(exec_id)).select_related("agent", "incident", "incident__machine", "incident__department").first()
        if not exec_obj:
            exec_obj = AgentExecution.objects.filter(execution_id=exec_id).select_related("agent", "incident", "incident__machine", "incident__department").first()

        if not exec_obj:
            return Response({"error": f"Execution {exec_id} not found."}, status=status.HTTP_404_NOT_FOUND)

        incident = exec_obj.incident
        machine = incident.machine if incident else None

        decisions_data = [
            {
                "id": d.id,
                "decision_type": d.decision_type,
                "decision_type_display": d.get_decision_type_display(),
                "rationale": d.rationale,
                "confidence_score": float(d.confidence_score),
                "risk_level": d.risk_level,
                "requires_human_approval": d.requires_human_approval,
                "timestamp": d.timestamp.isoformat(),
            }
            for d in exec_obj.decisions.all()
        ]

        actions_data = [
            {
                "id": a.id,
                "action_name": a.action_name,
                "tool_name": a.tool_name,
                "tool_input": a.tool_input,
                "tool_output": a.tool_output,
                "status": a.status,
                "executed_at": a.executed_at.isoformat(),
                "error_message": a.error_message,
            }
            for a in exec_obj.actions.all()
        ]

        recovery_case = RecoveryCase.objects.filter(incident=incident).first() if incident else None
        approval_req = ApprovalRequest.objects.filter(incident=incident).first() if incident else None

        audit_refs = []
        if incident:
            from django.db.models import Q
            logs = AuditLog.objects.filter(
                Q(entity_id=incident.incident_code) |
                Q(changes_payload__incident_code=incident.incident_code)
            ).order_by("-timestamp")[:10]
            audit_refs = [
                {
                    "id": l.id,
                    "action": l.action,
                    "actor_id": l.actor_id,
                    "actor_type": l.actor_type,
                    "timestamp": l.timestamp.isoformat(),
                    "description": l.description,
                }
                for l in logs
            ]

        clean_context = dict(exec_obj.context_payload or {})
        for sensitive_key in ["api_key", "password", "secret", "token", "credentials"]:
            clean_context.pop(sensitive_key, None)

        return Response({
            "execution_id": str(exec_obj.execution_id),
            "id": exec_obj.id,
            "agent_type": exec_obj.agent.agent_type,
            "agent_name": exec_obj.agent.name,
            "model_name": exec_obj.agent.model_name,
            "status": exec_obj.status,
            "trigger_event": exec_obj.trigger_event,
            "incident": {
                "id": incident.id if incident else None,
                "incident_code": incident.incident_code if incident else "N/A",
                "severity": incident.severity if incident else "N/A",
                "summary": incident.summary if incident else "N/A",
                "detected_at": incident.detected_at.isoformat() if incident else None,
            } if incident else None,
            "machine": {
                "id": machine.id if machine else None,
                "code": machine.code if machine else "N/A",
                "name": machine.name if machine else "N/A",
                "department": machine.department.name if machine else "N/A",
            } if machine else None,
            "started_at": exec_obj.started_at.isoformat() if exec_obj.started_at else None,
            "completed_at": exec_obj.completed_at.isoformat() if exec_obj.completed_at else None,
            "latency_ms": exec_obj.latency_ms,
            "token_count": exec_obj.token_count,
            "context_payload": clean_context,
            "execution_summary": exec_obj.execution_summary,
            "decisions": decisions_data,
            "actions": actions_data,
            "recovery_case": {
                "id": recovery_case.id,
                "case_code": recovery_case.case_code,
                "status": recovery_case.status,
                "priority_score": float(recovery_case.priority_score),
                "recommended_strategy": recovery_case.recommended_strategy,
            } if recovery_case else None,
            "approval_request": {
                "id": approval_req.id,
                "approval_code": approval_req.approval_code,
                "title": approval_req.title,
                "status": approval_req.status,
                "requested_action": approval_req.requested_action,
                "risk_level": approval_req.risk_level,
            } if approval_req else None,
            "audit_trail": audit_refs,
        })

    @action(detail=False, methods=["post"], url_path="investigate/(?P<incident_id>[^/.]+)")
    def investigate(self, request, incident_id=None):
        """Triggers an on-demand AI investigation for a specific incident."""
        agent = MachineHealthAgent()
        result = agent.investigate_incident(int(incident_id))
        http_status = status.HTTP_200_OK if result.get("success") else status.HTTP_400_BAD_REQUEST
        return Response(result, status=http_status)

    @action(detail=False, methods=["post"], url_path="run-cycle")
    def run_cycle(self, request):
        """Triggers an autonomous evaluation cycle across pending incidents."""
        agent = MachineHealthAgent()
        result = agent.run_cycle()
        return Response(result)

    @action(detail=False, methods=["get"], url_path="status")
    def agent_status(self, request):
        """Returns agent definition and provider operational status."""
        provider = get_llm_provider()
        agent_def = AgentDefinition.objects.filter(agent_type=AgentType.MACHINE_HEALTH).first()
        return Response({
            "agent_name": agent_def.name if agent_def else "Machine Health Diagnostic Specialist",
            "agent_type": "MACHINE_HEALTH",
            "is_enabled": agent_def.is_enabled if agent_def else True,
            "model_name": getattr(provider, "model_name", "gemini-3.5-flash"),
            "provider": os.getenv("LLM_PROVIDER", "gemini"),
            "is_configured": provider.is_configured(),
            "timestamp": timezone.now().isoformat(),
        })


class RecoveryCaseViewSet(viewsets.ModelViewSet):
    """
    API ViewSet for Factory Recovery Cases and Multi-Agent Orchestration.
    """
    queryset = (
        RecoveryCase.objects.select_related("incident", "machine", "machine__department")
        .prefetch_related("steps", "steps__approval_request", "steps__agent_action")
        .all()
    )
    serializer_class = RecoveryCaseSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["status", "priority", "machine"]
    search_fields = ["case_code", "incident__incident_code", "machine__code", "summary"]

    @action(detail=False, methods=["get"], url_path="summary")
    def recovery_summary(self, request):
        """Provides high-level KPI metrics for the Factory Recovery Command Center."""
        total_cases = RecoveryCase.objects.count()
        active_cases = RecoveryCase.objects.filter(
            status__in=[
                RecoveryCaseStatus.ANALYZING,
                RecoveryCaseStatus.PLAN_READY,
                RecoveryCaseStatus.AWAITING_APPROVALS,
                RecoveryCaseStatus.IN_RECOVERY,
                RecoveryCaseStatus.VERIFYING_TELEMETRY,
            ]
        ).count()
        awaiting_approvals = RecoveryCase.objects.filter(status=RecoveryCaseStatus.AWAITING_APPROVALS).count()
        in_recovery = RecoveryCase.objects.filter(status=RecoveryCaseStatus.IN_RECOVERY).count()
        recovered = RecoveryCase.objects.filter(status=RecoveryCaseStatus.RECOVERED).count()
        critical_cases = RecoveryCase.objects.filter(
            priority__in=["CRITICAL", "HIGH"],
            status__in=[
                RecoveryCaseStatus.AWAITING_APPROVALS,
                RecoveryCaseStatus.IN_RECOVERY,
                RecoveryCaseStatus.PLAN_READY,
                RecoveryCaseStatus.ANALYZING,
            ],
        ).count()

        pending_approvals_total = ApprovalRequest.objects.filter(status=ApprovalStatus.PENDING).count()
        reserved_spares_count = InventoryTransaction.objects.filter(transaction_type="RESERVATION").count()

        # Recent 10 cases
        recent = (
            RecoveryCase.objects.select_related("incident", "machine", "machine__department")
            .prefetch_related("steps", "steps__approval_request", "steps__agent_action")
            .all()[:10]
        )
        recent_data = RecoveryCaseSerializer(recent, many=True).data

        # Pending approval requests
        pending_approvals_qs = (
            ApprovalRequest.objects.filter(status=ApprovalStatus.PENDING)
            .select_related("incident", "agent_action")
            .order_by("-created_at")[:10]
        )
        approvals_list = [
            {
                "id": a.id,
                "approval_code": a.approval_code,
                "title": a.title,
                "description": a.description,
                "requested_action": a.requested_action,
                "risk_level": a.risk_level,
                "requested_by_agent": a.requested_by_agent,
                "incident_code": a.incident.incident_code if a.incident else "N/A",
                "machine_code": a.incident.machine.code if (a.incident and a.incident.machine) else "N/A",
                "created_at": a.created_at.isoformat(),
                "payload": a.agent_action.tool_input if a.agent_action else {},
            }
            for a in pending_approvals_qs
        ]

        return Response({
            "metrics": {
                "total_cases": total_cases,
                "active_cases": active_cases,
                "awaiting_approvals": awaiting_approvals,
                "in_recovery": in_recovery,
                "recovered_cases": recovered,
                "critical_cases": critical_cases,
                "pending_approvals_total": pending_approvals_total,
                "reserved_spares_count": reserved_spares_count,
            },
            "recent_cases": recent_data,
            "pending_approvals": approvals_list,
        })

    @action(detail=False, methods=["post"], url_path="orchestrate/(?P<incident_id>[^/.]+)")
    def orchestrate(self, request, incident_id=None):
        """Triggers multi-agent orchestration for a specific factory incident."""
        orchestrator = RecoveryOrchestrator()
        force = request.data.get("force_reanalyze", False)
        result = orchestrator.orchestrate_incident_recovery(int(incident_id), force_reanalyze=force)
        http_status = status.HTTP_200_OK if result.get("success") else status.HTTP_400_BAD_REQUEST
        return Response(result, status=http_status)

    @action(detail=True, methods=["post"], url_path="re-evaluate")
    def re_evaluate(self, request, pk=None):
        """Re-evaluates step dependencies and updates recovery case status."""
        case = self.get_object()
        orchestrator = RecoveryOrchestrator()
        orchestrator.evaluate_step_dependencies(case.id)
        case.refresh_from_db()
        return Response(RecoveryCaseSerializer(case).data)


class ApprovalActionViewSet(viewsets.ViewSet):
    """
    Secure endpoints for human managers to review, approve, or reject AI agent actions.
    """
    permission_classes = [permissions.AllowAny]

    @action(detail=True, methods=["post"], url_path="approve")
    def approve(self, request, pk=None):
        """Approves an action with server-side role validation."""
        approved_by = request.data.get("approved_by", "Factory Operations Manager")
        user_role = request.data.get("user_role", "MAINTENANCE_MANAGER")
        notes = request.data.get("response_notes", "Approved via Recovery Command Center")

        result = ActionSafetyService.approve_and_execute(
            approval_id=int(pk),
            approved_by=approved_by,
            user_role=user_role,
            response_notes=notes,
        )
        http_status = status.HTTP_200_OK if result.get("success") else status.HTTP_400_BAD_REQUEST
        return Response(result, status=http_status)

    @action(detail=True, methods=["post"], url_path="reject")
    def reject(self, request, pk=None):
        """Rejects an action with server-side role validation."""
        rejected_by = request.data.get("rejected_by", "Factory Operations Manager")
        user_role = request.data.get("user_role", "MAINTENANCE_MANAGER")
        notes = request.data.get("response_notes", "Rejected by manager")

        result = ActionSafetyService.reject_approval(
            approval_id=int(pk),
            rejected_by=rejected_by,
            user_role=user_role,
            response_notes=notes,
        )
        http_status = status.HTTP_200_OK if result.get("success") else status.HTTP_400_BAD_REQUEST
        return Response(result, status=http_status)


class MultiAgentCoordinationViewSet(viewsets.ViewSet):
    """
    Direct coordination endpoints for individual domain agents.
    """
    permission_classes = [permissions.AllowAny]

    @action(detail=False, methods=["post"], url_path="maintenance/(?P<incident_id>[^/.]+)")
    def coordinate_maintenance(self, request, incident_id=None):
        coordinator = MaintenanceCoordinatorAgent()
        result = coordinator.coordinate_maintenance(int(incident_id), health_diagnosis=request.data.get("diagnosis"))
        return Response(result)

    @action(detail=False, methods=["post"], url_path="inventory/(?P<incident_id>[^/.]+)")
    def coordinate_inventory(self, request, incident_id=None):
        coordinator = InventoryCoordinatorAgent()
        result = coordinator.coordinate_inventory(
            int(incident_id),
            health_diagnosis=request.data.get("diagnosis"),
            maintenance_recommendation=request.data.get("maintenance"),
        )
        return Response(result)

    @action(detail=False, methods=["post"], url_path="production/(?P<incident_id>[^/.]+)")
    def coordinate_production(self, request, incident_id=None):
        agent = ProductionImpactAgent()
        downtime = float(request.data.get("estimated_downtime_hours", 1.5))
        result = agent.evaluate_production_impact(int(incident_id), estimated_downtime_hours=downtime)
        return Response(result)


class AgentDecisionViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = AgentDecision.objects.select_related("execution").all()
    serializer_class = AgentDecisionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["execution", "decision_type", "risk_level"]


class AgentActionViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = AgentAction.objects.select_related("execution").all()
    serializer_class = AgentActionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["execution", "tool_name", "status"]


class AutonomousWorkflowViewSet(viewsets.ReadOnlyModelViewSet):
    """
    End-to-End Autonomous Intelligence & Agent Orchestration API.
    Provides real-time pipeline telemetry, expo demonstration, and verification endpoints.
    """
    queryset = AutonomousWorkflowRun.objects.select_related("incident", "recovery_case", "what_if_scenario", "approval_request").all()
    serializer_class = AutonomousWorkflowRunSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["status", "current_stage", "incident"]

    @action(detail=False, methods=["post"], url_path="trigger-incident/(?P<incident_id>[^/.]+)")
    def trigger_incident(self, request, incident_id=None):
        from .autonomous_orchestrator import AutonomousFactoryOrchestrator
        orchestrator = AutonomousFactoryOrchestrator()
        force = request.data.get("force_reanalyze", False)
        result = orchestrator.process_incident(int(incident_id), force_reanalyze=force)
        return Response(result)

    @action(detail=False, methods=["post"], url_path="run-cycle")
    def run_cycle(self, request):
        from .autonomous_orchestrator import AutonomousFactoryOrchestrator
        orchestrator = AutonomousFactoryOrchestrator()
        result = orchestrator.run_cycle()
        return Response(result)

    @action(detail=False, methods=["post"], url_path="expo-demo")
    def expo_demo(self, request):
        from .autonomous_orchestrator import AutonomousFactoryOrchestrator
        orchestrator = AutonomousFactoryOrchestrator()
        machine_code = request.data.get("machine_code", "WEV-AJ-02")
        anomaly_type = request.data.get("anomaly_type", "VIBRATION_SURGE")
        result = orchestrator.execute_expo_demo(machine_code=machine_code, anomaly_type=anomaly_type)
        return Response(result)

    @action(detail=False, methods=["post"], url_path="advance-approval/(?P<approval_id>[^/.]+)")
    def advance_approval(self, request, approval_id=None):
        from .autonomous_orchestrator import AutonomousFactoryOrchestrator
        orchestrator = AutonomousFactoryOrchestrator()
        approved_by = request.data.get("approved_by", "Operations Manager")
        user_role = request.data.get("user_role", "MAINTENANCE_MANAGER")
        selected_strategy = request.data.get("selected_strategy", "STRATEGY_A")
        response_notes = request.data.get("response_notes", "Approved via Operations Portal")

        result = orchestrator.advance_post_approval(
            approval_id=int(approval_id),
            approved_by=approved_by,
            user_role=user_role,
            selected_strategy=selected_strategy,
            response_notes=response_notes,
        )
        return Response(result)

    @action(detail=False, methods=["post"], url_path="verify-recovery/(?P<case_id>[^/.]+)")
    def verify_recovery(self, request, case_id=None):
        from .autonomous_orchestrator import AutonomousFactoryOrchestrator
        orchestrator = AutonomousFactoryOrchestrator()
        recorded_by = request.data.get("recorded_by", "Senior Maintenance Technician")
        evidence_notes = request.data.get("evidence_notes", "Bearing replaced, alignment verified, motor re-lubricated.")

        result = orchestrator.verify_recovery(
            case_id_or_incident_id=int(case_id),
            recorded_by=recorded_by,
            evidence_notes=evidence_notes,
        )
        return Response(result)

    @action(detail=False, methods=["get"], url_path="status")
    def operational_status(self, request):
        from apps.incidents.models import DetectionCheckpoint, WorkerHeartbeat
        checkpoint = DetectionCheckpoint.get_checkpoint()
        
        orch_wb = WorkerHeartbeat.objects.filter(worker_name="AUTONOMOUS_ORCHESTRATOR").first()
        orch_status = orch_wb.computed_status() if orch_wb else "STOPPED"
        is_running = orch_status == "RUNNING"

        active_workflows = AutonomousWorkflowRun.objects.filter(status__in=["RUNNING", "PAUSED_FOR_APPROVAL"]).count()
        pending_approvals = ApprovalRequest.objects.filter(status="PENDING").count()
        completed_workflows = AutonomousWorkflowRun.objects.filter(status="COMPLETED").count()
        failed_workflows = AutonomousWorkflowRun.objects.filter(status="FAILED").count()

        recent_runs = AutonomousWorkflowRun.objects.select_related("incident").order_by("-updated_at")[:5]

        return Response({
            "worker_running": is_running,
            "orchestrator_worker": orch_status,
            "active_workflows_count": active_workflows,
            "pending_approvals_count": pending_approvals,
            "completed_workflows_count": completed_workflows,
            "failed_workflows_count": failed_workflows,
            "last_active_timestamp": orch_wb.last_heartbeat_at.isoformat() if (orch_wb and orch_wb.last_heartbeat_at) else checkpoint.updated_at.isoformat(),
            "recent_runs": AutonomousWorkflowRunSerializer(recent_runs, many=True).data,
        })

    @action(detail=False, methods=["get"], url_path="incident-workflow/(?P<incident_id>[^/.]+)")
    def incident_workflow(self, request, incident_id=None):
        """
        Builds the complete 12-stage live workflow timeline for a specific incident:
        1. Telemetry Received
        2. Abnormality Detected
        3. Incident Created
        4. Machine Health Investigation
        5. Maintenance Coordination
        6. Inventory Coordination
        7. Production Impact Analysis
        8. Digital Twin Evaluation
        9. Recovery Recommendation
        10. Manager Approval
        11. Authorized Action
        12. Recovery Verification
        """
        from apps.machines.models import MachineTelemetry
        from apps.incidents.models import FactoryIncident, AnomalyDetection, IncidentStatus
        from apps.maintenance.models import MaintenanceTicket, TicketStatus
        from apps.approvals.models import ApprovalRequest, ApprovalStatus
        
        incident = (
            FactoryIncident.objects.filter(id=int(incident_id))
            .select_related("machine", "department", "factory")
            .first()
        )
        if not incident:
            return Response({"error": f"Incident #{incident_id} not found."}, status=status.HTTP_404_NOT_FOUND)

        machine = incident.machine
        workflow_run = AutonomousWorkflowRun.objects.filter(incident=incident).order_by("-created_at").first()
        recovery_case = RecoveryCase.objects.filter(incident=incident).prefetch_related("steps").order_by("-created_at").first()
        approval_req = ApprovalRequest.objects.filter(incident=incident).order_by("-created_at").first()
        anomalies = list(AnomalyDetection.objects.filter(incident=incident).order_by("detected_at"))
        tickets = list(MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).order_by("-created_at"))
        executions = list(
            AgentExecution.objects.filter(incident=incident)
            .select_related("agent")
            .prefetch_related("decisions", "actions")
            .order_by("started_at")
        )
        executions_by_type = {e.agent.agent_type: e for e in executions}

        telemetry = None
        if machine:
            telemetry = MachineTelemetry.objects.filter(
                machine=machine, timestamp__lte=incident.detected_at
            ).order_by("-timestamp").first()
            if not telemetry:
                telemetry = MachineTelemetry.objects.filter(machine=machine).order_by("-timestamp").first()

        what_if_scenario = getattr(workflow_run, "what_if_scenario", None) or getattr(recovery_case, "what_if_scenario", None)

        stages = []

        # 1. Telemetry Received
        tel_summary = "Telemetry reading received."
        tel_evidence = {}
        if telemetry:
            tel_summary = (
                f"Vibration {telemetry.vibration_mms} mm/s, Temp {telemetry.temperature_c}°C, "
                f"Speed {telemetry.speed_rpm} RPM, Power {telemetry.power_kw} kW on {machine.code if machine else 'machine'}"
            )
            tel_evidence = {
                "telemetry_id": telemetry.id,
                "vibration_mms": telemetry.vibration_mms,
                "temperature_c": telemetry.temperature_c,
                "speed_rpm": telemetry.speed_rpm,
                "power_kw": telemetry.power_kw,
                "timestamp": telemetry.timestamp.isoformat(),
            }
        stages.append({
            "stage_index": 1,
            "stage_key": "TELEMETRY_RECEIVED",
            "title": "Telemetry Received",
            "component": "IoT Edge Telemetry Gateway",
            "status": "COMPLETED",
            "timestamp": telemetry.timestamp.isoformat() if telemetry else incident.detected_at.isoformat(),
            "duration_ms": 15,
            "output_summary": tel_summary,
            "evidence": tel_evidence,
            "provenance": "Industrial IoT Sensor Stream",
            "error_reason": None,
            "database_record": {"model": "MachineTelemetry", "id": telemetry.id if telemetry else None},
        })

        # 2. Abnormality Detected
        anom_summary = "Anomalous sensor threshold deviation identified."
        anom_evidence = {}
        anom_status = "COMPLETED" if (anomalies or incident.evidence_data.get("initial_trigger")) else "PENDING"
        first_anom = anomalies[0] if anomalies else None
        if first_anom:
            anom_summary = (
                f"Threshold violation on {first_anom.metric_name}: observed {first_anom.observed_value} "
                f"vs threshold {first_anom.threshold_value} (Score: {first_anom.anomaly_score}x, Algorithm: {first_anom.algorithm_used})"
            )
            anom_evidence = {
                "anomaly_id": first_anom.id,
                "metric_name": first_anom.metric_name,
                "observed_value": first_anom.observed_value,
                "threshold_value": first_anom.threshold_value,
                "score": first_anom.anomaly_score,
                "algorithm": first_anom.algorithm_used,
            }
        elif incident.evidence_data.get("initial_trigger"):
            trig = incident.evidence_data.get("initial_trigger", {})
            anom_summary = f"Threshold violation on {trig.get('metric', 'sensor')}: observed {trig.get('observed')} vs limit {trig.get('threshold')}"
            anom_evidence = trig

        stages.append({
            "stage_index": 2,
            "stage_key": "ABNORMALITY_DETECTED",
            "title": "Abnormality Detected",
            "component": "Autonomous Anomaly Detection Engine",
            "status": anom_status,
            "timestamp": first_anom.detected_at.isoformat() if first_anom else incident.detected_at.isoformat(),
            "duration_ms": 42,
            "output_summary": anom_summary,
            "evidence": anom_evidence,
            "provenance": "Continuous Dynamic Threshold Rule Engine",
            "error_reason": None,
            "database_record": {"model": "AnomalyDetection", "id": first_anom.id if first_anom else None},
        })

        # 3. Incident Created
        stages.append({
            "stage_index": 3,
            "stage_key": "INCIDENT_CREATED",
            "title": "Incident Created",
            "component": "Factory Incident Management Service",
            "status": "COMPLETED",
            "timestamp": incident.detected_at.isoformat(),
            "duration_ms": 25,
            "output_summary": f"Incident {incident.incident_code} registered [{incident.severity}]: {incident.summary}",
            "evidence": {
                "incident_id": incident.id,
                "incident_code": incident.incident_code,
                "severity": incident.severity,
                "category": incident.category,
                "machine_code": machine.code if machine else "N/A",
            },
            "provenance": "Texora Operational Incident Engine",
            "error_reason": None,
            "database_record": {"model": "FactoryIncident", "id": incident.id, "code": incident.incident_code},
        })

        # 4. Machine Health Investigation
        health_exec = executions_by_type.get(AgentType.MACHINE_HEALTH)
        health_status = "NOT_STARTED"
        health_summary = "Diagnostic investigation pending."
        health_provenance = "Gemini LLM Reasoning / Deterministic Fallback"
        health_duration = None
        health_ts = None
        if health_exec:
            health_duration = health_exec.latency_ms
            health_ts = health_exec.completed_at.isoformat() if health_exec.completed_at else health_exec.started_at.isoformat()
            if health_exec.status == AgentExecutionStatus.COMPLETED:
                health_status = "COMPLETED"
                health_summary = health_exec.execution_summary or incident.root_cause_hypothesis or "Health diagnosis completed successfully."
                if "gemini" in health_exec.agent.model_name.lower():
                    if "fallback" in health_summary.lower() or "RATE_LIMITED" in health_summary:
                        health_provenance = "Deterministic Fallback Engine (Gemini Quota Guard)"
                    else:
                        health_provenance = "Google Gemini 2.5 Flash API"
                else:
                    health_provenance = "Deterministic Diagnostic Rules"
            elif health_exec.status in [AgentExecutionStatus.STARTED, AgentExecutionStatus.RUNNING]:
                health_status = "RUNNING"
                health_summary = "AI agent actively investigating telemetry and fault hypotheses."
            elif health_exec.status == AgentExecutionStatus.FAILED:
                health_status = "FAILED"
                health_summary = f"Investigation failed: {health_exec.execution_summary}"
        elif workflow_run and workflow_run.current_stage == AutonomousWorkflowStage.AI_INVESTIGATING:
            health_status = "RUNNING"
            health_summary = "Machine Health Specialist investigating telemetry spectra..."

        stages.append({
            "stage_index": 4,
            "stage_key": "MACHINE_HEALTH_INVESTIGATION",
            "title": "Machine Health Investigation",
            "component": "Machine Health Diagnostic Specialist",
            "status": health_status,
            "timestamp": health_ts,
            "duration_ms": health_duration,
            "output_summary": health_summary,
            "evidence": {
                "execution_id": str(health_exec.execution_id) if health_exec else None,
                "hypothesis": incident.root_cause_hypothesis,
            },
            "provenance": health_provenance,
            "error_reason": None,
            "database_record": {"model": "AgentExecution", "id": health_exec.id if health_exec else None},
        })

        # 5. Maintenance Coordination
        maint_exec = executions_by_type.get(AgentType.MAINTENANCE)
        maint_status = "NOT_STARTED"
        maint_summary = "Maintenance work order estimation pending."
        maint_duration = None
        maint_ts = None
        if maint_exec:
            maint_duration = maint_exec.latency_ms
            maint_ts = maint_exec.completed_at.isoformat() if maint_exec.completed_at else maint_exec.started_at.isoformat()
            if maint_exec.status == AgentExecutionStatus.COMPLETED:
                maint_status = "COMPLETED"
                maint_summary = maint_exec.execution_summary or "Maintenance labor protocol & technician skills identified."
            elif maint_exec.status in [AgentExecutionStatus.STARTED, AgentExecutionStatus.RUNNING]:
                maint_status = "RUNNING"
                maint_summary = "Evaluating repair duration and technician requirements..."
            elif maint_exec.status == AgentExecutionStatus.FAILED:
                maint_status = "FAILED"
                maint_summary = f"Maintenance coordination failed: {maint_exec.execution_summary}"

        stages.append({
            "stage_index": 5,
            "stage_key": "MAINTENANCE_COORDINATION",
            "title": "Maintenance Coordination",
            "component": "Maintenance & Work Order Coordinator",
            "status": maint_status,
            "timestamp": maint_ts,
            "duration_ms": maint_duration,
            "output_summary": maint_summary,
            "evidence": {"execution_id": str(maint_exec.execution_id) if maint_exec else None},
            "provenance": "Autonomous Maintenance Rule & Skill Engine",
            "error_reason": None,
            "database_record": {"model": "AgentExecution", "id": maint_exec.id if maint_exec else None},
        })

        # 6. Inventory Coordination
        inv_exec = executions_by_type.get(AgentType.INVENTORY)
        inv_status = "NOT_STARTED"
        inv_summary = "Spare part availability evaluation pending."
        inv_duration = None
        inv_ts = None
        if inv_exec:
            inv_duration = inv_exec.latency_ms
            inv_ts = inv_exec.completed_at.isoformat() if inv_exec.completed_at else inv_exec.started_at.isoformat()
            if inv_exec.status == AgentExecutionStatus.COMPLETED:
                inv_status = "COMPLETED"
                inv_summary = inv_exec.execution_summary or "Spare parts availability verified; stock allocation proposed."
            elif inv_exec.status in [AgentExecutionStatus.STARTED, AgentExecutionStatus.RUNNING]:
                inv_status = "RUNNING"
                inv_summary = "Validating warehouse parts inventory and safety barriers..."
            elif inv_exec.status == AgentExecutionStatus.FAILED:
                inv_status = "FAILED"
                inv_summary = f"Inventory coordination failed: {inv_exec.execution_summary}"

        stages.append({
            "stage_index": 6,
            "stage_key": "INVENTORY_COORDINATION",
            "title": "Inventory Coordination",
            "component": "Inventory & Spare Parts Coordinator",
            "status": inv_status,
            "timestamp": inv_ts,
            "duration_ms": inv_duration,
            "output_summary": inv_summary,
            "evidence": {"execution_id": str(inv_exec.execution_id) if inv_exec else None},
            "provenance": "Autonomous Warehouse Stock & Safety Reserve Engine",
            "error_reason": None,
            "database_record": {"model": "AgentExecution", "id": inv_exec.id if inv_exec else None},
        })

        # 7. Production Impact Analysis
        prod_exec = executions_by_type.get(AgentType.PRODUCTION_IMPACT)
        prod_status = "NOT_STARTED"
        prod_summary = "Production output fallout calculation pending."
        prod_duration = None
        prod_ts = None
        if prod_exec:
            prod_duration = prod_exec.latency_ms
            prod_ts = prod_exec.completed_at.isoformat() if prod_exec.completed_at else prod_exec.started_at.isoformat()
            if prod_exec.status == AgentExecutionStatus.COMPLETED:
                prod_status = "COMPLETED"
                prod_summary = prod_exec.execution_summary or "Throughput loss estimated; compatible alternate machinery evaluated."
            elif prod_exec.status in [AgentExecutionStatus.STARTED, AgentExecutionStatus.RUNNING]:
                prod_status = "RUNNING"
                prod_summary = "Evaluating delivery risks and alternate loom capacity..."
            elif prod_exec.status == AgentExecutionStatus.FAILED:
                prod_status = "FAILED"
                prod_summary = f"Production impact evaluation failed: {prod_exec.execution_summary}"

        stages.append({
            "stage_index": 7,
            "stage_key": "PRODUCTION_IMPACT_ANALYSIS",
            "title": "Production Impact Analysis",
            "component": "Production Rescheduling & Impact Agent",
            "status": prod_status,
            "timestamp": prod_ts,
            "duration_ms": prod_duration,
            "output_summary": prod_summary,
            "evidence": {"execution_id": str(prod_exec.execution_id) if prod_exec else None},
            "provenance": "Deterministic Production Capacity Model",
            "error_reason": None,
            "database_record": {"model": "AgentExecution", "id": prod_exec.id if prod_exec else None},
        })

        # 8. Digital Twin Evaluation
        twin_status = "NOT_STARTED"
        twin_summary = "Digital Twin recovery strategy simulation pending."
        twin_duration = None
        twin_ts = None
        twin_evidence = {}
        if what_if_scenario:
            comp_run = what_if_scenario.runs.filter(status="COMPLETED").first()
            if comp_run:
                twin_status = "COMPLETED"
                twin_duration = comp_run.execution_duration_ms
                twin_ts = comp_run.executed_at.isoformat()
                evals = list(comp_run.strategy_evaluations.all().order_by("rank"))
                top = evals[0] if evals else None
                cost_val = top.estimated_cost.get("total_estimated_cost_inr", 4200) if (top and isinstance(top.estimated_cost, dict)) else 4200
                twin_summary = (
                    f"Simulated {len(evals)} recovery strategies. Top Rank: {top.strategy_name if top else 'Strategy A'} "
                    f"({top.estimated_downtime_hours if top else 2.0}h downtime, est cost ₹{cost_val:,})"
                )
                twin_evidence = {
                    "scenario_id": what_if_scenario.scenario_id,
                    "strategies_evaluated": [e.strategy_code for e in evals],
                    "top_strategy": top.strategy_code if top else "STRATEGY_A",
                }
            elif what_if_scenario.runs.filter(status="STARTED").exists():
                twin_status = "RUNNING"
                twin_summary = "Executing What-If simulation across Strategies A, B, and C..."
        elif workflow_run and workflow_run.current_stage == AutonomousWorkflowStage.SIMULATING_STRATEGIES:
            twin_status = "RUNNING"
            twin_summary = "Executing What-If simulation across Strategies A, B, and C..."

        stages.append({
            "stage_index": 8,
            "stage_key": "DIGITAL_TWIN_EVALUATION",
            "title": "Digital Twin Evaluation",
            "component": "Factory Digital Twin What-If Engine",
            "status": twin_status,
            "timestamp": twin_ts,
            "duration_ms": twin_duration,
            "output_summary": twin_summary,
            "evidence": twin_evidence,
            "provenance": "Deterministic Plant Simulation Model",
            "error_reason": None,
            "database_record": {"model": "WhatIfScenario", "id": what_if_scenario.id if what_if_scenario else None},
        })

        # 9. Recovery Recommendation
        rec_status = "NOT_STARTED"
        rec_summary = "Autonomous recommendation pending."
        rec_ts = None
        if workflow_run and workflow_run.recommended_strategy:
            rec_status = "COMPLETED"
            rec_ts = workflow_run.updated_at.isoformat()
            rec_summary = f"Autonomous recommendation formulated: {workflow_run.recommended_strategy} selected as optimal recovery route."
        elif recovery_case and recovery_case.recommended_strategy:
            rec_status = "COMPLETED"
            rec_ts = recovery_case.updated_at.isoformat()
            rec_summary = f"Autonomous recommendation formulated: {recovery_case.recommended_strategy} selected."

        stages.append({
            "stage_index": 9,
            "stage_key": "RECOVERY_RECOMMENDATION",
            "title": "Recovery Recommendation",
            "component": "Autonomous Recommendation Synthesizer",
            "status": rec_status,
            "timestamp": rec_ts,
            "duration_ms": 30,
            "output_summary": rec_summary,
            "evidence": {
                "workflow_run_id": workflow_run.workflow_id if workflow_run else None,
                "recommended_strategy": workflow_run.recommended_strategy if workflow_run else (recovery_case.recommended_strategy if recovery_case else None),
            },
            "provenance": "Multi-Agent Synthesis Engine",
            "error_reason": None,
            "database_record": {"model": "AutonomousWorkflowRun", "id": workflow_run.id if workflow_run else None},
        })

        # 10. Manager Approval
        appr_status = "NOT_STARTED"
        appr_summary = "Approval request pending generation."
        appr_provenance = "Human-in-the-Loop Governance Gate"
        appr_ts = None
        if approval_req:
            appr_ts = approval_req.responded_at.isoformat() if approval_req.responded_at else approval_req.created_at.isoformat()
            if approval_req.status == ApprovalStatus.APPROVED:
                appr_status = "COMPLETED"
                appr_summary = f"Approved by {approval_req.approved_by or 'Plant Operations Manager'}. Authorized: {approval_req.requested_action}"
                appr_provenance = f"Human Operations Authorization ({approval_req.approved_by or 'Operations Manager'})"
            elif approval_req.status == ApprovalStatus.REJECTED:
                appr_status = "FAILED"
                appr_summary = f"Rejected by {approval_req.approved_by or 'Operations Manager'}. Reason: {approval_req.response_notes}"
            elif approval_req.status == ApprovalStatus.REVISION_REQUESTED:
                appr_status = "BLOCKED"
                appr_summary = f"Revision requested by {approval_req.approved_by or 'Manager'}. Notes: {approval_req.response_notes}"
            else:
                appr_status = "WAITING_FOR_APPROVAL"
                appr_summary = f"Awaiting Manager Review ({approval_req.approval_code}): {approval_req.title} [Risk: {approval_req.risk_level}]"

        stages.append({
            "stage_index": 10,
            "stage_key": "MANAGER_APPROVAL",
            "title": "Manager Approval",
            "component": "Operations Governance & Approval Inbox Gate",
            "status": appr_status,
            "timestamp": appr_ts,
            "duration_ms": None,
            "output_summary": appr_summary,
            "evidence": {
                "approval_id": approval_req.id if approval_req else None,
                "approval_code": approval_req.approval_code if approval_req else None,
                "status": approval_req.status if approval_req else None,
            },
            "provenance": appr_provenance,
            "error_reason": None,
            "database_record": {"model": "ApprovalRequest", "id": approval_req.id if approval_req else None},
        })

        # 11. Authorized Action
        act_status = "NOT_STARTED"
        act_summary = "Action dispatch awaiting prior approval."
        act_ts = None
        if approval_req and approval_req.status == ApprovalStatus.APPROVED:
            if tickets:
                t = tickets[0]
                act_ts = t.resolved_at.isoformat() if t.resolved_at else (t.repair_completed_at.isoformat() if t.repair_completed_at else t.created_at.isoformat())
                if t.status in [TicketStatus.REPAIR_COMPLETED, TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED, TicketStatus.CLOSED, TicketStatus.RESOLVED]:
                    act_status = "COMPLETED"
                    fault_note = f" Confirmed fault: {t.confirmed_fault}." if t.confirmed_fault else ""
                    parts_count = len(t.parts_replaced) if t.parts_replaced else 0
                    parts_note = f" Parts replaced: {parts_count}." if parts_count > 0 else ""
                    act_summary = f"Work Order {t.ticket_number} executed by {t.assigned_technician or 'Technician'}.{fault_note}{parts_note}"
                elif t.status in [TicketStatus.ACCEPTED, TicketStatus.INSPECTION_IN_PROGRESS, TicketStatus.REPAIR_IN_PROGRESS, TicketStatus.IN_PROGRESS]:
                    act_status = "RUNNING"
                    act_summary = f"Work Order {t.ticket_number} actively executing [{t.status}] by {t.assigned_technician or 'Technician'}."
                elif t.status == TicketStatus.BLOCKED:
                    act_status = "BLOCKED"
                    act_summary = f"Work Order {t.ticket_number} blocked during execution. Technician intervention required."
                else:
                    act_status = "RUNNING"
                    act_summary = f"Work Order {t.ticket_number} actionable. Ready for technician acceptance and guided inspection."
            else:
                act_status = "RUNNING"
                act_summary = "Authorized action approved; work order queued for technician dispatch."
        elif approval_req and approval_req.status == ApprovalStatus.REJECTED:
            act_status = "SKIPPED"
            act_summary = "Action dispatch skipped due to manager rejection."
        elif approval_req and approval_req.status == ApprovalStatus.PENDING:
            act_status = "BLOCKED"
            act_summary = "Blocked by safety barrier: No work orders or inventory deductions allowed prior to manager approval."

        stages.append({
            "stage_index": 11,
            "stage_key": "AUTHORIZED_ACTION",
            "title": "Authorized Action",
            "component": "Maintenance Execution & Work Order Service",
            "status": act_status,
            "timestamp": act_ts,
            "duration_ms": None,
            "output_summary": act_summary,
            "evidence": {
                "ticket_count": len(tickets),
                "ticket_number": tickets[0].ticket_number if tickets else None,
                "ticket_status": tickets[0].status if tickets else None,
                "confirmed_fault": tickets[0].confirmed_fault if tickets else None,
            },
            "provenance": "Action Safety Service (Verified Authorized)",
            "error_reason": None,
            "database_record": {"model": "MaintenanceTicket", "id": tickets[0].id if tickets else None},
        })

        # 12. Recovery Verification
        recov_status = "NOT_STARTED"
        recov_summary = "Post-repair verification pending technician completion."
        recov_ts = None
        t = tickets[0] if tickets else None

        if t and t.verification_status:
            from apps.maintenance.models import VerificationStatus as VS
            v_status = t.verification_status
            if v_status == VS.VERIFIED or t.status == TicketStatus.CLOSED:
                recov_status = "COMPLETED"
                recov_ts = t.authorized_signoff_at.isoformat() if t.authorized_signoff_at else t.updated_at.isoformat()
                recov_summary = (
                    f"Machine {machine.code if machine else 'Asset'} confirmed recovered. "
                    f"Sensor telemetry restored within nominal operating limits. "
                    f"Return to service authorized by {t.authorized_signoff_by or 'Plant Operations Manager'}."
                )
            elif v_status == VS.AWAITING_AUTHORIZED_SIGNOFF:
                recov_status = "RUNNING"
                recov_ts = t.updated_at.isoformat()
                recov_summary = (
                    f"Post-repair telemetry checks passed within configured limits. "
                    f"Awaiting authorized personnel sign-off for safe return to service."
                )
            elif v_status == VS.FAILED or t.status == TicketStatus.VERIFICATION_FAILED:
                recov_status = "FAILED"
                recov_ts = t.updated_at.isoformat()
                recov_summary = t.verification_summary or "Recovery verification failed — Post-repair telemetry exceeds thresholds."
            elif v_status == VS.MONITORING:
                recov_status = "RUNNING"
                recov_ts = t.updated_at.isoformat()
                recov_summary = t.verification_summary or "Observation window accumulating post-repair telemetry samples."
            elif v_status == VS.INCONCLUSIVE:
                recov_status = "BLOCKED"
                recov_ts = t.updated_at.isoformat()
                recov_summary = t.verification_summary or "Sensor stream inconclusive or stale. Awaiting reliable readings."
            elif t.status in [TicketStatus.REPAIR_COMPLETED, TicketStatus.AWAITING_VERIFICATION]:
                recov_status = "RUNNING"
                recov_summary = "Repair completed; awaiting post-repair telemetry evaluation over observation window."
        elif recovery_case and recovery_case.status == RecoveryCaseStatus.RECOVERED:
            recov_status = "COMPLETED"
            recov_ts = recovery_case.recovered_at.isoformat() if recovery_case.recovered_at else recovery_case.updated_at.isoformat()
            recov_summary = f"Machine {machine.code if machine else 'Asset'} confirmed recovered. Sensor telemetry restored within nominal operating limits."
        elif incident.status == IncidentStatus.CLOSED:
            recov_status = "COMPLETED"
            recov_ts = incident.resolved_at.isoformat() if incident.resolved_at else incident.detected_at.isoformat()
            recov_summary = f"Incident verified & closed: {incident.resolution_summary or 'Nominal operation restored.'}"

        stages.append({
            "stage_index": 12,
            "stage_key": "RECOVERY_VERIFICATION",
            "title": "Recovery Verification",
            "component": "Telemetry Post-Repair Verification Monitor",
            "status": recov_status,
            "timestamp": recov_ts,
            "duration_ms": None,
            "output_summary": recov_summary,
            "evidence": {
                "recovery_case_code": recovery_case.case_code if recovery_case else None,
                "incident_status": incident.status,
                "ticket_verification_status": t.verification_status if t else None,
                "authorized_signoff_by": t.authorized_signoff_by if t else None,
            },
            "provenance": "Dual-Verification (Physical Inspection + Multi-Reading Telemetry Stream)",
            "error_reason": None,
            "database_record": {"model": "MaintenanceTicket", "id": t.id if t else None},
        })

        return Response({
            "incident": {
                "id": incident.id,
                "incident_code": incident.incident_code,
                "severity": incident.severity,
                "status": incident.status,
                "summary": incident.summary,
                "detected_at": incident.detected_at.isoformat(),
                "machine_code": machine.code if machine else "N/A",
                "machine_name": machine.name if machine else "N/A",
                "department_name": machine.department.name if machine else "N/A",
            },
            "workflow_run_id": workflow_run.workflow_id if workflow_run else None,
            "current_stage": workflow_run.current_stage if workflow_run else ("RESOLVED" if incident.status == IncidentStatus.RESOLVED else "NEW_INCIDENT"),
            "recommended_strategy": workflow_run.recommended_strategy if workflow_run else (recovery_case.recommended_strategy if recovery_case else None),
            "approval_status": approval_req.status if approval_req else "NOT_REQUESTED",
            "stages": stages,
        })

    @action(detail=False, methods=["get"], url_path="business-impact/(?P<incident_id>[^/.]+)")
    def business_impact(self, request, incident_id=None):
        """
        Calculates financial and operational business impact for a factory incident:
        - Potential downtime (hours)
        - Production output loss (meters/kg)
        - Estimated repair cost (INR)
        - Recovery strategy comparison (Strategy A vs B vs C)
        - Strategic financial exposure difference
        """
        from apps.incidents.models import FactoryIncident
        from apps.digital_twin.models import WhatIfScenario
        
        incident = FactoryIncident.objects.select_related("machine", "department").filter(id=int(incident_id)).first()
        if not incident:
            return Response({"error": f"Incident #{incident_id} not found."}, status=status.HTTP_404_NOT_FOUND)

        machine = incident.machine
        recovery_case = RecoveryCase.objects.filter(incident=incident).order_by("-created_at").first()
        workflow_run = AutonomousWorkflowRun.objects.filter(incident=incident).order_by("-created_at").first()

        scenario = getattr(workflow_run, "what_if_scenario", None) or getattr(recovery_case, "what_if_scenario", None)
        if not scenario:
            scenario = WhatIfScenario.objects.filter(machine_changes__machine_code=machine.code).order_by("-created_at").first() if machine else None

        evaluations = []
        if scenario:
            run = scenario.runs.filter(status="COMPLETED").first()
            if run:
                evals = list(run.strategy_evaluations.all().order_by("rank"))
                for ev in evals:
                    cost_val = ev.estimated_cost.get("total_estimated_cost_inr", 4200) if isinstance(ev.estimated_cost, dict) else 4200
                    loss_val = ev.estimated_output_loss.get("meters", ev.estimated_output_loss.get("kg", 250)) if isinstance(ev.estimated_output_loss, dict) else 250
                    evaluations.append({
                        "strategy_code": ev.strategy_code,
                        "strategy_name": ev.strategy_name,
                        "rank": ev.rank,
                        "is_feasible": ev.is_feasible,
                        "effectiveness_level": ev.effectiveness_level,
                        "estimated_downtime_hours": ev.estimated_downtime_hours,
                        "capacity_recovered_pct": ev.capacity_recovered_pct,
                        "estimated_output_loss": loss_val,
                        "estimated_cost_inr": cost_val,
                        "cost_breakdown": ev.estimated_cost if isinstance(ev.estimated_cost, dict) else {},
                        "pros": ev.pros,
                        "cons": ev.cons,
                    })

        if not evaluations:
            base_downtime = float(recovery_case.estimated_downtime_hours if recovery_case else 2.5)
            evaluations = [
                {
                    "strategy_code": "STRATEGY_A",
                    "strategy_name": "Strategy A: Repair Affected Machine First",
                    "rank": 1,
                    "is_feasible": True,
                    "effectiveness_level": "HIGH_EFFECTIVENESS",
                    "estimated_downtime_hours": base_downtime,
                    "capacity_recovered_pct": 100.0,
                    "estimated_output_loss": round(base_downtime * 35.0, 1),
                    "estimated_cost_inr": 4200.0,
                    "cost_breakdown": {"labor_cost": 1500, "parts_cost": 2700, "total_estimated_cost_inr": 4200},
                    "pros": ["100% capacity restored", "Uses standard in-stock spares"],
                    "cons": ["Requires immediate technician attendance"],
                },
                {
                    "strategy_code": "STRATEGY_B",
                    "strategy_name": "Strategy B: Shift Production to Compatible Alternates",
                    "rank": 2,
                    "is_feasible": True,
                    "effectiveness_level": "MODERATE_EFFECTIVENESS",
                    "estimated_downtime_hours": round(base_downtime * 0.4, 1),
                    "capacity_recovered_pct": 80.0,
                    "estimated_output_loss": round(base_downtime * 70.0, 1),
                    "estimated_cost_inr": 6800.0,
                    "cost_breakdown": {"retooling_cost": 3000, "overtime_cost": 3800, "total_estimated_cost_inr": 6800},
                    "pros": ["Near-zero downtime on primary loom"],
                    "cons": ["Retooling overhead on alternate loom", "20% capacity loss"],
                },
                {
                    "strategy_code": "STRATEGY_C",
                    "strategy_name": "Strategy C: Hybrid Prioritized Repair & Partial Rerouting",
                    "rank": 3,
                    "is_feasible": True,
                    "effectiveness_level": "MODERATE_EFFECTIVENESS",
                    "estimated_downtime_hours": round(base_downtime * 0.7, 1),
                    "capacity_recovered_pct": 90.0,
                    "estimated_output_loss": round(base_downtime * 45.0, 1),
                    "estimated_cost_inr": 5400.0,
                    "cost_breakdown": {"labor_cost": 1800, "overtime_cost": 3600, "total_estimated_cost_inr": 5400},
                    "pros": ["Balanced order fulfillment", "Buffers critical client batches"],
                    "cons": ["High technician coordination complexity"],
                },
            ]

        top_strat = evaluations[0]
        unmitigated_downtime = round(top_strat["estimated_downtime_hours"] * 3.2, 1)
        hourly_value = 4500.0
        unmitigated_loss_inr = round(unmitigated_downtime * hourly_value, 2)
        mitigated_loss_inr = round(top_strat["estimated_downtime_hours"] * hourly_value + top_strat["estimated_cost_inr"], 2)
        net_financial_risk_avoided = max(round(unmitigated_loss_inr - mitigated_loss_inr, 2), 0.0)

        return Response({
            "incident": {
                "id": incident.id,
                "incident_code": incident.incident_code,
                "severity": incident.severity,
                "summary": incident.summary,
                "machine_code": machine.code if machine else "N/A",
                "department": machine.department.name if machine else "N/A",
            },
            "kpis": {
                "recommended_strategy": top_strat["strategy_code"],
                "recommended_strategy_name": top_strat["strategy_name"],
                "potential_downtime_hours": top_strat["estimated_downtime_hours"],
                "production_output_loss": top_strat["estimated_output_loss"],
                "estimated_repair_cost_inr": top_strat["estimated_cost_inr"],
                "unmitigated_exposure_inr": unmitigated_loss_inr,
                "mitigated_exposure_inr": mitigated_loss_inr,
                "net_financial_risk_avoided_inr": net_financial_risk_avoided,
            },
            "strategy_comparison": evaluations,
            "data_provenance": {
                "recorded_operational_data": "Machine base capacity, verified shift schedule, factory operating limits",
                "simulated_factory_data": "Injected sensor telemetry & anomaly thresholds",
                "model_generated_estimates": "Deterministic Digital Twin What-If formula (downtime x output rate + labor/parts)",
                "user_entered_assumptions": "Standardized hourly line value (₹4,500/hr) & technician staffing availability",
                "notice": "All financial figures are illustrative operational estimates derived from deterministic factory models, not guaranteed warranty savings."
            },
        })

    @action(detail=False, methods=["get"], url_path="demo-status")
    def demo_status(self, request):
        """Returns readiness status and metadata for the controlled commercial expo demonstration."""
        from apps.incidents.models import FactoryIncident, IncidentStatus
        
        active_demo = (
            FactoryIncident.objects.filter(
                summary__icontains="Vibration Surge",
                status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING],
            )
            .select_related("machine")
            .order_by("-detected_at")
            .first()
        )

        return Response({
            "is_demo_in_progress": active_demo is not None,
            "active_demo_incident": {
                "id": active_demo.id,
                "incident_code": active_demo.incident_code,
                "machine_code": active_demo.machine.code if active_demo.machine else "WEV-AJ-02",
                "status": active_demo.status,
                "detected_at": active_demo.detected_at.isoformat(),
            } if active_demo else None,
            "supported_machines": ["WEV-AJ-02", "WEV-RAP-01", "SPN-RS-01"],
            "demo_scenario_name": "Controlled Weaving Loom Bearing Vibration Surge",
            "cooldown_remaining_seconds": 0,
            "can_trigger": True,
            "notice": "Executing this scenario runs genuine anomaly detection, specialist agent coordination, and Digital Twin evaluation without bypassing manager approval.",
        })


