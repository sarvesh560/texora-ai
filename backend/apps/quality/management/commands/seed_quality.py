from datetime import datetime, timezone, timedelta
from django.core.management.base import BaseCommand
from django.db import transaction
from apps.quality.models import QualityInspection, QualityDefect, DefectType
from apps.production.models import ProductionBatch
from apps.machines.models import Machine


class Command(BaseCommand):
    help = "Seeds realistic textile quality inspections and laboratory test records."

    @transaction.atomic
    def handle(self, *args, **options):
        self.stdout.write("--- SEEDING QUALITY INSPECTION BASELINE ---")

        batches = list(ProductionBatch.objects.select_related("machine", "production_order").all())
        if not batches:
            self.stdout.write(self.style.WARNING("No ProductionBatch found. Run seed_factory first."))
            return

        inspection_templates = [
            {
                "suffix": "SPN-01",
                "inspector": "Dr. S. Ranganathan (Head of Spinning QC)",
                "sample": 100.0,
                "inspected": 1200.0,
                "accepted": 1180.0,
                "rejected": 20.0,
                "status": "PASSED",
                "score": 98.3,
                "notes": "Yarn count Ne 40s/1 nominal. Uster unevenness CV% is 11.2% (well within 12.5% ASTM threshold).",
                "defects": [
                    (DefectType.YARN_UNEVENNESS, "MINOR", 2, "Bobbin spindle #48", "Draft apron tension wear"),
                    (DefectType.NEP_COUNT, "MINOR", 1, "Card sliver delivery", "Carding cylinder wire loading"),
                ],
            },
            {
                "suffix": "WEV-02",
                "inspector": "M. Senthilkumar (Weaving QA Specialist)",
                "sample": 150.0,
                "inspected": 1500.0,
                "accepted": 1460.0,
                "rejected": 40.0,
                "status": "PASSED",
                "score": 97.3,
                "notes": "Air-jet loom fabric audit. Warp tension nominal at 180 cN. Reed mark rate negligible.",
                "defects": [
                    (DefectType.MISSING_PICK, "MINOR", 3, "Selvage side meter 142", "Main nozzle pneumatic pulsation"),
                ],
            },
            {
                "suffix": "KNT-03",
                "inspector": "K. Murugesan (Knitting Floor Auditor)",
                "sample": 80.0,
                "inspected": 800.0,
                "accepted": 750.0,
                "rejected": 50.0,
                "status": "CONDITIONAL_PASS",
                "score": 93.8,
                "notes": "Single Jersey 180 GSM audit. Slight barre shading observed due to yarn lot tension mismatch. Grade B.",
                "defects": [
                    (DefectType.BARRE_EFFECT, "MAJOR", 2, "Tube body course 220", "Feeder #14 yarn tension differential"),
                    (DefectType.HOLES_DROPPED_STITCHES, "MINOR", 1, "Lower cylinder sector 3", "Latch needle tip microscopic burr"),
                ],
            },
            {
                "suffix": "DYE-04",
                "inspector": "V. Selvam (Chief Dyehouse Chemist)",
                "sample": 60.0,
                "inspected": 600.0,
                "accepted": 595.0,
                "rejected": 5.0,
                "status": "PASSED",
                "score": 99.2,
                "notes": "Reactive Navy Blue Delta E = 0.42 (Tolerance < 0.8). Wash fastness ISO 105-C06 rating: 4-5.",
                "defects": [
                    (DefectType.SHADE_VARIATION, "MINOR", 1, "Rope tail sample #3", "Minor dyebath cooling gradient"),
                ],
            },
            {
                "suffix": "FIN-05",
                "inspector": "M. Kavitha (Final Stenter QC Lead)",
                "sample": 200.0,
                "inspected": 2000.0,
                "accepted": 1970.0,
                "rejected": 30.0,
                "status": "PASSED",
                "score": 98.5,
                "notes": "Stenter temperature 175°C. Shrinkage length: -2.1%, width: -1.8% (Tolerance: +/- 3.0%). Approved.",
                "defects": [
                    (DefectType.CONTAMINATION, "MINOR", 1, "Fabric edge meter 18", "Guide roller oil vapor trace"),
                ],
            },
            {
                "suffix": "SPN-06",
                "inspector": "Dr. S. Ranganathan (Head of Spinning QC)",
                "sample": 80.0,
                "inspected": 950.0,
                "accepted": 950.0,
                "rejected": 0.0,
                "status": "PASSED",
                "score": 99.8,
                "notes": "Combed yarn test. Zero thick places detected on Uster Tester 5. Excellent CSP of 2850.",
                "defects": [],
            },
            {
                "suffix": "WEV-07",
                "inspector": "M. Senthilkumar (Weaving QA Specialist)",
                "sample": 100.0,
                "inspected": 700.0,
                "accepted": 640.0,
                "rejected": 60.0,
                "status": "CONDITIONAL_PASS",
                "score": 91.4,
                "notes": "Weft insertion speed slightly throttled. Secondary batch acceptable for non-export market.",
                "defects": [
                    (DefectType.MISSING_PICK, "MAJOR", 4, "Center warp zone", "Relay nozzle #4 sub-pressure"),
                ],
            },
        ]

        created_count = 0
        now = datetime.now(timezone.utc)

        for i, tpl in enumerate(inspection_templates):
            batch = batches[i % len(batches)]
            machine = batch.machine or Machine.objects.first()

            code = f"QC-2026-{tpl['suffix']}"
            insp, created = QualityInspection.objects.update_or_create(
                inspection_code=code,
                defaults={
                    "production_batch": batch,
                    "machine": machine,
                    "inspector_name": tpl["inspector"],
                    "sample_size": tpl["sample"],
                    "inspected_quantity": tpl["inspected"],
                    "accepted_quantity": tpl["accepted"],
                    "rejected_quantity": tpl["rejected"],
                    "status": tpl["status"],
                    "overall_score": tpl["score"],
                    "notes": tpl["notes"],
                },
            )
            # Update timestamp staggered over last 3 days
            QualityInspection.objects.filter(pk=insp.pk).update(
                inspected_at=now - timedelta(hours=i * 9 + 2)
            )

            # Re-seed defects
            insp.defects.all().delete()
            for dtype, severity, count, loc, cause in tpl["defects"]:
                QualityDefect.objects.create(
                    inspection=insp,
                    defect_type=dtype,
                    severity=severity,
                    count=count,
                    defect_location=loc,
                    root_cause_category=cause,
                )
            created_count += 1

        self.stdout.write(self.style.SUCCESS(f"[OK] Successfully seeded {created_count} Quality Inspections with Defects."))
