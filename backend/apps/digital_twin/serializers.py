from rest_framework import serializers
from .models import (
    DigitalTwinSnapshot,
    WhatIfScenario,
    ScenarioMachineChange,
    SimulationRun,
    SimulationResult,
    RecoveryStrategyEvaluation,
)


class ScenarioMachineChangeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ScenarioMachineChange
        fields = [
            "id",
            "machine_code",
            "simulated_state",
            "failure_type",
            "capacity_loss_pct",
        ]


class RecoveryStrategyEvaluationSerializer(serializers.ModelSerializer):
    class Meta:
        model = RecoveryStrategyEvaluation
        fields = [
            "id",
            "strategy_code",
            "strategy_name",
            "is_feasible",
            "effectiveness_level",
            "infeasibility_reasons",
            "estimated_downtime_hours",
            "capacity_recovered_pct",
            "unmitigated_baseline_loss",
            "estimated_output_loss",
            "volume_protected_units",
            "recovery_time_hours",
            "resource_utilization",
            "estimated_cost",
            "rank",
            "is_tied",
            "tie_breaker_note",
            "pros",
            "cons",
        ]


class SimulationResultSerializer(serializers.ModelSerializer):
    class Meta:
        model = SimulationResult
        fields = [
            "id",
            "baseline_capacity_per_hour",
            "simulated_capacity_per_hour",
            "lost_machine_operating_hours",
            "capacity_reduction_pct",
            "estimated_output_loss",
            "potential_order_delays",
            "bottleneck_department",
            "alternative_machine_utilization",
            "timeline_events",
            "data_provenance",
            "created_at",
        ]


class SimulationRunSerializer(serializers.ModelSerializer):
    result = SimulationResultSerializer(read_only=True)
    strategy_evaluations = RecoveryStrategyEvaluationSerializer(many=True, read_only=True)

    class Meta:
        model = SimulationRun
        fields = [
            "id",
            "run_id",
            "scenario",
            "status",
            "executed_at",
            "execution_duration_ms",
            "error_message",
            "result",
            "strategy_evaluations",
        ]


class WhatIfScenarioSerializer(serializers.ModelSerializer):
    machine_changes = ScenarioMachineChangeSerializer(many=True, read_only=True)
    latest_run = serializers.SerializerMethodField()

    class Meta:
        model = WhatIfScenario
        fields = [
            "id",
            "scenario_id",
            "name",
            "description",
            "scenario_type",
            "baseline_snapshot",
            "failure_duration_hours",
            "repair_duration_hours",
            "capacity_reduction_pct",
            "spare_parts_availability",
            "technicians_available",
            "demand_variation_pct",
            "shift_duration_hours",
            "selected_strategy",
            "is_demo_scenario",
            "demo_code",
            "machine_changes",
            "latest_run",
            "created_at",
            "updated_at",
        ]

    def get_latest_run(self, obj):
        run = obj.runs.order_by("-executed_at").first()
        if run:
            return SimulationRunSerializer(run).data
        return None


class WhatIfScenarioCreateSerializer(serializers.ModelSerializer):
    machine_codes = serializers.ListField(
        child=serializers.CharField(), required=False, default=list
    )
    failure_type = serializers.CharField(required=False, default="MECHANICAL_FAILURE")

    class Meta:
        model = WhatIfScenario
        fields = [
            "name",
            "description",
            "scenario_type",
            "failure_duration_hours",
            "repair_duration_hours",
            "capacity_reduction_pct",
            "spare_parts_availability",
            "technicians_available",
            "demand_variation_pct",
            "shift_duration_hours",
            "selected_strategy",
            "machine_codes",
            "failure_type",
        ]


class DigitalTwinSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = DigitalTwinSnapshot
        fields = [
            "id",
            "snapshot_id",
            "factory",
            "captured_at",
            "total_machines",
            "operational_summary",
            "machine_states",
            "is_baseline",
            "created_at",
        ]
