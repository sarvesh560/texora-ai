from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import ApprovalRequest, ApprovalStatus
from .serializers import ApprovalRequestSerializer
from apps.ai_agents.action_service import ActionSafetyService


class ApprovalRequestViewSet(viewsets.ModelViewSet):
    queryset = ApprovalRequest.objects.select_related("incident", "agent_action").all()
    serializer_class = ApprovalRequestSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["status", "risk_level", "incident"]
    search_fields = ["approval_code", "title", "requested_action"]

    @action(detail=True, methods=["post"])
    def approve(self, request, pk=None):
        approval = self.get_object()
        approved_by = request.data.get("approved_by", "Factory Operations Manager")
        response_notes = request.data.get("response_notes", "Approved via Operations Portal")

        result = ActionSafetyService.approve_and_execute(
            approval_id=approval.id,
            approved_by=approved_by,
            response_notes=response_notes,
        )

        if not result.get("success"):
            return Response(result, status=status.HTTP_400_BAD_REQUEST)

        approval.refresh_from_db()
        data = self.get_serializer(approval).data
        data["execution_result"] = result.get("result")
        return Response(data)

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        approval = self.get_object()
        rejected_by = request.data.get("approved_by", "Factory Operations Manager")
        response_notes = request.data.get("response_notes", "Rejected by Operations Manager")

        result = ActionSafetyService.reject_approval(
            approval_id=approval.id,
            rejected_by=rejected_by,
            response_notes=response_notes,
        )

        if not result.get("success"):
            return Response(result, status=status.HTTP_400_BAD_REQUEST)

        approval.refresh_from_db()
        return Response(self.get_serializer(approval).data)

    @action(detail=True, methods=["post"], url_path="request-revision")
    def request_revision(self, request, pk=None):
        approval = self.get_object()
        requested_by = request.data.get("approved_by", "Factory Operations Manager")
        response_notes = request.data.get("response_notes", "Revision requested by Operations Manager")

        result = ActionSafetyService.request_revision(
            approval_id=approval.id,
            requested_by=requested_by,
            response_notes=response_notes,
        )

        if not result.get("success"):
            return Response(result, status=status.HTTP_400_BAD_REQUEST)

        approval.refresh_from_db()
        return Response(self.get_serializer(approval).data)

