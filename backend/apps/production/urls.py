from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    ProductionOrderViewSet,
    ProductionBatchViewSet,
    ProductionScheduleViewSet,
    ProductionOutputViewSet,
    ProductionDelayViewSet,
)

router = DefaultRouter()
router.register(r"orders", ProductionOrderViewSet, basename="production-order")
router.register(r"batches", ProductionBatchViewSet, basename="production-batch")
router.register(r"schedules", ProductionScheduleViewSet, basename="production-schedule")
router.register(r"outputs", ProductionOutputViewSet, basename="production-output")
router.register(r"delays", ProductionDelayViewSet, basename="production-delay")

urlpatterns = [
    path("", include(router.urls)),
]
