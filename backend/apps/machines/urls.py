from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    MachineViewSet,
    MachineTypeViewSet,
    MachineOperatingLimitsViewSet,
    MachineTelemetryViewSet,
    MachineStateHistoryViewSet,
)

router = DefaultRouter()
router.register(r"machines", MachineViewSet, basename="machine")
router.register(r"machine-types", MachineTypeViewSet, basename="machine-type")
router.register(r"operating-limits", MachineOperatingLimitsViewSet, basename="operating-limit")
router.register(r"telemetry", MachineTelemetryViewSet, basename="telemetry")
router.register(r"state-history", MachineStateHistoryViewSet, basename="state-history")

urlpatterns = [
    path("", include(router.urls)),
]
