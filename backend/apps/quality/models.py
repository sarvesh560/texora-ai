from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.production.models import ProductionBatch
from apps.machines.models import Machine


class DefectType(models.TextChoices):
    YARN_UNEVENNESS = "YARN_UNEVENNESS", _("Yarn Unevenness / Thick & Thin Places")
    NEP_COUNT = "NEP_COUNT", _("Excessive Neps / Trash Particles")
    MISSING_PICK = "MISSING_PICK", _("Missing Pick / Broken Weft")
    BARRE_EFFECT = "BARRE_EFFECT", _("Barre Effect / Striping in Knit")
    SHADE_VARIATION = "SHADE_VARIATION", _("Dye Shade Variation (Delta E > 0.8)")
    HOLES_DROPPED_STITCHES = "HOLES_DROPPED_STITCHES", _("Holes / Dropped Stitches")
    TENSILE_FAILURE = "TENSILE_FAILURE", _("Low CSP / Tensile Strength Failure")
    CONTAMINATION = "CONTAMINATION", _("Foreign Fiber / Oil Stain Contamination")


class QualityInspection(models.Model):
    """Laboratory & on-loom quality test records for batches."""
    inspection_code = models.CharField(max_length=50, unique=True, help_text="e.g. QC-2026-0391")
    production_batch = models.ForeignKey(ProductionBatch, on_delete=models.CASCADE, related_name="inspections")
    machine = models.ForeignKey(Machine, on_delete=models.SET_NULL, null=True, blank=True)
    inspector_name = models.CharField(max_length=150, default="Quality Assurance Lab")
    sample_size = models.DecimalField(max_digits=10, decimal_places=2, help_text="Sample size in meters / kg")
    inspected_quantity = models.DecimalField(max_digits=10, decimal_places=2)
    accepted_quantity = models.DecimalField(max_digits=10, decimal_places=2)
    rejected_quantity = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    status = models.CharField(
        max_length=30,
        choices=[
            ("PASSED", "Passed (Grade A)"),
            ("FAILED", "Failed (Off-Spec)"),
            ("CONDITIONAL_PASS", "Conditional Pass (Grade B / Discounted)"),
        ],
        default="PASSED",
    )
    overall_score = models.DecimalField(max_digits=5, decimal_places=2, default=98.50, help_text="Quality score 0-100")
    inspected_at = models.DateTimeField(auto_now_add=True)
    notes = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-inspected_at"]

    def __str__(self):
        return f"{self.inspection_code} — {self.production_batch.batch_number} [{self.status}]"


class QualityDefect(models.Model):
    """Specific defect identified during quality inspection."""
    inspection = models.ForeignKey(QualityInspection, on_delete=models.CASCADE, related_name="defects")
    defect_type = models.CharField(max_length=50, choices=DefectType.choices)
    severity = models.CharField(
        max_length=20,
        choices=[("MINOR", "Minor"), ("MAJOR", "Major"), ("CRITICAL", "Critical")],
        default="MINOR",
    )
    count = models.PositiveIntegerField(default=1)
    defect_location = models.CharField(max_length=150, blank=True, default="Fabric Edge / Center")
    root_cause_category = models.CharField(max_length=150, blank=True, default="Machine Tension / Needle Wear")
    image_url = models.URLField(blank=True, default="")

    def __str__(self):
        return f"{self.get_defect_type_display()} (Count: {self.count}) [{self.severity}]"
