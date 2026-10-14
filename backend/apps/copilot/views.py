import uuid
import logging
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.machines.models import Machine, MachineStatus
from apps.incidents.models import FactoryIncident, IncidentStatus
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.inventory.models import InventoryItem

from .models import CopilotSession, CopilotMessage
from .serializers import (
    CopilotSessionSerializer,
    CopilotMessageSerializer,
    CopilotChatRequestSerializer,
    SuggestedQuestionSerializer,
)
from .reasoning_engine import CopilotReasoningEngine

logger = logging.getLogger(__name__)


class CopilotSessionViewSet(viewsets.ModelViewSet):
    """
    CRUD ViewSet for Factory AI Copilot conversation sessions.
    Lookup by session_id (e.g. COP-XXXXXXXXXXXX).
    """
    queryset = CopilotSession.objects.all().order_by("-updated_at")
    serializer_class = CopilotSessionSerializer
    lookup_field = "session_id"

    def create(self, request, *args, **kwargs):
        title = request.data.get("title", "Factory Operations Consultation")
        active_machine = request.data.get("active_machine_code", "")
        active_incident = request.data.get("active_incident_code", "")

        session_id = f"COP-{uuid.uuid4().hex[:12].upper()}"
        session = CopilotSession.objects.create(
            session_id=session_id,
            title=title,
            active_machine_code=active_machine,
            active_incident_code=active_incident,
        )

        serializer = self.get_serializer(session)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["get"], url_path="messages")
    def messages(self, request, session_id=None):
        """Returns all message turns in this session."""
        session = self.get_object()
        msgs = session.messages.all().order_by("created_at")
        serializer = CopilotMessageSerializer(msgs, many=True)
        return Response({
            "session_id": session.session_id,
            "title": session.title,
            "active_machine_code": session.active_machine_code,
            "active_incident_code": session.active_incident_code,
            "message_count": msgs.count(),
            "messages": serializer.data,
        })

    @action(detail=True, methods=["post"], url_path="chat")
    def chat(self, request, session_id=None):
        """Processes a user question within this session."""
        session = self.get_object()
        req_serializer = CopilotChatRequestSerializer(data=request.data)
        if not req_serializer.is_valid():
            return Response(req_serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        user_text = req_serializer.validated_data["message"]

        try:
            assistant_msg = CopilotReasoningEngine.process_user_query(
                session=session,
                user_query=user_text,
            )
            serializer = CopilotMessageSerializer(assistant_msg)
            return Response(serializer.data, status=status.HTTP_200_OK)
        except Exception as exc:
            logger.exception("Error processing Copilot chat query: %s", exc)
            return Response(
                {
                    "error": "Failed to process Copilot query",
                    "details": str(exc),
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


class CopilotSuggestionsView(APIView):
    """
    Returns contextual suggested prompts dynamically generated
    from live/simulated factory state.
    """

    def get(self, request, *args, **kwargs):
        suggestions = []

        # 1. Critical / Warning machine query
        problem_machine = Machine.objects.filter(
            status__in=[MachineStatus.CRITICAL, MachineStatus.WARNING]
        ).first() or Machine.objects.filter(code="WEV-AJ-02").first()
        if problem_machine:
            suggestions.append({
                "id": "sug-machine-status",
                "category": "MACHINE_HEALTH",
                "prompt": f"What is the current operational status and vibration of {problem_machine.code}?",
                "description": f"Examine real-time sensor limits and telemetry for {problem_machine.code}",
                "target_entity": problem_machine.code,
            })
            suggestions.append({
                "id": "sug-machine-why",
                "category": "ROOT_CAUSE",
                "prompt": f"Why did {problem_machine.code} experience an anomaly?",
                "description": f"Inspect specialist AI diagnostic findings for {problem_machine.code}",
                "target_entity": problem_machine.code,
            })

        # 2. Active Incident query
        active_incident = FactoryIncident.objects.filter(
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING]
        ).first()
        if active_incident:
            suggestions.append({
                "id": "sug-incident-rec",
                "category": "INCIDENT_RECOVERY",
                "prompt": f"What is the recommended recovery strategy for {active_incident.incident_code}?",
                "description": f"Review Digital Twin recovery options (A, B, C) for {active_incident.incident_code}",
                "target_entity": active_incident.incident_code,
            })

        # 3. Pending Approvals query
        pending_count = ApprovalRequest.objects.filter(status=ApprovalStatus.PENDING).count()
        if pending_count > 0:
            suggestions.append({
                "id": "sug-approvals",
                "category": "GOVERNANCE",
                "prompt": "Which AI agent actions are currently waiting for manager approval?",
                "description": f"Review {pending_count} pending governance approval gates",
                "target_entity": "APPROVALS",
            })

        # 4. Inventory / Spare Parts query
        low_stock_part = InventoryItem.objects.filter(category="SPARE_PART").first()
        part_code = low_stock_part.item_code if low_stock_part else "SPR-BRG-6204"
        suggestions.append({
            "id": "sug-inventory",
            "category": "INVENTORY",
            "prompt": f"Do we have {part_code} bearing spare parts in stock?",
            "description": "Check warehouse safety stock, reorder points, and availability",
            "target_entity": part_code,
        })

        # 5. Factory Health Overview
        suggestions.append({
            "id": "sug-factory-overview",
            "category": "FACTORY_OVERVIEW",
            "prompt": "Provide a plant-wide operational health and efficiency overview",
            "description": "Review total active looms, overall health score, and operational status",
            "target_entity": "FACTORY",
        })

        serializer = SuggestedQuestionSerializer(suggestions, many=True)
        return Response({"suggestions": serializer.data}, status=status.HTTP_200_OK)
