import logging
from django.db.models import Count, Avg, Sum
from django.utils import timezone
from rest_framework import status, views, permissions
from rest_framework.response import Response

from .models import SimulationState, InjectedScenario, ScenarioType
from .engine import SimulationEngine
from .serializers import (
    SimulationStateSerializer,
    InjectedScenarioSerializer,
    ScenarioInjectionRequestSerializer,
    SimulationControlRequestSerializer,
    LiveMachineStatusSerializer,
)
from apps.machines.models import Machine, MachineStatus, MachineTelemetry
from apps.factories.models import Department
from apps.production.models import ProductionOrder, ProductionBatch
from apps.quality.models import QualityInspection, QualityDefect
from apps.energy.models import EnergyReading

logger = logging.getLogger(__name__)


class SimulationStatusView(views.APIView):
    """Returns current simulation state and active injected scenarios."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        state = SimulationState.get_state()
        active_scenarios = InjectedScenario.objects.filter(is_active=True)
        return Response({
            "state": SimulationStateSerializer(state).data,
            "active_scenarios": InjectedScenarioSerializer(active_scenarios, many=True).data,
            "available_scenarios": [
                {"type": choice[0], "label": str(choice[1])}
                for choice in ScenarioType.choices
            ],
        })


class SimulationStartView(views.APIView):
    """Starts the simulation engine background loop."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = SimulationControlRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        speed = serializer.validated_data.get("speed_multiplier", 1.0)
        interval = serializer.validated_data.get("tick_interval_seconds", 3.0)

        engine = SimulationEngine()
        engine.start(speed_multiplier=speed, tick_interval=interval)

        state = SimulationState.get_state()
        return Response({
            "message": "Simulation started successfully.",
            "state": SimulationStateSerializer(state).data,
        }, status=status.HTTP_200_OK)


class SimulationPauseView(views.APIView):
    """Pauses the simulation engine."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        engine = SimulationEngine()
        engine.pause()
        state = SimulationState.get_state()
        return Response({
            "message": "Simulation paused.",
            "state": SimulationStateSerializer(state).data,
        }, status=status.HTTP_200_OK)


class SimulationResumeView(views.APIView):
    """Resumes a paused simulation engine."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        engine = SimulationEngine()
        engine.resume()
        state = SimulationState.get_state()
        return Response({
            "message": "Simulation resumed.",
            "state": SimulationStateSerializer(state).data,
        }, status=status.HTTP_200_OK)


class SimulationStopView(views.APIView):
    """Stops the simulation engine."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        engine = SimulationEngine()
        engine.stop()
        state = SimulationState.get_state()
        return Response({
            "message": "Simulation stopped.",
            "state": SimulationStateSerializer(state).data,
        }, status=status.HTTP_200_OK)


class SimulationTickView(views.APIView):
    """Executes a single discrete simulation tick synchronously."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        engine = SimulationEngine()
        result = engine.run_tick()
        state = SimulationState.get_state()
        return Response({
            "message": "Simulation tick executed successfully.",
            "result": result,
            "state": SimulationStateSerializer(state).data,
        }, status=status.HTTP_200_OK)


class SimulationInjectScenarioView(views.APIView):
    """Injects a new operational anomaly scenario."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = ScenarioInjectionRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        description = data.get("description") or f"Injected {data['scenario_type']} on {data.get('target_machine_code') or 'Factory'}"

        scenario = InjectedScenario.objects.create(
            scenario_type=data["scenario_type"],
            target_machine_code=data.get("target_machine_code", ""),
            target_department_code=data.get("target_department_code", ""),
            severity=data.get("severity", "HIGH"),
            parameters=data.get("parameters", {}),
            description=description,
            is_active=True,
        )

        return Response({
            "message": f"Scenario '{scenario.get_scenario_type_display()}' injected successfully.",
            "scenario": InjectedScenarioSerializer(scenario).data,
        }, status=status.HTTP_201_CREATED)


class SimulationClearScenariosView(views.APIView):
    """Clears all active injected scenarios or a specific scenario by ID."""
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        scenario_id = request.data.get("scenario_id")
        now = timezone.now()
        if scenario_id:
            updated = InjectedScenario.objects.filter(id=scenario_id, is_active=True).update(is_active=False, cleared_at=now)
            msg = f"Scenario {scenario_id} cleared."
        else:
            updated = InjectedScenario.objects.filter(is_active=True).update(is_active=False, cleared_at=now)
            # Reset warning machine statuses back to operational
            Machine.objects.filter(status=MachineStatus.WARNING).update(status=MachineStatus.OPERATIONAL)
            msg = f"All {updated} active scenarios cleared and machine states restored."

        return Response({
            "message": msg,
            "scenarios_cleared": updated,
        }, status=status.HTTP_200_OK)


class SimulationSummaryView(views.APIView):
    """Comprehensive factory operational and simulation summary."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        state = SimulationState.get_state()
        machines = Machine.objects.filter(is_active=True).select_related("department", "machine_type").prefetch_related("telemetry_readings")
        departments = Department.objects.prefetch_related("machines").all()

        # Machine status counts
        status_counts = {}
        for s in MachineStatus.values:
            status_counts[s] = 0
        for m in machines:
            status_counts[m.status] = status_counts.get(m.status, 0) + 1

        # Department summaries
        dept_summaries = []
        for dept in departments:
            dept_machines = [m for m in machines if m.department_id == dept.id]
            dept_summaries.append({
                "id": dept.id,
                "code": dept.code,
                "name": dept.name,
                "department_type": dept.department_type,
                "total_machines": len(dept_machines),
                "operational_machines": sum(1 for m in dept_machines if m.status == MachineStatus.OPERATIONAL),
                "warning_machines": sum(1 for m in dept_machines if m.status == MachineStatus.WARNING),
                "critical_machines": sum(1 for m in dept_machines if m.status == MachineStatus.CRITICAL),
                "average_health_score": round(
                    sum(float(m.current_health_score) for m in dept_machines) / max(1, len(dept_machines)), 1
                ),
            })

        # Latest readings for all machines
        machine_list = LiveMachineStatusSerializer(machines, many=True).data

        # Recent quality inspections
        inspections = QualityInspection.objects.order_by("-inspected_at")[:5]
        failed_inspections_count = QualityInspection.objects.filter(status="FAILED").count()

        # Active orders summary
        active_orders = ProductionOrder.objects.filter(status__in=["IN_PROGRESS", "PLANNED"]).count()

        # Power load
        latest_telemetry_batch = MachineTelemetry.objects.order_by("-timestamp")[:25]
        total_instant_power_kw = round(sum(t.power_kw for t in latest_telemetry_batch), 1)

        active_scenarios = InjectedScenario.objects.filter(is_active=True)

        return Response({
            "simulation_state": SimulationStateSerializer(state).data,
            "factory_name": "Texora Smart Textile Mill — Coimbatore #1",
            "factory_code": "FAC-CBE-01",
            "total_machines": len(machines),
            "status_breakdown": status_counts,
            "total_power_kw": total_instant_power_kw,
            "active_scenarios_count": active_scenarios.count(),
            "active_scenarios": InjectedScenarioSerializer(active_scenarios, many=True).data,
            "failed_inspections_count": failed_inspections_count,
            "active_orders_count": active_orders,
            "departments": dept_summaries,
            "machines": machine_list,
        })
