from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import CopilotSessionViewSet, CopilotSuggestionsView

router = DefaultRouter()
router.register(r"sessions", CopilotSessionViewSet, basename="copilot-sessions")

urlpatterns = [
    path("suggestions/", CopilotSuggestionsView.as_view(), name="copilot-suggestions"),
    path("", include(router.urls)),
]
