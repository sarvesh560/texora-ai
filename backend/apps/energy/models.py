from django.db import models
from apps.factories.models import Factory, Department
from apps.machines.models import Machine


class EnergyReading(models.Model):
    """Sub-metered electrical energy consumption reading."""
    factory = models.ForeignKey(Factory, on_delete=models.CASCADE, related_name="energy_readings")
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="energy_readings")
    machine = models.ForeignKey(
        Machine, on_delete=models.SET_NULL, null=True, blank=True, related_name="energy_readings"
    )
    timestamp = models.DateTimeField(db_index=True)
    active_power_kw = models.FloatField(help_text="Instantaneous kW load")
    energy_kwh = models.FloatField(help_text="Cumulative or interval kWh")
    power_factor = models.FloatField(default=0.92)
    voltage_v = models.FloatField(default=415.0)
    current_amps = models.FloatField(default=65.0)
    peak_demand_kw = models.FloatField(default=0.0)
    carbon_emission_kg = models.FloatField(default=0.0, help_text="Calculated CO2 equivalent")
    is_peak_hour = models.BooleanField(default=False)

    class Meta:
        ordering = ["-timestamp"]
        indexes = [
            models.Index(fields=["department", "-timestamp"]),
            models.Index(fields=["machine", "-timestamp"]),
        ]

    def __str__(self):
        target = self.machine.code if self.machine else self.department.code
        return f"Energy: {target} @ {self.timestamp.strftime('%Y-%m-%d %H:%M')} ({self.active_power_kw} kW)"
