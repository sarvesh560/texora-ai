from rest_framework import viewsets, permissions
from .models import ProductionOrder, ProductionBatch, ProductionSchedule, ProductionOutput, ProductionDelay
from .serializers import (
    ProductionOrderSerializer,
    ProductionBatchSerializer,
    ProductionScheduleSerializer,
    ProductionOutputSerializer,
    ProductionDelaySerializer,
)


class ProductionOrderViewSet(viewsets.ModelViewSet):
    queryset = ProductionOrder.objects.select_related("department").prefetch_related("batches").all()
    serializer_class = ProductionOrderSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "status", "priority"]
    search_fields = ["order_number", "client_name", "fabric_or_yarn_spec"]


class ProductionBatchViewSet(viewsets.ModelViewSet):
    queryset = ProductionBatch.objects.select_related("production_order", "machine").all()
    serializer_class = ProductionBatchSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "machine", "status"]


class ProductionScheduleViewSet(viewsets.ModelViewSet):
    queryset = ProductionSchedule.objects.select_related("production_order", "machine", "production_line").all()
    serializer_class = ProductionScheduleSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "machine", "shift", "is_active"]


class ProductionOutputViewSet(viewsets.ModelViewSet):
    queryset = ProductionOutput.objects.select_related("production_batch", "machine").all()
    serializer_class = ProductionOutputSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_batch", "machine"]


class ProductionDelayViewSet(viewsets.ModelViewSet):
    queryset = ProductionDelay.objects.select_related("production_order", "production_batch", "machine").all()
    serializer_class = ProductionDelaySerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "delay_reason"]
