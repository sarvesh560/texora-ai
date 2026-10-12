from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import QualityInspectionViewSet, QualityDefectViewSet

router = DefaultRouter()
router.register(r"inspections", QualityInspectionViewSet, basename="quality-inspection")
router.register(r"defects", QualityDefectViewSet, basename="quality-defect")

urlpatterns = [
    path("", include(router.urls)),
]
