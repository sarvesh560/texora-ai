from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import EnergyReadingViewSet

router = DefaultRouter()
router.register(r"readings", EnergyReadingViewSet, basename="energy-reading")

urlpatterns = [
    path("", include(router.urls)),
]
