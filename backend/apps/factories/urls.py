from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import FactoryViewSet, DepartmentViewSet, ProductionLineViewSet

router = DefaultRouter()
router.register(r"factories", FactoryViewSet, basename="factory")
router.register(r"departments", DepartmentViewSet, basename="department")
router.register(r"production-lines", ProductionLineViewSet, basename="production-line")

urlpatterns = [
    path("", include(router.urls)),
]
