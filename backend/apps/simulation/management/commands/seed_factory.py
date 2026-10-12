from datetime import datetime, timezone, timedelta, date
from django.core.management.base import BaseCommand
from django.db import transaction
from apps.factories.models import Factory, Department, ProductionLine, DepartmentType
from apps.machines.models import Machine, MachineType, MachineOperatingLimits, MachineStatus
from apps.production.models import ProductionOrder, ProductionBatch, ProductionSchedule, OrderStatus, OrderPriority
from apps.inventory.models import InventoryItem, InventoryCategory, SparePartRequirement
from apps.ai_agents.models import AgentDefinition, AgentType
from apps.simulation.models import SimulationState


class Command(BaseCommand):
    help = "Seeds the Texora AI database with a comprehensive, realistic textile factory baseline (Idempotent)."

    @transaction.atomic
    def handle(self, *args, **options):
        self.stdout.write(self.style.NOTICE("--- SEEDING TEXORA AI TEXTILE FACTORY BASELINE ---"))

        # 1. Seed Factory
        factory, _ = Factory.objects.update_or_create(
            code="FAC-CBE-01",
            defaults={
                "name": "Texora Smart Textile Mill — Coimbatore #1",
                "location": "Avinashi Road Industrial Zone, Coimbatore, Tamil Nadu, India",
                "timezone": "Asia/Kolkata",
                "total_area_sqft": 185000,
                "is_active": True,
            },
        )
        self.stdout.write(self.style.SUCCESS(f"[OK] Factory: {factory.name}"))

        # 2. Seed Departments
        dept_data = [
            (DepartmentType.SPINNING, "Spinning Department", "SPN", "Dr. S. Ranganathan", "Bay 1 — Blowroom to Ring Spinning"),
            (DepartmentType.WEAVING, "Weaving Shed", "WEV", "K. Murugesan", "Bay 2 — High Speed Loom Shed"),
            (DepartmentType.KNITTING, "Knitting Division", "KNT", "P. Anand Kumar", "Bay 3 — Circular & Seamless Knitting"),
            (DepartmentType.DYEING, "Dyeing & Processing", "DYE", "V. Selvam", "Bay 4 — HTHP Dyehouse & Bleaching"),
            (DepartmentType.FINISHING, "Finishing & Packaging", "FIN", "M. Kavitha", "Bay 5 — Stenter, Compactor & Final QC"),
        ]

        departments = {}
        for dtype, name, code, supervisor, location in dept_data:
            dept, _ = Department.objects.update_or_create(
                code=code,
                defaults={
                    "factory": factory,
                    "department_type": dtype,
                    "name": name,
                    "supervisor_name": supervisor,
                    "floor_location": location,
                    "target_efficiency_pct": 88.0,
                    "is_active": True,
                },
            )
            departments[code] = dept
        self.stdout.write(self.style.SUCCESS(f"[OK] Seeded {len(departments)} factory departments."))

        # 3. Seed Production Lines
        line_data = [
            ("SPN", "SPN-LINE-A", "Combed Ring Yarn Line 1 (Ne 40s/1)"),
            ("SPN", "SPN-LINE-B", "Carded Hosiery Yarn Line 2 (Ne 30s/1)"),
            ("WEV", "WEV-LINE-A", "Air-Jet High Speed Shirting Line"),
            ("WEV", "WEV-LINE-B", "Heavy Twill & Denim Weaving Line"),
            ("KNT", "KNT-LINE-A", "Single Jersey Greige Fabric Line"),
            ("KNT", "KNT-LINE-B", "Interlock & Rib Knitting Line"),
            ("DYE", "DYE-LINE-A", "Reactive Fabric Soft-Flow Range"),
            ("FIN", "FIN-LINE-A", "Stenter Heat-Setting & Compacting Line"),
        ]

        lines = {}
        for dcode, lcode, lname in line_data:
            line, _ = ProductionLine.objects.update_or_create(
                code=lcode,
                defaults={
                    "department": departments[dcode],
                    "name": lname,
                    "target_capacity_units_per_hour": 750.0,
                    "is_active": True,
                },
            )
            lines[lcode] = line

        # 4. Seed Machine Types
        mtypes_data = [
            # Spinning
            (DepartmentType.SPINNING, "High-Production Carding Machine", "Trützschler", "TC 19i", 35.0),
            (DepartmentType.SPINNING, "Autoleveller Draw Frame", "Rieter", "RSB-D 50", 22.0),
            (DepartmentType.SPINNING, "Ring Spinning Frame (1632 Spindles)", "Rieter", "G 38 Compact", 65.0),
            (DepartmentType.SPINNING, "Automatic Cone Winder", "Murata / Muratec", "QPRO EX", 40.0),
            # Weaving
            (DepartmentType.WEAVING, "High-Speed Direct Warping Machine", "Karl Mayer", "WARP-O-MATIC", 55.0),
            (DepartmentType.WEAVING, "Air Jet Loom 340cm", "Picanol", "OmniPlus-i", 15.0),
            (DepartmentType.WEAVING, "High Performance Air Jet Loom", "Toyota", "JAT810", 14.5),
            (DepartmentType.WEAVING, "High-Speed Rapier Loom", "Itema", "R9500-2", 12.0),
            # Knitting
            (DepartmentType.KNITTING, "Single Jersey Circular Knitter (30in/28G)", "Mayer & Cie", "MV 4-3.2 II", 8.5),
            (DepartmentType.KNITTING, "Double Jersey Interlock Knitter", "Terrot", "I3P 196", 9.0),
            (DepartmentType.KNITTING, "Computerized Flat Knitting Machine", "Shima Seiki", "SVR 123", 5.5),
            # Dyeing
            (DepartmentType.DYEING, "HTHP Soft Flow Fabric Dyeing Vessel", "Fongs", "Tecwin HTHP", 45.0),
            (DepartmentType.DYEING, "Eco-Friendly Low Liquor Ratio Dyeing", "Thies", "iMaster H2O", 38.0),
            (DepartmentType.DYEING, "Yarn Package Dyeing Vessel", "Fongs", "ALLWIN Package", 30.0),
            # Finishing
            (DepartmentType.FINISHING, "8-Chamber Fabric Stenter Frame", "Monforts", "Montex 8500", 120.0),
            (DepartmentType.FINISHING, "Tubular / Open Width Compactor", "Ferraro", "Comptex REVO", 28.0),
            (DepartmentType.FINISHING, "Automatic Fabric Inspection & Grading Table", "Daroitex", "Roll-Check 3000", 4.5),
        ]

        mtypes = {}
        for cat, mname, mfg, model, kw in mtypes_data:
            mt, _ = MachineType.objects.update_or_create(
                name=mname,
                category=cat,
                defaults={
                    "manufacturer": mfg,
                    "model_number": model,
                    "default_power_rating_kw": kw,
                },
            )
            mtypes[mname] = mt

        # 5. Seed 25 Machines with Operating Limits
        machines_data = [
            # Spinning (5 Machines)
            ("SPN-CARD-01", "Trützschler Carding Machine #1", "High-Production Carding Machine", "SPN", "SPN-LINE-A", 450, 95.0, 70.0, 80.0, 4.2, 5.5, 300, 550, 40.0),
            ("SPN-DRAW-01", "Rieter Draw Frame #1", "Autoleveller Draw Frame", "SPN", "SPN-LINE-A", 900, 180.0, 65.0, 75.0, 3.5, 4.8, 600, 1100, 25.0),
            ("SPN-RS-01", "Rieter Ring Frame G38 #1", "Ring Spinning Frame (1632 Spindles)", "SPN", "SPN-LINE-A", 19500, 42.0, 74.0, 85.0, 3.8, 5.2, 14000, 22000, 70.0),
            ("SPN-RS-02", "Rieter Ring Frame G38 #2", "Ring Spinning Frame (1632 Spindles)", "SPN", "SPN-LINE-A", 19200, 41.5, 74.0, 85.0, 3.8, 5.2, 14000, 22000, 70.0),
            ("SPN-WND-01", "Murata Auto-Coner #1", "Automatic Cone Winder", "SPN", "SPN-LINE-A", 1800, 85.0, 68.0, 78.0, 3.2, 4.5, 1200, 2200, 45.0),
            
            # Spinning Line B (2 Machines)
            ("SPN-RS-03", "Rieter Ring Frame G38 #3", "Ring Spinning Frame (1632 Spindles)", "SPN", "SPN-LINE-B", 18800, 40.0, 74.0, 85.0, 3.8, 5.2, 14000, 22000, 70.0),
            ("SPN-WND-02", "Murata Auto-Coner #2", "Automatic Cone Winder", "SPN", "SPN-LINE-B", 1800, 85.0, 68.0, 78.0, 3.2, 4.5, 1200, 2200, 45.0),

            # Weaving (6 Machines)
            ("WEV-WARP-01", "Karl Mayer Warping Machine", "High-Speed Direct Warping Machine", "WEV", "WEV-LINE-A", 1100, 350.0, 60.0, 72.0, 3.0, 4.2, 800, 1300, 60.0),
            ("WEV-AJ-01", "Picanol OmniPlus-i Loom #1", "Air Jet Loom 340cm", "WEV", "WEV-LINE-A", 1050, 48.0, 68.0, 80.0, 4.0, 5.8, 700, 1200, 16.0),
            ("WEV-AJ-02", "Picanol OmniPlus-i Loom #2", "Air Jet Loom 340cm", "WEV", "WEV-LINE-A", 1050, 48.0, 68.0, 80.0, 4.0, 5.8, 700, 1200, 16.0),
            ("WEV-AJ-03", "Toyota JAT810 Loom #3", "High Performance Air Jet Loom", "WEV", "WEV-LINE-A", 1000, 45.0, 66.0, 78.0, 3.8, 5.5, 700, 1150, 15.0),
            ("WEV-AJ-04", "Toyota JAT810 Loom #4", "High Performance Air Jet Loom", "WEV", "WEV-LINE-B", 1000, 45.0, 66.0, 78.0, 3.8, 5.5, 700, 1150, 15.0),
            ("WEV-RAP-01", "Itema R9500-2 Rapier Loom", "High-Speed Rapier Loom", "WEV", "WEV-LINE-B", 680, 36.0, 65.0, 76.0, 4.2, 6.0, 450, 800, 14.0),

            # Knitting (4 Machines)
            ("KNT-CS-01", "Mayer & Cie Circular Knitter #1", "Single Jersey Circular Knitter (30in/28G)", "KNT", "KNT-LINE-A", 32, 28.0, 55.0, 68.0, 2.5, 3.8, 18, 38, 9.5),
            ("KNT-CS-02", "Mayer & Cie Circular Knitter #2", "Single Jersey Circular Knitter (30in/28G)", "KNT", "KNT-LINE-A", 32, 28.0, 55.0, 68.0, 2.5, 3.8, 18, 38, 9.5),
            ("KNT-DBL-01", "Terrot Interlock Knitter #1", "Double Jersey Interlock Knitter", "KNT", "KNT-LINE-B", 26, 24.0, 56.0, 70.0, 2.8, 4.0, 15, 32, 10.0),
            ("KNT-FLAT-01", "Shima Seiki Flat Knitter #1", "Computerized Flat Knitting Machine", "KNT", "KNT-LINE-B", 120, 12.0, 50.0, 65.0, 2.0, 3.2, 60, 150, 6.0),

            # Dyeing (4 Machines)
            ("DYE-SF-01", "Fongs Soft Flow Vessel #1 (500kg)", "HTHP Soft Flow Fabric Dyeing Vessel", "DYE", "DYE-LINE-A", 350, 125.0, 132.0, 142.0, 3.0, 4.5, 100, 450, 48.0),
            ("DYE-SF-02", "Fongs Soft Flow Vessel #2 (1000kg)", "HTHP Soft Flow Fabric Dyeing Vessel", "DYE", "DYE-LINE-A", 350, 250.0, 132.0, 142.0, 3.0, 4.5, 100, 450, 52.0),
            ("DYE-THIES-01", "Thies iMaster Vessel #1", "Eco-Friendly Low Liquor Ratio Dyeing", "DYE", "DYE-LINE-A", 320, 200.0, 130.0, 140.0, 2.8, 4.2, 100, 400, 42.0),
            ("DYE-PKG-01", "Fongs Yarn Package Dyeing #1", "Yarn Package Dyeing Vessel", "DYE", "DYE-LINE-A", 280, 150.0, 128.0, 138.0, 2.5, 3.8, 80, 350, 32.0),

            # Finishing (4 Machines)
            ("FIN-STNT-01", "Monforts 8-Chamber Stenter Frame", "8-Chamber Fabric Stenter Frame", "FIN", "FIN-LINE-A", 80, 650.0, 190.0, 215.0, 3.5, 5.0, 40, 100, 130.0),
            ("FIN-COMP-01", "Ferraro Revo Compactor", "Tubular / Open Width Compactor", "FIN", "FIN-LINE-A", 45, 450.0, 110.0, 135.0, 2.8, 4.0, 20, 60, 30.0),
            ("FIN-INSP-01", "Daroitex Fabric Inspection Table #1", "Automatic Fabric Inspection & Grading Table", "FIN", "FIN-LINE-A", 60, 500.0, 45.0, 55.0, 1.5, 2.5, 20, 90, 5.0),
            ("FIN-INSP-02", "Daroitex Fabric Inspection Table #2", "Automatic Fabric Inspection & Grading Table", "FIN", "FIN-LINE-A", 60, 500.0, 45.0, 55.0, 1.5, 2.5, 20, 90, 5.0),
        ]

        seeded_machines = []
        for code, mname, type_name, dcode, lcode, rpm, cap, w_temp, m_temp, w_vib, m_vib, min_rpm, max_rpm, max_kw in machines_data:
            machine, _ = Machine.objects.update_or_create(
                code=code,
                defaults={
                    "name": mname,
                    "machine_type": mtypes[type_name],
                    "department": departments[dcode],
                    "production_line": lines.get(lcode),
                    "status": MachineStatus.OPERATIONAL,
                    "rated_speed_rpm": rpm,
                    "rated_capacity_units_per_hour": cap,
                    "current_health_score": 98.50,
                    "installation_date": date(2023, 6, 15),
                    "last_serviced_at": datetime.now(timezone.utc) - timedelta(days=14),
                    "is_active": True,
                },
            )
            # Create/update operating limits
            MachineOperatingLimits.objects.update_or_create(
                machine=machine,
                defaults={
                    "warning_temp_c": w_temp,
                    "max_temp_c": m_temp,
                    "warning_vibration_mms": w_vib,
                    "max_vibration_mms": m_vib,
                    "min_rpm": min_rpm,
                    "max_rpm": max_rpm,
                    "max_power_kw": max_kw,
                    "max_utilization_pct": 100.0,
                },
            )
            seeded_machines.append(machine)

        self.stdout.write(self.style.SUCCESS(f"[OK] Seeded {len(seeded_machines)} physical machines with operational limits."))

        # 6. Seed Inventory Items (Spare parts, Dyes, Raw cotton)
        inventory_data = [
            ("SPR-BRG-6204", "SKF High Speed Spindle Bearing 6204-2Z", InventoryCategory.SPARE_PART, 45.0, 10.0, 15.0, "PCS", 350.0),
            ("SPR-BRG-6309", "FAG Heavy Duty Loom Main Bearing 6309", InventoryCategory.SPARE_PART, 12.0, 4.0, 6.0, "PCS", 1250.0),
            ("SPR-BELT-SPN", "Habasit Spindle Drive Flat Belt (Synthetic)", InventoryCategory.SPARE_PART, 8.0, 2.0, 4.0, "PCS", 2200.0),
            ("SPR-WEFT-AJ", "Picanol Optical Weft Sensor Unit", InventoryCategory.SPARE_PART, 6.0, 2.0, 3.0, "PCS", 4800.0),
            ("SPR-NDL-G28", "Groz-Beckert Circular Knitting Needles (Gauge 28)", InventoryCategory.SPARE_PART, 500.0, 100.0, 150.0, "PCS", 45.0),
            ("SPR-SEAL-PUMP", "Silicon Carbide Mechanical Pump Seal (Dyeing)", InventoryCategory.SPARE_PART, 4.0, 2.0, 3.0, "PCS", 3200.0),
            ("SPR-STNT-CLIP", "Monforts Stenter Pin-Clip Holder Assembly", InventoryCategory.SPARE_PART, 18.0, 5.0, 8.0, "PCS", 1850.0),
            ("RAW-COT-MCU5", "Raw Cotton Bales — Shankar-6 / MCU-5 (Coimbatore)", InventoryCategory.RAW_MATERIAL, 14500.0, 2000.0, 4000.0, "KG", 185.0),
            ("DYE-BLU-250", "Diresul / Reactive Navy Blue RGB Dye 250%", InventoryCategory.CHEMICAL_DYE, 480.0, 50.0, 100.0, "KG", 620.0),
            ("DYE-RED-3BS", "Reactive Deep Red 3BS Dye", InventoryCategory.CHEMICAL_DYE, 320.0, 40.0, 80.0, "KG", 680.0),
            ("OIL-KLUB-46", "Klüber ISO VG 46 High-Temp Synthetic Machine Oil", InventoryCategory.CONSUMABLE, 240.0, 40.0, 60.0, "LITERS", 450.0),
        ]

        inv_items = {}
        for code, iname, cat, stock, min_s, reorder, unit, cost in inventory_data:
            item, _ = InventoryItem.objects.update_or_create(
                item_code=code,
                defaults={
                    "name": iname,
                    "category": cat,
                    "current_stock": stock,
                    "minimum_safety_stock": min_s,
                    "reorder_point": reorder,
                    "unit": unit,
                    "unit_cost": cost,
                    "is_active": True,
                },
            )
            inv_items[code] = item
        self.stdout.write(self.style.SUCCESS(f"[OK] Seeded {len(inv_items)} inventory items."))

        # 7. Seed Spare Part Requirement Matrix
        SparePartRequirement.objects.update_or_create(
            machine_type=mtypes["Ring Spinning Frame (1632 Spindles)"],
            item=inv_items["SPR-BRG-6204"],
            defaults={"recommended_quantity": 4, "replacement_interval_hours": 3000},
        )
        SparePartRequirement.objects.update_or_create(
            machine_type=mtypes["Air Jet Loom 340cm"],
            item=inv_items["SPR-BRG-6309"],
            defaults={"recommended_quantity": 2, "replacement_interval_hours": 4000},
        )
        SparePartRequirement.objects.update_or_create(
            machine_type=mtypes["HTHP Soft Flow Fabric Dyeing Vessel"],
            item=inv_items["SPR-SEAL-PUMP"],
            defaults={"recommended_quantity": 1, "replacement_interval_hours": 2500},
        )

        # 8. Seed Production Orders
        orders_data = [
            ("ORD-2026-SPN-101", "Tirupur Knitwear Exporters", "100% Combed Cotton Ne 40s Ring Spun", "SPN", 10000.0, 3200.0, OrderStatus.IN_PROGRESS, OrderPriority.HIGH, 5),
            ("ORD-2026-WEV-202", "Bombay Rayon Fashions", "100% Cotton 2/40s x 2/40s Oxford Shirting", "WEV", 8000.0, 1500.0, OrderStatus.IN_PROGRESS, OrderPriority.URGENT, 7),
            ("ORD-2026-KNT-303", "Decathlon Sourcing India", "Single Jersey Greige 180 GSM (95% Cotton 5% Spandex)", "KNT", 12000.0, 4800.0, OrderStatus.IN_PROGRESS, OrderPriority.MEDIUM, 10),
            ("ORD-2026-DYE-404", "Marks & Spencer India", "Reactive Dyed Navy Blue Cotton Interlock (Finished)", "DYE", 6000.0, 2100.0, OrderStatus.IN_PROGRESS, OrderPriority.HIGH, 6),
            ("ORD-2026-FIN-505", "Raymond Apparels Ltd", "Heat-set Compacted Finished Single Jersey Fabric", "FIN", 7500.0, 2900.0, OrderStatus.IN_PROGRESS, OrderPriority.MEDIUM, 8),
        ]

        for onum, client, spec, dcode, target, done, ostatus, prio, days in orders_data:
            order, _ = ProductionOrder.objects.update_or_create(
                order_number=onum,
                defaults={
                    "client_name": client,
                    "fabric_or_yarn_spec": spec,
                    "department": departments[dcode],
                    "target_quantity": target,
                    "completed_quantity": done,
                    "unit": "KG" if dcode in ["SPN", "KNT", "DYE", "FIN"] else "METERS",
                    "status": ostatus,
                    "priority": prio,
                    "start_date": datetime.now(timezone.utc).date() - timedelta(days=2),
                    "due_date": datetime.now(timezone.utc).date() + timedelta(days=days),
                },
            )
            # Create active batch linked to first machine of department
            first_machine = Machine.objects.filter(department=departments[dcode]).first()
            ProductionBatch.objects.update_or_create(
                batch_number=f"BATCH-{onum[-7:]}-01",
                defaults={
                    "production_order": order,
                    "machine": first_machine,
                    "planned_quantity": target / 2,
                    "actual_quantity": done,
                    "status": "RUNNING",
                    "started_at": datetime.now(timezone.utc) - timedelta(days=2),
                },
            )

        self.stdout.write(self.style.SUCCESS("[OK] Seeded active production orders and batches."))

        # 9. Seed AI Agent Definitions
        agents_data = [
            (AgentType.MACHINE_HEALTH, "Machine Health Diagnostic Agent", "Continuously monitors vibration, temperature and RPM telemetry to detect mechanical degradation.", ["throttle_machine_speed", "create_maintenance_ticket", "flag_machine_warning"]),
            (AgentType.MAINTENANCE, "Maintenance & Work Order Agent", "Dispatches technician work orders, orders spare parts and logs root-cause resolutions.", ["create_maintenance_ticket", "assign_technician", "reserve_spare_parts"]),
            (AgentType.PRODUCTION_IMPACT, "Production Rescheduling & Impact Agent", "Calculates order delay bottlenecks and automatically reroutes jobs across parallel looms/frames.", ["reroute_production_batch", "reschedule_order_shift", "request_manager_approval"]),
            (AgentType.QUALITY_CONTROL, "Quality Assurance & CSP Optimization Agent", "Correlates on-line yarn unevenness and fabric defects with machine draft ratios and spindle speeds.", ["adjust_spindle_speed", "flag_quality_rejection", "quarantine_batch"]),
            (AgentType.INVENTORY, "Inventory & Spare Parts Allocation Agent", "Monitors safety stock, triggers purchase requisitions and allocates emergency bearings.", ["reserve_inventory", "create_purchase_requisition"]),
            (AgentType.ENERGY, "Energy Optimization & Peak Shaving Agent", "Identifies abnormal kW surges, optimizes thermal stenter heat, and schedules energy intensive dyeing.", ["stagger_machine_startup", "flag_energy_surge"]),
        ]

        for atype, aname, desc, permitted in agents_data:
            AgentDefinition.objects.update_or_create(
                agent_type=atype,
                defaults={
                    "name": aname,
                    "description": desc,
                    "permitted_actions": permitted,
                    "is_enabled": True,
                    "sensitivity_threshold": 0.75,
                },
            )
        self.stdout.write(self.style.SUCCESS(f"[OK] Seeded {len(agents_data)} Autonomous AI Agent Definitions."))

        # 10. Ensure Simulation State is initialized
        SimulationState.get_state()
        self.stdout.write(self.style.SUCCESS("--- FACTORY SEEDING COMPLETED SUCCESSFULLY ---"))
