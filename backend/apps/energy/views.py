from rest_framework import viewsets, permissions
from .models import EnergyReading
from .serializers import EnergyReadingSerializer


class EnergyReadingViewSet(viewsets.ModelViewSet):
    queryset = EnergyReading.objects.select_related("factory", "department", "machine").all()
    serializer_class = EnergyReadingSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "machine", "is_peak_hour"]
