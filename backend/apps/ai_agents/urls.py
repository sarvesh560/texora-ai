from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    AgentDefinitionViewSet,
    AgentExecutionViewSet,
    AgentDecisionViewSet,
    AgentActionViewSet,
    RecoveryCaseViewSet,
    ApprovalActionViewSet,
    MultiAgentCoordinationViewSet,
    AutonomousWorkflowViewSet,
)

router = DefaultRouter()
router.register(r"agents", AgentDefinitionViewSet, basename="agent-definition")
router.register(r"executions", AgentExecutionViewSet, basename="agent-execution")
router.register(r"ai-agents", AgentExecutionViewSet, basename="ai-agent-ops")
router.register(r"recovery-cases", RecoveryCaseViewSet, basename="recovery-case")
router.register(r"coordination", MultiAgentCoordinationViewSet, basename="multi-agent-coordination")
router.register(r"autonomous", AutonomousWorkflowViewSet, basename="autonomous-workflows")
router.register(r"decisions", AgentDecisionViewSet, basename="agent-decision")
router.register(r"actions", AgentActionViewSet, basename="agent-action")

urlpatterns = [
    path("", include(router.urls)),
]

