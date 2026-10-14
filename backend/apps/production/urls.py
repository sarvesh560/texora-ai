from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    ProductionOrderViewSet,
    ProductionBatchViewSet,
    ProductionScheduleViewSet,
    ProductionOutputViewSet,
    ProductionDelayViewSet,
    MachineProductionAssignmentViewSet,
    ProductionProgressViewSet,
    ProductionCapacityProfileViewSet,
    ProductionBottleneckViewSet,
    ProductionImpactAssessmentViewSet,
    ProductionOverviewAPIView,
    ProductionDepartmentCapacityAPIView,
    ProductionBottleneckAnalysisAPIView,
    ProductionDelayRiskAPIView,
    ProductionTimelineAPIView,
    ProductionSimulateProgressionAPIView,
)

router = DefaultRouter()
router.register(r"orders", ProductionOrderViewSet, basename="production-order")
router.register(r"batches", ProductionBatchViewSet, basename="production-batch")
router.register(r"assignments", MachineProductionAssignmentViewSet, basename="production-assignment")
router.register(r"progress", ProductionProgressViewSet, basename="production-progress")
router.register(r"capacity-profiles", ProductionCapacityProfileViewSet, basename="production-capacity-profile")
router.register(r"bottlenecks-list", ProductionBottleneckViewSet, basename="production-bottleneck-list")
router.register(r"impact-assessments", ProductionImpactAssessmentViewSet, basename="production-impact-assessment")
router.register(r"schedules", ProductionScheduleViewSet, basename="production-schedule")
router.register(r"outputs", ProductionOutputViewSet, basename="production-output")
router.register(r"delays", ProductionDelayViewSet, basename="production-delay")

urlpatterns = [
    # Phase 15 Dedicated Production Intelligence API Endpoints
    path("overview/", ProductionOverviewAPIView.as_view(), name="production-overview"),
    path("department-capacity/", ProductionDepartmentCapacityAPIView.as_view(), name="production-department-capacity"),
    path("bottlenecks/", ProductionBottleneckAnalysisAPIView.as_view(), name="production-bottlenecks"),
    path("delay-risk/", ProductionDelayRiskAPIView.as_view(), name="production-delay-risk"),
    path("impact/", ProductionImpactAssessmentViewSet.as_view({"get": "list"}), name="production-impact"),
    path("timeline/", ProductionTimelineAPIView.as_view(), name="production-timeline"),
    path("simulate-progression/", ProductionSimulateProgressionAPIView.as_view(), name="production-simulate-progression"),

    # Router ViewSets
    path("", include(router.urls)),
]
