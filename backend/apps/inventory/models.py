from django.db import models
from django.utils.translation import gettext_lazy as _
from apps.machines.models import MachineType


class InventoryCategory(models.TextChoices):
    SPARE_PART = "SPARE_PART", _("Machine Spare Part (Bearings, Belts, Needles)")
    RAW_MATERIAL = "RAW_MATERIAL", _("Raw Fiber & Cotton Bales")
    CHEMICAL_DYE = "CHEMICAL_DYE", _("Dyes & Auxiliary Finishing Chemicals")
    PACKAGING = "PACKAGING", _("Cones, Tubes & Poly-wrap Packaging")
    CONSUMABLE = "CONSUMABLE", _("Lubricants, Machine Oils & Filters")


class InventoryItem(models.Model):
    """Warehouse stock item for factory maintenance and production."""
    item_code = models.CharField(max_length=50, unique=True, help_text="e.g. SPR-BRG-6204, DYE-BLU-250")
    name = models.CharField(max_length=200)
    category = models.CharField(
        max_length=50, choices=InventoryCategory.choices, default=InventoryCategory.SPARE_PART, db_index=True
    )
    current_stock = models.DecimalField(max_digits=12, decimal_places=2, default=0.00)
    minimum_safety_stock = models.DecimalField(max_digits=12, decimal_places=2, default=5.00)
    reorder_point = models.DecimalField(max_digits=12, decimal_places=2, default=10.00)
    unit = models.CharField(
        max_length=20,
        choices=[("PCS", "Pieces"), ("KG", "Kilograms"), ("LITERS", "Liters"), ("METERS", "Meters"), ("BOXES", "Boxes")],
        default="PCS",
    )
    unit_cost = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    location_shelf = models.CharField(max_length=100, blank=True, default="Shelf A-12")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["category", "name"]

    def __str__(self):
        return f"{self.item_code} — {self.name} ({self.current_stock} {self.unit})"

    @property
    def is_low_stock(self):
        return self.current_stock <= self.reorder_point


class InventoryTransaction(models.Model):
    """Stock movement history (issue to machine, receipt from supplier, reserve by agent)."""
    item = models.ForeignKey(InventoryItem, on_delete=models.CASCADE, related_name="transactions")
    transaction_type = models.CharField(
        max_length=30,
        choices=[
            ("RECEIPT", "Receipt from Supplier"),
            ("ISSUE", "Issued for Maintenance / Production"),
            ("RESERVATION", "Reserved by AI Agent Workflow"),
            ("ADJUSTMENT", "Inventory Count Audit Adjustment"),
            ("RETURN", "Returned to Stock"),
        ],
    )
    quantity = models.DecimalField(max_digits=10, decimal_places=2)
    reference_number = models.CharField(
        max_length=100, blank=True, default="", help_text="PO number, Maintenance Ticket, or Incident code"
    )
    recorded_by = models.CharField(max_length=150, default="Warehouse System")
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)
    notes = models.TextField(blank=True, default="")

    class Meta:
        ordering = ["-timestamp"]


class SparePartRequirement(models.Model):
    """Maps critical spare parts required for specific textile machine types."""
    machine_type = models.ForeignKey(MachineType, on_delete=models.CASCADE, related_name="spare_part_requirements")
    item = models.ForeignKey(InventoryItem, on_delete=models.CASCADE, related_name="machine_requirements")
    recommended_quantity = models.PositiveIntegerField(default=2)
    replacement_interval_hours = models.PositiveIntegerField(default=2000, help_text="Mean time between replacement")

    def __str__(self):
        return f"{self.machine_type.name} requires {self.item.name} ({self.recommended_quantity} {self.item.unit})"
