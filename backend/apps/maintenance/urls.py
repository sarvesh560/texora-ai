from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    MaintenanceTicketViewSet,
    MaintenanceActivityViewSet,
    MaintenanceHistoryViewSet,
    WorkOrderTransitionViewSet,
    WorkOrderAttachmentViewSet,
)

router = DefaultRouter()
router.register(r"tickets", MaintenanceTicketViewSet, basename="maintenance-ticket")
router.register(r"transitions", WorkOrderTransitionViewSet, basename="maintenance-transition")
router.register(r"attachments", WorkOrderAttachmentViewSet, basename="maintenance-attachment")
router.register(r"activities", MaintenanceActivityViewSet, basename="maintenance-activity")
router.register(r"history", MaintenanceHistoryViewSet, basename="maintenance-history")

urlpatterns = [
    path("", include(router.urls)),
]
