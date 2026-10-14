from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from django.utils import timezone

from .models import (
    MaintenanceTicket,
    MaintenanceActivity,
    MaintenanceHistory,
    WorkOrderTransition,
    WorkOrderAttachment,
    TicketStatus,
    VerificationStatus,
)
from .serializers import (
    MaintenanceTicketSerializer,
    MaintenanceActivitySerializer,
    MaintenanceHistorySerializer,
    WorkOrderTransitionSerializer,
    WorkOrderAttachmentSerializer,
)
from .lifecycle_service import WorkOrderLifecycleService
from .verification_service import RecoveryVerificationService
from .simulation_service import MaintenanceSimulationService
from apps.machines.models import MachineTelemetry, MachineOperatingLimits
from apps.incidents.models import FactoryIncident
from apps.inventory.models import InventoryItem


class MaintenanceTicketViewSet(viewsets.ModelViewSet):
    queryset = (
        MaintenanceTicket.objects.select_related("machine", "machine__machine_type", "machine__department")
        .prefetch_related("activities", "transitions", "attachments")
        .all()
    )
    serializer_class = MaintenanceTicketSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "priority", "status", "incident_reference", "verification_status"]
    search_fields = ["ticket_number", "title", "description", "assigned_technician"]

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        # Ensure checklist is populated
        WorkOrderLifecycleService.populate_checklist_if_empty(instance)
        serializer = self.get_serializer(instance)
        return Response(serializer.data)

    @action(detail=True, methods=["get"], url_path="execution-detail")
    def execution_detail(self, request, pk=None):
        """
        Returns rich execution details for the Maintenance Execution Center:
        ticket, machine limits, telemetry before and after repair, incident, spare parts.
        """
        ticket = self.get_object()
        WorkOrderLifecycleService.populate_checklist_if_empty(ticket)
        machine = ticket.machine

        # Telemetry readings: last 20 readings for before/after trend
        telemetry_qs = MachineTelemetry.objects.filter(machine=machine).order_by("-timestamp")[:20]
        telemetry_data = [
            {
                "id": t.id,
                "timestamp": t.timestamp.isoformat(),
                "vibration_mms": round(float(t.vibration_mms or 0), 2),
                "temperature_c": round(float(t.temperature_c or 0), 1),
                "speed_rpm": round(float(t.speed_rpm or 0), 0),
                "power_kw": round(float(t.power_kw or 0), 1),
            }
            for t in reversed(list(telemetry_qs))
        ]

        # Machine operating limits
        limits = getattr(machine, "operating_limits", None)
        limits_data = {
            "warning_vibration_mms": limits.warning_vibration_mms if limits else 4.0,
            "max_vibration_mms": limits.max_vibration_mms if limits else 5.5,
            "warning_temp_c": limits.warning_temp_c if limits else 75.0,
            "max_temp_c": limits.max_temp_c if limits else 85.0,
            "min_rpm": limits.min_rpm if limits else 10000,
            "max_rpm": limits.max_rpm if limits else 22000,
        }

        # Incident context
        incident = None
        if ticket.incident_reference:
            incident = FactoryIncident.objects.filter(incident_code=ticket.incident_reference).first()

        incident_data = None
        if incident:
            incident_data = {
                "id": incident.id,
                "incident_code": incident.incident_code,
                "severity": incident.severity,
                "status": incident.status,
                "summary": incident.summary,
                "root_cause_hypothesis": incident.root_cause_hypothesis,
                "detected_at": incident.detected_at.isoformat(),
                "resolved_at": incident.resolved_at.isoformat() if incident.resolved_at else None,
            }

        # Available spare parts for this machine type
        parts_qs = InventoryItem.objects.filter(category="SPARE_PART", is_active=True)[:10]
        spare_parts = [
            {
                "item_code": p.item_code,
                "name": p.name,
                "current_stock": float(p.current_stock),
                "unit": p.unit,
                "unit_cost": float(p.unit_cost),
                "location_shelf": p.location_shelf,
            }
            for p in parts_qs
        ]

        # Maintenance history
        history_qs = ticket.machine.maintenance_history.all()[:5]
        history_data = MaintenanceHistorySerializer(history_qs, many=True).data

        # Verification evaluation
        verification_eval = RecoveryVerificationService.evaluate_machine_recovery(
            machine=machine,
            ticket=ticket,
            observation_window=5,
        )

        return Response({
            "ticket": MaintenanceTicketSerializer(ticket).data,
            "machine_limits": limits_data,
            "telemetry_trend": telemetry_data,
            "incident": incident_data,
            "spare_parts_catalog": spare_parts,
            "maintenance_history": history_data,
            "verification_evaluation": verification_eval,
        })

    @action(detail=True, methods=["post"], url_path="transition")
    def transition(self, request, pk=None):
        """
        Executes a validated lifecycle transition:
        POST /api/v1/maintenance/tickets/{id}/transition/
        body: { "new_state": "ACCEPTED", "actor": "R. Sharma", "actor_role": "Lead Tech", "reason": "...", "payload": {...} }
        """
        ticket = self.get_object()
        new_state = request.data.get("new_state")
        actor = request.data.get("actor", "Field Technician")
        actor_role = request.data.get("actor_role", "Technician")
        reason = request.data.get("reason", "")
        payload = request.data.get("payload", {})

        if not new_state:
            return Response({"error": "new_state is required."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            updated_ticket = WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=new_state,
                actor=actor,
                actor_role=actor_role,
                reason=reason,
                payload=payload,
            )
            return Response(MaintenanceTicketSerializer(updated_ticket).data)
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=["post"], url_path="submit-inspection")
    def submit_inspection(self, request, pk=None):
        """
        Submits technician inspection results and confirmed physical fault:
        body: { "checklist": [...], "confirmed_fault": "...", "notes": "...", "actor": "..." }
        """
        ticket = self.get_object()
        checklist = request.data.get("checklist", [])
        confirmed_fault = request.data.get("confirmed_fault", "")
        notes = request.data.get("notes", "")
        actor = request.data.get("actor", "Field Technician")

        if ticket.status in [TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED, TicketStatus.CLOSED]:
            return Response(
                {
                    "error": (
                        f"Diagnostic inspection already completed: Work order {ticket.ticket_number} "
                        f"is currently in state '{ticket.status}'."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not confirmed_fault:
            return Response({"error": "confirmed_fault is required to confirm diagnostic inspection."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            updated_ticket = WorkOrderLifecycleService.transition_state(
                ticket=ticket,
                new_state=TicketStatus.REPAIR_IN_PROGRESS,
                actor=actor,
                reason="Inspection completed and confirmed fault documented.",
                payload={
                    "inspection_checklist": checklist,
                    "confirmed_fault": confirmed_fault,
                    "fault_confirmation_notes": notes,
                },
            )
            return Response(MaintenanceTicketSerializer(updated_ticket).data)
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=["post"], url_path="consume-parts")
    def consume_parts(self, request, pk=None):
        """
        Consumes spare parts transaction-safely:
        body: { "parts": [{"item_code": "SPR-BRG-6204", "quantity": 1}], "actor": "..." }
        """
        ticket = self.get_object()
        parts = request.data.get("parts", [])
        actor = request.data.get("actor", "Field Technician")

        if ticket.status in [TicketStatus.AWAITING_VERIFICATION, TicketStatus.VERIFIED, TicketStatus.CLOSED]:
            return Response(
                {
                    "error": (
                        f"Cannot deduct spare parts: Physical repair is already completed for "
                        f"work order {ticket.ticket_number} (current state: '{ticket.status}')."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not parts:
            return Response({"error": "parts list is required."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            consumed = WorkOrderLifecycleService.consume_spare_parts(
                ticket=ticket,
                parts=parts,
                actor=actor,
            )
            return Response({
                "consumed_parts": consumed,
                "ticket": MaintenanceTicketSerializer(ticket).data,
            })
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=["post"], url_path="complete-repair")
    def complete_repair(self, request, pk=None):
        """
        Documents physical repair completion:
        body: { "repair_performed": "...", "actual_duration_minutes": 45, "remaining_issues": "...", "actor": "..." }
        """
        ticket = self.get_object()
        repair_performed = request.data.get("repair_performed", "")
        duration = int(request.data.get("actual_duration_minutes", 0))
        remaining_issues = request.data.get("remaining_issues", "")
        actor = request.data.get("actor", "Field Technician")

        # State-aware guard: prevent repeated repair completion from AWAITING_VERIFICATION or terminal states
        if ticket.status == TicketStatus.AWAITING_VERIFICATION:
            return Response(
                {
                    "error": (
                        f"Physical repair has already been completed for work order {ticket.ticket_number}. "
                        f"The ticket is currently in 'AWAITING_VERIFICATION' and awaiting post-repair recovery verification."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        if ticket.status in [TicketStatus.VERIFIED, TicketStatus.CLOSED, TicketStatus.RESOLVED]:
            return Response(
                {
                    "error": (
                        f"Action unavailable: Work order {ticket.ticket_number} has already been "
                        f"verified and closed ({ticket.status})."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not repair_performed or len(repair_performed.strip()) < 10:
            return Response(
                {"error": "Please describe the repair performed (minimum 10 characters)."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if duration <= 0:
            return Response(
                {"error": "Positive actual repair duration in minutes is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            if ticket.status == TicketStatus.REPAIR_COMPLETED:
                updated_ticket = WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.AWAITING_VERIFICATION,
                    actor=actor,
                    reason="Moving to awaiting verification following repair completion.",
                )
            else:
                updated_ticket = WorkOrderLifecycleService.transition_state(
                    ticket=ticket,
                    new_state=TicketStatus.REPAIR_COMPLETED,
                    actor=actor,
                    reason="Technician finished repair; documented work and duration.",
                    payload={
                        "repair_performed": repair_performed,
                        "actual_repair_duration_minutes": duration,
                        "remaining_issues": remaining_issues,
                    },
                )
                updated_ticket = WorkOrderLifecycleService.transition_state(
                    ticket=updated_ticket,
                    new_state=TicketStatus.AWAITING_VERIFICATION,
                    actor=actor,
                    reason="Work order ready for post-repair sensor verification.",
                )
            return Response(MaintenanceTicketSerializer(updated_ticket).data)
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=["post"], url_path="verify-recovery")
    def verify_recovery(self, request, pk=None):
        """
        Triggers the dedicated Recovery Verification Engine evaluation.
        """
        ticket = self.get_object()
        observation_window = int(request.data.get("observation_window", 5))

        report = RecoveryVerificationService.evaluate_machine_recovery(
            machine=ticket.machine,
            ticket=ticket,
            observation_window=observation_window,
        )
        return Response({
            "ticket": MaintenanceTicketSerializer(ticket).data,
            "evaluation_report": report,
        })

    @action(detail=True, methods=["post"], url_path="authorize-return-to-service")
    def authorize_return_to_service(self, request, pk=None):
        """
        Authorized personnel signs off safe return to service after telemetry verification.
        body: { "authorized_by": "J. Doe", "role": "Plant Operations Manager", "notes": "..." }
        """
        ticket = self.get_object()
        authorized_by = request.data.get("authorized_by", "Operations Manager")
        role = request.data.get("role", "Plant Operations Manager")
        notes = request.data.get("notes", "")

        try:
            report = RecoveryVerificationService.authorize_and_sign_off(
                ticket=ticket,
                authorized_by=authorized_by,
                notes=notes,
                role=role,
            )
            return Response({
                "ticket": MaintenanceTicketSerializer(ticket).data,
                "evaluation_report": report,
            })
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=["post"], url_path="close-with-evidence")
    def close_with_evidence(self, request, pk=None):
        """
        Closes incident only when recovery is verified and sign-off is complete.
        body: { "closed_by": "Operations Manager", "notes": "..." }
        """
        ticket = self.get_object()
        closed_by = request.data.get("closed_by", "Operations Manager")
        notes = request.data.get("notes", "")

        incident = None
        if ticket.incident_reference:
            incident = FactoryIncident.objects.filter(incident_code=ticket.incident_reference).first()

        if not incident:
            return Response({"error": f"Associated incident '{ticket.incident_reference}' not found."}, status=status.HTTP_404_NOT_FOUND)

        try:
            closed_incident = RecoveryVerificationService.close_incident_with_evidence(
                incident=incident,
                ticket=ticket,
                closed_by=closed_by,
                resolution_notes=notes,
            )
            return Response({
                "ticket": MaintenanceTicketSerializer(ticket).data,
                "incident_status": closed_incident.status,
                "incident_resolution": closed_incident.resolution_summary,
            })
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=["post"], url_path="simulate-technician-flow")
    def simulate_technician_flow(self, request, pk=None):
        """
        Controlled expo demo: executes technician flow and generates post-repair telemetry.
        body: { "mode": "HEALTHY" | "FAULTY" | "STALE", "actor": "..." }
        """
        ticket = self.get_object()
        mode = request.data.get("mode", "HEALTHY")
        actor = request.data.get("actor", "R. Sharma (Senior Diagnostic Tech)")

        try:
            result = MaintenanceSimulationService.execute_demo_technician_flow(
                ticket=ticket,
                mode=mode,
                actor=actor,
            )
            return Response(result)
        except ValidationError as e:
            return Response({"error": str(e.detail if hasattr(e, "detail") else e)}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)


class WorkOrderTransitionViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = WorkOrderTransition.objects.select_related("ticket").all()
    serializer_class = WorkOrderTransitionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["ticket", "new_state", "actor"]


class WorkOrderAttachmentViewSet(viewsets.ModelViewSet):
    queryset = WorkOrderAttachment.objects.select_related("ticket").all()
    serializer_class = WorkOrderAttachmentSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["ticket"]


class MaintenanceActivityViewSet(viewsets.ModelViewSet):
    queryset = MaintenanceActivity.objects.select_related("ticket").all()
    serializer_class = MaintenanceActivitySerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["ticket", "activity_type"]


class MaintenanceHistoryViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = MaintenanceHistory.objects.select_related("machine", "ticket").all()
    serializer_class = MaintenanceHistorySerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "maintenance_type"]
