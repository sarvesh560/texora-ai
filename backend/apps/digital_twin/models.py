import uuid
from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.factories.models import Factory


class MachineTwinState(models.TextChoices):
    RUNNING = "RUNNING", _("Running (Nominal Operation)")
    WARNING = "WARNING", _("Warning (Telemetry Sub-optimal / Threshold Warning)")
    CRITICAL = "CRITICAL", _("Critical (Severe Anomaly / Active Incident)")
    IDLE = "IDLE", _("Idle (Standby / Waiting Material)")
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE", _("Under Maintenance / Active Work Order)")
    OFFLINE = "OFFLINE", _("Offline (Powered Down / Disconnected)")
    UNKNOWN = "UNKNOWN", _("Unknown (Missing / Stale Telemetry)")


class DigitalTwinSnapshot(models.Model):
    """Immutable virtual factory snapshot constructed from live/simulated database records."""
    snapshot_id = models.CharField(max_length=64, unique=True, db_index=True)
    factory = models.ForeignKey(Factory, on_delete=models.CASCADE, related_name="digital_twin_snapshots")
    captured_at = models.DateTimeField(auto_now_add=True, db_index=True)
    total_machines = models.PositiveIntegerField(default=25)
    operational_summary = models.JSONField(
        default=dict,
        help_text="Department summaries, state distribution, efficiency, and active incident counts",
    )
    machine_states = models.JSONField(
        default=list,
        help_text="Full list of 25 machine virtual twin states, sensor telemetry, and assignments",
    )
    is_baseline = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-captured_at"]

    def __str__(self):
        return f"Snapshot {self.snapshot_id} [{self.factory.code}] @ {self.captured_at.strftime('%Y-%m-%d %H:%M:%S')}"


class ScenarioType(models.TextChoices):
    SINGLE_MACHINE_FAILURE = "SINGLE_MACHINE_FAILURE", _("Single Machine Failure (Specific Asset)")
    MULTI_MACHINE_FAILURE = "MULTI_MACHINE_FAILURE", _("Multi-Machine / Department Cluster Failure")
    CROSS_DEPARTMENT_DISRUPTION = "CROSS_DEPARTMENT_DISRUPTION", _("Cross-Department Material Flow Disruption")
    DEMAND_SURGE = "DEMAND_SURGE", _("Production Demand Surge / Capacity Stress")
    CUSTOM = "CUSTOM", _("Custom Configured Scenario")


class SparePartsAvailability(models.TextChoices):
    FULL = "FULL", _("Full Stock Available in Warehouse")
    PARTIAL = "PARTIAL", _("Partial Stock (Requires Allocation Priority)")
    UNAVAILABLE = "UNAVAILABLE", _("Out of Stock / Stockout Risk")


class RecoveryStrategyType(models.TextChoices):
    ALL_COMPARISON = "ALL_COMPARISON", _("Compare All Feasible Strategies (A, B, C)")
    STRATEGY_A = "STRATEGY_A", _("Strategy A: Repair Affected Machine First")
    STRATEGY_B = "STRATEGY_B", _("Strategy B: Shift Production to Compatible Alternates")
    STRATEGY_C = "STRATEGY_C", _("Strategy C: Hybrid Prioritized Repair & Partial Rerouting")


class WhatIfScenario(models.Model):
    """Deterministic simulation scenario specification for evaluating hypothetical factory changes."""
    scenario_id = models.CharField(max_length=64, unique=True, db_index=True)
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True, default="")
    scenario_type = models.CharField(
        max_length=50, choices=ScenarioType.choices, default=ScenarioType.SINGLE_MACHINE_FAILURE
    )
    baseline_snapshot = models.ForeignKey(
        DigitalTwinSnapshot, on_delete=models.SET_NULL, null=True, blank=True, related_name="scenarios"
    )
    
    # Input simulation levers
    failure_duration_hours = models.FloatField(default=4.0, help_text="Hypothetical failure duration in hours")
    repair_duration_hours = models.FloatField(default=3.0, help_text="Estimated repair duration in hours")
    capacity_reduction_pct = models.FloatField(default=100.0, help_text="Capacity loss on failed machines (0-100%)")
    spare_parts_availability = models.CharField(
        max_length=30, choices=SparePartsAvailability.choices, default=SparePartsAvailability.FULL
    )
    technicians_available = models.PositiveIntegerField(default=2, help_text="Available maintenance staff count")
    demand_variation_pct = models.FloatField(default=0.0, help_text="Demand variation from baseline (+/- %)")
    shift_duration_hours = models.FloatField(default=8.0)
    selected_strategy = models.CharField(
        max_length=40, choices=RecoveryStrategyType.choices, default=RecoveryStrategyType.ALL_COMPARISON
    )
    
    is_demo_scenario = models.BooleanField(default=False)
    demo_code = models.CharField(max_length=50, blank=True, default="", help_text="e.g. DEMO_A, DEMO_B, DEMO_C")
    
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.scenario_id} — {self.name} [{self.scenario_type}]"


