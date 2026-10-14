from django.urls import path
from .views import HealthCheckView, ReadinessCheckView, WorkerHealthStatusView
from .reports_views import ReportsAnalyticsView, ReportsExportCsvView

urlpatterns = [
    path("health/", HealthCheckView.as_view(), name="health-check"),
    path("health/readiness/", ReadinessCheckView.as_view(), name="readiness-check"),
    path("health/workers/", WorkerHealthStatusView.as_view(), name="worker-health-status"),
    path("health/status/", WorkerHealthStatusView.as_view(), name="system-health-status"),
    path("reports/", ReportsAnalyticsView.as_view(), name="reports-base"),
    path("reports/overview/", ReportsAnalyticsView.as_view(), name="reports-overview"),
    path("reports/export/", ReportsExportCsvView.as_view(), name="reports-export-csv"),
]
