from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import InventoryItemViewSet, InventoryTransactionViewSet, SparePartRequirementViewSet

router = DefaultRouter()
router.register(r"items", InventoryItemViewSet, basename="inventory-item")
router.register(r"transactions", InventoryTransactionViewSet, basename="inventory-transaction")
router.register(r"spare-part-requirements", SparePartRequirementViewSet, basename="spare-part-requirement")

urlpatterns = [
    path("", include(router.urls)),
]
