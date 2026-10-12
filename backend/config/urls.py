"""
Texora AI - Root URL Configuration
"""

from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("apps.core.urls")),
    path("api/v1/", include("apps.factories.urls")),
    path("api/v1/", include("apps.machines.urls")),
    path("api/v1/", include("apps.production.urls")),
    path("api/v1/", include("apps.maintenance.urls")),
    path("api/v1/maintenance/", include("apps.maintenance.urls")),
    path("api/v1/", include("apps.quality.urls")),
    path("api/v1/", include("apps.inventory.urls")),
    path("api/v1/", include("apps.energy.urls")),
    path("api/v1/", include("apps.incidents.urls")),
    path("api/v1/", include("apps.ai_agents.urls")),
    path("api/v1/", include("apps.approvals.urls")),
    path("api/v1/", include("apps.audit_logs.urls")),
    path("api/v1/", include("apps.simulation.urls")),
    path("api/v1/", include("apps.digital_twin.urls")),
]
