from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    FactoryIncidentViewSet,
    AnomalyDetectionViewSet,
    DetectorStatusView,
    DetectorRunEvalView,
    IncidentsSummaryView,
)

app_name = "incidents"

router = DefaultRouter()
router.register(r"incidents", FactoryIncidentViewSet, basename="factory-incident")
router.register(r"anomalies", AnomalyDetectionViewSet, basename="anomaly-detection")

urlpatterns = [
    path("incidents/detector-status/", DetectorStatusView.as_view(), name="detector-status"),
    path("incidents/run-eval/", DetectorRunEvalView.as_view(), name="detector-run-eval"),
    path("incidents/summary/", IncidentsSummaryView.as_view(), name="incidents-summary"),
    path("", include(router.urls)),
]
