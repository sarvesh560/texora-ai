from rest_framework import viewsets, permissions
from .models import QualityInspection, QualityDefect
from .serializers import QualityInspectionSerializer, QualityDefectSerializer


class QualityInspectionViewSet(viewsets.ModelViewSet):
    queryset = QualityInspection.objects.select_related("production_batch", "machine").prefetch_related("defects").all()
    serializer_class = QualityInspectionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_batch", "machine", "status"]
    search_fields = ["inspection_code", "inspector_name"]


class QualityDefectViewSet(viewsets.ModelViewSet):
    queryset = QualityDefect.objects.select_related("inspection").all()
    serializer_class = QualityDefectSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["inspection", "defect_type", "severity"]
