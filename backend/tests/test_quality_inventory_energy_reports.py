from django.test import TestCase
from rest_framework.test import APIClient
from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType
from apps.production.models import ProductionOrder, ProductionBatch
from apps.quality.models import QualityInspection, QualityDefect, DefectType
from apps.inventory.models import InventoryItem
from apps.energy.models import EnergyReading
from datetime import datetime, timezone, timedelta


class QualityInventoryEnergyReportsApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.factory = Factory.objects.create(code="FAC-TEST", name="Test Factory")
        self.dept = Department.objects.create(
            factory=self.factory,
            code="SPN",
            name="Spinning",
            department_type=DepartmentType.SPINNING,
        )
        self.mtype = MachineType.objects.create(
            category=DepartmentType.SPINNING,
            name="Ring Frame",
            manufacturer="Rieter",
            model_number="G38",
            default_power_rating_kw=65.0,
        )
        self.machine = Machine.objects.create(
            department=self.dept,
            machine_type=self.mtype,
            code="SPN-01",
            name="Ring Frame #1",
        )
        self.order = ProductionOrder.objects.create(
            order_number="ORD-TEST-01",
            client_name="Test Client",
            fabric_or_yarn_spec="Cotton Ne 40s",
            department=self.dept,
            target_quantity=1000.0,
            completed_quantity=500.0,
            start_date=datetime.now(timezone.utc).date(),
            due_date=datetime.now(timezone.utc).date() + timedelta(days=7),
        )
        self.batch = ProductionBatch.objects.create(
            batch_number="BATCH-TEST-01",
            production_order=self.order,
            machine=self.machine,
            planned_quantity=1000.0,
            actual_quantity=500.0,
        )

        # Quality
        self.inspection = QualityInspection.objects.create(
            inspection_code="QC-TEST-01",
            production_batch=self.batch,
            machine=self.machine,
            sample_size=50.0,
            inspected_quantity=500.0,
            accepted_quantity=490.0,
            rejected_quantity=10.0,
            status="PASSED",
            overall_score=98.0,
        )
        QualityDefect.objects.create(
            inspection=self.inspection,
            defect_type=DefectType.YARN_UNEVENNESS,
            severity="MINOR",
            count=2,
        )

        # Inventory
        self.item = InventoryItem.objects.create(
            item_code="SPR-TEST-01",
            name="Bearing 6309",
            category="SPARE_PARTS",
            current_stock=10.0,
            reorder_point=5.0,
            minimum_safety_stock=2.0,
            unit_cost=1200.0,
        )

        # Energy
        self.reading = EnergyReading.objects.create(
            factory=self.factory,
            department=self.dept,
            machine=self.machine,
            timestamp=datetime.now(timezone.utc),
            active_power_kw=45.0,
            energy_kwh=12.5,
            power_factor=0.95,
        )

    def test_quality_summary_api(self):
        resp = self.client.get("/api/v1/inspections/summary/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["total_inspections"], 1)
        self.assertEqual(resp.data["pass_rate_pct"], 100.0)

    def test_inventory_summary_api(self):
        resp = self.client.get("/api/v1/items/summary/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["total_items"], 1)
        self.assertEqual(resp.data["total_inventory_value_inr"], 12000.0)

    def test_energy_summary_api(self):
        resp = self.client.get("/api/v1/readings/summary/")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["total_consumption_kwh"], 12.5)

    def test_reports_overview_api(self):
        resp = self.client.get("/api/v1/reports/overview/?category=quality")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["category"], "quality")

    def test_reports_export_csv_api(self):
        resp = self.client.get("/api/v1/reports/export/?category=inventory")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "text/csv")
        self.assertIn("SPR-TEST-01", resp.content.decode("utf-8"))
