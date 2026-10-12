from django.db import models
from django.utils.translation import gettext_lazy as _


class DepartmentType(models.TextChoices):
    SPINNING = "SPINNING", _("Spinning (Yarn Production)")
    WEAVING = "WEAVING", _("Weaving (Fabric Loom)")
    KNITTING = "KNITTING", _("Knitting (Circular & Flat)")
    DYEING = "DYEING", _("Dyeing & Chemical Processing)")
    FINISHING = "FINISHING", _("Finishing & Quality Inspection)")


class Factory(models.Model):
    """Represents a textile manufacturing plant."""
    name = models.CharField(max_length=200, default="Texora Smart Textile Mill #1")
    code = models.CharField(max_length=50, unique=True, default="FAC-01")
    location = models.CharField(max_length=255, default="Coimbatore, Tamil Nadu, India")
    timezone = models.CharField(max_length=50, default="Asia/Kolkata")
    total_area_sqft = models.PositiveIntegerField(default=150000, help_text="Total factory floor area")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name_plural = "Factories"
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.code})"


class Department(models.Model):
    """Represents a production department in the textile factory."""
    factory = models.ForeignKey(Factory, on_delete=models.CASCADE, related_name="departments")
    department_type = models.CharField(
        max_length=50,
        choices=DepartmentType.choices,
        default=DepartmentType.SPINNING,
    )
    name = models.CharField(max_length=150)
    code = models.CharField(max_length=30, unique=True)
    supervisor_name = models.CharField(max_length=150, blank=True, default="")
    floor_location = models.CharField(max_length=100, blank=True, default="Bay A")
    target_efficiency_pct = models.DecimalField(max_digits=5, decimal_places=2, default=85.00)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["factory", "code"]

    def __str__(self):
        return f"{self.name} [{self.code}]"


class ProductionLine(models.Model):
    """Represents an integrated production line within a department."""
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name="production_lines")
    name = models.CharField(max_length=150)
    code = models.CharField(max_length=50, unique=True)
    description = models.TextField(blank=True, default="")
    target_capacity_units_per_hour = models.DecimalField(max_digits=10, decimal_places=2, default=1000.00)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["department", "code"]

    def __str__(self):
        return f"{self.name} ({self.code})"
