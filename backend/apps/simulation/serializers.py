from rest_framework import serializers
from .models import SimulationState, InjectedScenario, ScenarioType
from apps.machines.models import Machine, MachineTelemetry
from apps.factories.models import Department


class SimulationStateSerializer(serializers.ModelSerializer):
    is_thread_alive = serializers.SerializerMethodField()

    class Meta:
        model = SimulationState
        fields = [
            "id",
            "is_running",
            "is_paused",
            "speed_multiplier",
            "tick_interval_seconds",
            "total_ticks_generated",
            "last_tick_at",
            "started_at",
            "updated_at",
            "is_thread_alive",
        ]

    def get_is_thread_alive(self, obj) -> bool:
        from .engine import SimulationEngine
        return SimulationEngine().is_active()


class InjectedScenarioSerializer(serializers.ModelSerializer):
    scenario_type_display = serializers.CharField(source="get_scenario_type_display", read_only=True)

    class Meta:
        model = InjectedScenario
        fields = [
            "id",
            "scenario_type",
            "scenario_type_display",
            "target_machine_code",
            "target_department_code",
            "severity",
            "is_active",
            "parameters",
            "description",
            "injected_at",
            "cleared_at",
        ]


class ScenarioInjectionRequestSerializer(serializers.Serializer):
    scenario_type = serializers.ChoiceField(choices=ScenarioType.choices)
    target_machine_code = serializers.CharField(required=False, allow_blank=True, default="")
    target_department_code = serializers.CharField(required=False, allow_blank=True, default="")
    severity = serializers.ChoiceField(choices=["LOW", "MEDIUM", "HIGH", "CRITICAL"], default="HIGH")
    description = serializers.CharField(required=False, allow_blank=True, default="")
    parameters = serializers.DictField(required=False, default=dict)


class SimulationControlRequestSerializer(serializers.Serializer):
    speed_multiplier = serializers.FloatField(required=False, default=1.0, min_value=0.1, max_value=20.0)
    tick_interval_seconds = serializers.FloatField(required=False, default=3.0, min_value=0.5, max_value=60.0)


class LiveMachineStatusSerializer(serializers.ModelSerializer):
    latest_telemetry = serializers.SerializerMethodField()
    department_name = serializers.CharField(source="department.name", read_only=True)
    department_code = serializers.CharField(source="department.code", read_only=True)

    class Meta:
        model = Machine
        fields = [
            "id",
            "code",
            "name",
            "department_code",
            "department_name",
            "status",
            "current_health_score",
            "rated_capacity_units_per_hour",
            "latest_telemetry",
        ]

    def get_latest_telemetry(self, obj):
        latest = obj.telemetry_readings.first()
        if not latest:
            return None
        return {
            "timestamp": latest.timestamp.isoformat(),
            "temperature_c": latest.temperature_c,
            "vibration_mms": latest.vibration_mms,
            "speed_rpm": latest.speed_rpm,
            "power_kw": latest.power_kw,
            "utilization_pct": latest.utilization_pct,
            "output_rate": latest.output_rate,
            "status_flag": latest.status_flag,
        }