class ScenarioMachineChange(models.Model):
    """Explicit machine state modification within a hypothetical scenario."""
    scenario = models.ForeignKey(WhatIfScenario, on_delete=models.CASCADE, related_name="machine_changes")
    machine_code = models.CharField(max_length=50, help_text="e.g. WEV-AJ-02")
    simulated_state = models.CharField(
        max_length=30, choices=MachineTwinState.choices, default=MachineTwinState.CRITICAL
    )
    failure_type = models.CharField(
        max_length=100, default="BEARING_FAILURE", help_text="e.g. BEARING_SEIZURE, MOTOR_OVERHEAT, YARN_BREAK"
    )
    capacity_loss_pct = models.FloatField(default=100.0)

    class Meta:
        ordering = ["machine_code"]

    def __str__(self):
        return f"{self.scenario.scenario_id}: {self.machine_code} -> {self.simulated_state} ({self.failure_type})"


class SimulationRun(models.Model):
    """Record of an executed deterministic simulation run."""
    run_id = models.UUIDField(default=uuid.uuid4, unique=True, editable=False, db_index=True)
    scenario = models.ForeignKey(WhatIfScenario, on_delete=models.CASCADE, related_name="runs")
    status = models.CharField(
        max_length=30,
        choices=[("STARTED", "Started"), ("COMPLETED", "Completed"), ("FAILED", "Failed")],
        default="STARTED",
    )
    executed_at = models.DateTimeField(auto_now_add=True, db_index=True)
    execution_duration_ms = models.PositiveIntegerField(default=0)
    error_message = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-executed_at"]

    def __str__(self):
        return f"Run {self.run_id} ({self.scenario.scenario_id}) [{self.status}]"


class SimulationResult(models.Model):
    """Calculated deterministic results, production impact, and timeline events for a simulation run."""
    run = models.OneToOneField(SimulationRun, on_delete=models.CASCADE, related_name="result")
    baseline_capacity_per_hour = models.JSONField(default=dict)
    simulated_capacity_per_hour = models.JSONField(default=dict)
    lost_machine_operating_hours = models.FloatField(default=0.0)
    capacity_reduction_pct = models.FloatField(default=0.0)
    estimated_output_loss = models.JSONField(
        default=dict, help_text="Output loss segmented strictly by unit type (e.g. {'meters': 1200, 'kg': 450})"
    )
    potential_order_delays = models.JSONField(default=list, help_text="List of impacted production orders")
    bottleneck_department = models.CharField(max_length=50, blank=True, default="WEV")
    alternative_machine_utilization = models.JSONField(default=list, help_text="Compatible alternate machines and rerouted units")
    timeline_events = models.JSONField(default=list, help_text="Chronological event frames for playback mode")
    data_provenance = models.JSONField(
        default=dict, help_text="Audit trace of underlying real records vs demo scenario parameters"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Result for Run {self.run.run_id} (Lost Hours: {self.lost_machine_operating_hours}h, Cap Loss: {self.capacity_reduction_pct}%)"


class EffectivenessLevel(models.TextChoices):
    HIGH_EFFECTIVENESS = "HIGH_EFFECTIVENESS", _("High Effectiveness (Full Asset Restoration & High Output Protection)")
    MODERATE_EFFECTIVENESS = "MODERATE_EFFECTIVENESS", _("Moderate Effectiveness (Partial Restoration / Moderate Output Loss)")
    TEMPORARY_WORKAROUND = "TEMPORARY_WORKAROUND", _("Temporary Workaround (0% Asset Recovery / Ongoing Retooling Overhead)")
    INFEASIBLE = "INFEASIBLE", _("Infeasible (Resource / Capacity Boundary Violation)")


class RecoveryStrategyEvaluation(models.Model):
    """Evaluation of a specific recovery strategy generated by the simulation engine."""
    run = models.ForeignKey(SimulationRun, on_delete=models.CASCADE, related_name="strategy_evaluations")
    strategy_code = models.CharField(
        max_length=30, choices=RecoveryStrategyType.choices, default=RecoveryStrategyType.STRATEGY_A
    )
    strategy_name = models.CharField(max_length=150)
    is_feasible = models.BooleanField(default=True)
    effectiveness_level = models.CharField(
        max_length=40, choices=EffectivenessLevel.choices, default=EffectivenessLevel.HIGH_EFFECTIVENESS
    )
    infeasibility_reasons = models.JSONField(default=list, blank=True)
    estimated_downtime_hours = models.FloatField(default=0.0)
    capacity_recovered_pct = models.FloatField(default=0.0)
    estimated_output_loss = models.JSONField(default=dict)
    unmitigated_baseline_loss = models.JSONField(default=dict, blank=True, help_text="Loss if no strategy is applied")
    volume_protected_units = models.JSONField(default=dict, blank=True, help_text="Output volume saved by this strategy")
    recovery_time_hours = models.FloatField(default=0.0)
    resource_utilization = models.JSONField(
        default=dict, help_text="Staff technicians and spare parts utilization"
    )
    estimated_cost = models.JSONField(
        default=dict, help_text="Labor, parts, and downtime loss financial estimate with formula breakdown"
    )
    rank = models.PositiveIntegerField(default=1)
    is_tied = models.BooleanField(default=False, help_text="True if tied on primary metrics with another strategy")
    tie_breaker_note = models.CharField(max_length=255, blank=True, default="")
    pros = models.JSONField(default=list)
    cons = models.JSONField(default=list)

    class Meta:
        ordering = ["rank", "estimated_downtime_hours"]

    def __str__(self):
        feasible_str = "FEASIBLE" if self.is_feasible else "INFEASIBLE"
        tied_str = " (Tied)" if self.is_tied else ""
        return f"{self.strategy_name} (Rank {self.rank}{tied_str}) [{feasible_str} - {self.effectiveness_level}]"
