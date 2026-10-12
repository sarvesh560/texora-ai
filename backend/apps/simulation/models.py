from django.db import models
from django.utils.translation import gettext_lazy as _


class ScenarioType(models.TextChoices):
    WEAVING_VIBRATION = "WEAVING_VIBRATION", _("Weaving Loom Excessive Vibration (Bearing Wear)")
    SPINNING_OVERHEAT = "SPINNING_OVERHEAT", _("Ring Frame Spindle Bearing Overheat (Thermal Spike)")
    PRODUCTION_SLOWDOWN = "PRODUCTION_SLOWDOWN", _("Production Line Bottleneck (Speed Throttle / Tension)")
    QUALITY_DEFECT_SPIKE = "QUALITY_DEFECT_SPIKE", _("Fabric Quality Rejection (Barre / Yarn Unevenness)")
    SPARE_PART_SHORTAGE = "SPARE_PART_SHORTAGE", _("Critical Spare Parts Stock Depletion")
    ENERGY_SURGE = "ENERGY_SURGE", _("Abnormal Peak Demand Energy Spike")


class SimulationState(models.Model):
    """Singleton tracking the active state of the factory simulation engine."""
    is_running = models.BooleanField(default=False)
    is_paused = models.BooleanField(default=False)
    speed_multiplier = models.FloatField(default=1.0)
    tick_interval_seconds = models.FloatField(default=3.0)
    total_ticks_generated = models.PositiveIntegerField(default=0)
    last_tick_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    @classmethod
    def get_state(cls):
        state, _ = cls.objects.get_or_create(id=1)
        return state

    def __str__(self):
        status_str = "RUNNING" if self.is_running else ("PAUSED" if self.is_paused else "STOPPED")
        return f"Simulation: {status_str} (Ticks: {self.total_ticks_generated}, Speed: {self.speed_multiplier}x)"


class InjectedScenario(models.Model):
    """Dynamic operational anomaly or scenario injected into simulated factory machines."""
    scenario_type = models.CharField(max_length=50, choices=ScenarioType.choices)
    target_machine_code = models.CharField(max_length=50, blank=True, default="", help_text="e.g. WEV-AJ-02, SPN-RS-03")
    target_department_code = models.CharField(max_length=30, blank=True, default="", help_text="e.g. SPIN, WEAV, KNT, DYE, FIN")
    severity = models.CharField(
        max_length=20,
        choices=[("LOW", "Low"), ("MEDIUM", "Medium"), ("HIGH", "High"), ("CRITICAL", "Critical")],
        default="HIGH",
    )
    is_active = models.BooleanField(default=True, db_index=True)
    parameters = models.JSONField(default=dict, blank=True, help_text="Configurable scenario parameters")
    description = models.TextField()
    injected_at = models.DateTimeField(auto_now_add=True)
    cleared_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-injected_at"]

    def __str__(self):
        status = "ACTIVE" if self.is_active else "CLEARED"
        target = self.target_machine_code or self.target_department_code or "Factory-wide"
        return f"{self.get_scenario_type_display()} on {target} [{status}]"
