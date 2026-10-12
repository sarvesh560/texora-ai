from rest_framework import viewsets, permissions, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import Machine, MachineType, MachineOperatingLimits, MachineTelemetry, MachineStateHistory
from .serializers import (
    MachineSerializer,
    MachineTypeSerializer,
    MachineOperatingLimitsSerializer,
    MachineTelemetrySerializer,
    MachineStateHistorySerializer,
)


class MachineTypeViewSet(viewsets.ModelViewSet):
    queryset = MachineType.objects.all()
    serializer_class = MachineTypeSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["category"]


class MachineViewSet(viewsets.ModelViewSet):
    queryset = Machine.objects.select_related("machine_type", "department", "production_line", "operating_limits").all()
    serializer_class = MachineSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "machine_type", "status", "is_active"]
    search_fields = ["name", "code"]

    @action(detail=True, methods=["get"])
    def telemetry(self, request, pk=None):
        machine = self.get_object()
        readings = machine.telemetry_readings.all()[:100]
        serializer = MachineTelemetrySerializer(readings, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=["get"])
    def history(self, request, pk=None):
        machine = self.get_object()
        history = machine.state_history.all()[:50]
        serializer = MachineStateHistorySerializer(history, many=True)
        return Response(serializer.data)


class MachineOperatingLimitsViewSet(viewsets.ModelViewSet):
    queryset = MachineOperatingLimits.objects.all()
    serializer_class = MachineOperatingLimitsSerializer
    permission_classes = [permissions.AllowAny]


class MachineTelemetryViewSet(viewsets.ModelViewSet):
    queryset = MachineTelemetry.objects.select_related("machine").all()
    serializer_class = MachineTelemetrySerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "status_flag"]


class MachineStateHistoryViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = MachineStateHistory.objects.select_related("machine").all()
    serializer_class = MachineStateHistorySerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "trigger_source"]
