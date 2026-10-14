"""
Texora AI - Controlled Production Simulation Engine (Phase 15)
Provides deterministic, bounded simulation operations:
- Seed realistic textile orders and assignments
- Advance production hours safely
- Controlled machine breakdown and recovery
- Backlog and capacity stress testing
"""

import logging
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Dict, Any, List, Optional
from django.db import transaction
from django.utils import timezone

from apps.factories.models import Department, Factory
from apps.machines.models import Machine, MachineStatus
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus, IncidentCategory
from apps.production.models import (
    ProductionOrder,
    ProductionBatch,
    MachineProductionAssignment,
    ProductionProgress,
    ProductionBottleneck,
    ProductionImpactAssessment,
    OrderStatus,
    OrderPriority,
    DelayRiskLevel,
)
from apps.production.capacity_engine import CapacityIntelligenceEngine, DEFAULT_TEXTILE_ROUTES

logger = logging.getLogger(__name__)


class ProductionSimulationService:
    """
    Controlled simulation service for advancing production runs,
    inducing machinery downtime, and restoring capacity idempotently.
    """

    @classmethod
    @transaction.atomic
    def seed_production_baseline(cls) -> Dict[str, Any]:
        """
        Seeds a rich, realistic textile production baseline with 6 multi-department
        orders, routing stages, machine assignments, and active batches.
        """
        now = timezone.now().date()

        # Department map
        depts = {d.code: d for d in Department.objects.filter(is_active=True)}
        if not depts:
            return {"success": False, "error": "No departments found in database. Run seed_factory first."}

        orders_spec = [
            {
                "order_number": "ORD-2026-SPN-101",
                "client_name": "Tirupur Knitwear Exporters",
                "customer_po": "PO-TKE-2026-904",
                "spec": "100% Combed Cotton Ne 40s Ring Spun (Waxed Hosiery)",
                "category": "COMBED_YARN",
                "dept_code": "SPN",
                "target": 12000.0,
                "done": 4200.0,
                "unit": "KG",
                "priority": OrderPriority.HIGH,
                "due_days": 4,
                "routing": DEFAULT_TEXTILE_ROUTES["SPINNING_ONLY"],
                "stage": "Ring Spinning",
            },
            {
                "order_number": "ORD-2026-WEV-202",
                "client_name": "Bombay Rayon Fashions",
                "customer_po": "PO-BRF-8821-X",
                "spec": "100% Cotton 2/40s x 2/40s Oxford Shirting (340cm Width)",
                "category": "WOVEN_SHIRTING",
                "dept_code": "WEV",
                "target": 15000.0,
                "done": 3100.0,
                "unit": "METERS",
                "priority": OrderPriority.URGENT,
                "due_days": 3,
                "routing": DEFAULT_TEXTILE_ROUTES["FULL_CYCLE"],
                "stage": "Weaving Shed",
            },
            {
                "order_number": "ORD-2026-KNT-303",
                "client_name": "Decathlon Sourcing India",
                "customer_po": "PO-DEC-IN-4402",
                "spec": "Single Jersey Greige 180 GSM (95% Cotton 5% Spandex Lycra)",
                "category": "SINGLE_JERSEY",
                "dept_code": "KNT",
                "target": 18000.0,
                "done": 7200.0,
                "unit": "KG",
                "priority": OrderPriority.MEDIUM,
                "due_days": 8,
                "routing": DEFAULT_TEXTILE_ROUTES["KNIT_CYCLE"],
                "stage": "Circular Knitting",
            },
            {
                "order_number": "ORD-2026-DYE-404",
                "client_name": "Marks & Spencer India",
                "customer_po": "PO-MSI-7719-DYE",
                "spec": "Reactive Dyed Navy Blue Cotton Interlock (Soft-Flow)",
                "category": "DYED_INTERLOCK",
                "dept_code": "DYE",
                "target": 8500.0,
                "done": 2900.0,
                "unit": "KG",
                "priority": OrderPriority.HIGH,
                "due_days": 5,
                "routing": DEFAULT_TEXTILE_ROUTES["COMMISSION_DYEING"],
                "stage": "Dyehouse Jet Vessel",
            },
            {
                "order_number": "ORD-2026-FIN-505",
                "client_name": "Raymond Apparels Ltd",
                "customer_po": "PO-RAY-FIN-2026",
                "spec": "Heat-set Compacted Finished Single Jersey Fabric (Monforts Stenter)",
                "category": "FINISHED_FABRIC",
                "dept_code": "FIN",
                "target": 10000.0,
                "done": 4500.0,
                "unit": "METERS",
                "priority": OrderPriority.MEDIUM,
                "due_days": 7,
                "routing": DEFAULT_TEXTILE_ROUTES["FULL_CYCLE"],
                "stage": "Stenter Finishing",
            },
            {
                "order_number": "ORD-2026-WEV-206",
                "client_name": "Arvind Mills Denim Division",
                "customer_po": "PO-ARV-DNM-601",
                "spec": "Heavy Indigo Denim Twill 14.5 Oz / Sq Yd",
                "category": "DENIM_TWILL",
                "dept_code": "WEV",
                "target": 22000.0,
                "done": 2100.0,
                "unit": "METERS",
                "priority": OrderPriority.URGENT,
                "due_days": 2,  # Imminent rush deadline
                "routing": DEFAULT_TEXTILE_ROUTES["WEAVING_ONLY"],
                "stage": "Heavy Loom Shed",
            },
        ]

        created_orders = []
        created_batches = []
        created_assignments = []

        for spec in orders_spec:
            dept = depts.get(spec["dept_code"])
            if not dept:
                continue

            due_date = now + timedelta(days=spec["due_days"])
            start_date = now - timedelta(days=2)

            order, _ = ProductionOrder.objects.update_or_create(
                order_number=spec["order_number"],
                defaults={
                    "client_name": spec["client_name"],
                    "customer_po_number": spec["customer_po"],
                    "fabric_or_yarn_spec": spec["spec"],
                    "product_category": spec["category"],
                    "department": dept,
                    "target_quantity": Decimal(str(spec["target"])),
                    "completed_quantity": Decimal(str(spec["done"])),
                    "unit": spec["unit"],
                    "status": OrderStatus.IN_PROGRESS,
                    "priority": spec["priority"],
                    "routing_stages": spec["routing"],
                    "current_stage": spec["stage"],
                    "start_date": start_date,
                    "due_date": due_date,
                    "target_delivery_date": due_date,
                },
            )
            created_orders.append(order)

            # Assign machine in this department
            machines_in_dept = list(Machine.objects.filter(department=dept, is_active=True))
            primary_machine = machines_in_dept[0] if machines_in_dept else None

            # Create or update active batch
            batch_num = f"BATCH-{spec['order_number'][-7:]}-01"
            planned_batch = spec["target"] / 2.0
            actual_batch = min(planned_batch, spec["done"])

            batch, _ = ProductionBatch.objects.update_or_create(
                batch_number=batch_num,
                defaults={
                    "production_order": order,
                    "department": dept,
                    "stage_name": spec["stage"],
                    "machine": primary_machine,
                    "planned_quantity": Decimal(str(planned_batch)),
                    "actual_quantity": Decimal(str(actual_batch)),
                    "defect_quantity": Decimal("15.50"),
                    "status": "RUNNING",
                    "effective_speed_pct": Decimal("100.00"),
                    "target_completion_date": timezone.now() + timedelta(days=spec["due_days"] - 1),
                    "started_at": timezone.now() - timedelta(days=2),
                },
            )
            created_batches.append(batch)

            if primary_machine:
                # Create Machine Production Assignment
                assignment, _ = MachineProductionAssignment.objects.update_or_create(
                    machine=primary_machine,
                    production_order=order,
                    defaults={
                        "production_batch": batch,
                        "department": dept,
                        "stage_name": spec["stage"],
                        "status": "RUNNING",
                        "shift": "SHIFT_1",
                        "planned_run_hours": Decimal("24.00"),
                        "actual_run_hours": Decimal("16.00"),
                        "speed_override_rpm": primary_machine.rated_speed_rpm,
                        "notes": f"Primary assignment for {spec['client_name']} ({spec['category']})",
                    },
                )
                created_assignments.append(assignment)

                # Add a progress record
                ProductionProgress.objects.create(
                    production_order=order,
                    production_batch=batch,
                    machine=primary_machine,
                    department=dept,
                    stage_name=spec["stage"],
                    quantity_produced=Decimal("450.00"),
                    cumulative_quantity=Decimal(str(spec["done"])),
                    scrap_or_defect_quantity=Decimal("6.20"),
                    efficiency_pct=Decimal("94.50"),
                    stage_status="RUNNING",
                    notes="Baseline shift progress recorded.",
                )

        # Run calculations
        CapacityIntelligenceEngine.calculate_department_capacities(target_date=now)
        CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
        CapacityIntelligenceEngine.detect_and_sync_bottlenecks()

        return {
            "success": True,
            "orders_seeded": len(created_orders),
            "batches_seeded": len(created_batches),
            "assignments_seeded": len(created_assignments),
        }

    @classmethod
    @transaction.atomic
    def advance_production(cls, hours: float = 2.0) -> Dict[str, Any]:
        """
        Advances completed production quantities across all running machine assignments
        and recalculates delivery risks and department capacities.
        """
        running_assignments = MachineProductionAssignment.objects.filter(
            status="RUNNING"
        ).select_related("machine", "production_order", "production_batch", "department")

        total_units_produced = 0.0
        updated_orders_count = 0

        for assign in running_assignments:
            m = assign.machine
            order = assign.production_order
            batch = assign.production_batch

            if m.status in [MachineStatus.CRITICAL, MachineStatus.MAINTENANCE, MachineStatus.OFFLINE]:
                continue  # Machine is down; produces 0

            # Rate: units per hour * speed factor
            speed_factor = 0.80 if m.status == MachineStatus.WARNING else 1.00
            rate = float(m.rated_capacity_units_per_hour or 50.0) * speed_factor
            produced_now = round(rate * hours, 2)
            total_units_produced += produced_now

            # Update batch
            if batch:
                batch.actual_quantity = Decimal(str(float(batch.actual_quantity) + produced_now))
                batch.save(update_fields=["actual_quantity"])

            # Update order
            new_order_done = float(order.completed_quantity) + produced_now
            target = float(order.target_quantity)
            order.completed_quantity = Decimal(str(min(target, new_order_done)))
            if new_order_done >= target:
                order.status = OrderStatus.COMPLETED
                order.completed_at = timezone.now()
            order.save(update_fields=["completed_quantity", "status", "completed_at"])
            updated_orders_count += 1

            # Log Progress
            ProductionProgress.objects.create(
                production_order=order,
                production_batch=batch,
                machine=m,
                department=assign.department,
                stage_name=assign.stage_name,
                quantity_produced=Decimal(str(produced_now)),
                cumulative_quantity=order.completed_quantity,
                scrap_or_defect_quantity=Decimal("3.50"),
                efficiency_pct=Decimal("96.00" if m.status == MachineStatus.OPERATIONAL else "78.00"),
                stage_status="COMPLETED" if order.status == OrderStatus.COMPLETED else "RUNNING",
                notes=f"Advanced {hours} hours at {rate:.1f} units/hr rate.",
            )

        # Refresh calculations
        CapacityIntelligenceEngine.calculate_department_capacities()
        CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
        CapacityIntelligenceEngine.detect_and_sync_bottlenecks()

        return {
            "success": True,
            "hours_advanced": hours,
            "total_units_produced": total_units_produced,
            "orders_updated": updated_orders_count,
        }

    @classmethod
    @transaction.atomic
    def inject_machine_breakdown(cls, machine_code: str, estimated_downtime_hours: float = 3.0) -> Dict[str, Any]:
        """
        Induces a controlled breakdown on a specific machine, pauses its active assignments,
        records a FactoryIncident, and executes deterministic impact evaluation.
        """
        machine = Machine.objects.filter(code=machine_code).first()
        if not machine:
            return {"success": False, "error": f"Machine {machine_code} not found."}

        machine.status = MachineStatus.CRITICAL
        machine.current_health_score = Decimal("48.50")
        machine.save(update_fields=["status", "current_health_score"])

        # Create or fetch active incident
        incident, _ = FactoryIncident.objects.update_or_create(
            machine=machine,
            status=IncidentStatus.OPEN,
            defaults={
                "incident_code": f"INC-SIM-{machine.code}",
                "factory": machine.department.factory,
                "department": machine.department,
                "severity": IncidentSeverity.CRITICAL,
                "category": IncidentCategory.MACHINE_HEALTH,
                "summary": f"Simulated mechanical breakdown on {machine.code} ({machine.name})",
                "root_cause_hypothesis": "Main drive shaft excessive vibration and thermal spike",
            },
        )

        # Pause machine's active assignments
        MachineProductionAssignment.objects.filter(machine=machine, status="RUNNING").update(
            status="INTERRUPTED"
        )
        ProductionBatch.objects.filter(machine=machine, status="RUNNING").update(
            status="PAUSED"
        )

        # Evaluate impact
        assessment = CapacityIntelligenceEngine.evaluate_machine_breakdown_impact(
            machine=machine,
            estimated_downtime_hours=estimated_downtime_hours,
            incident=incident,
        )

        # Recalculate bottlenecks and order timelines
        CapacityIntelligenceEngine.detect_and_sync_bottlenecks()
        CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
        CapacityIntelligenceEngine.calculate_department_capacities()

        return {
            "success": True,
            "machine_code": machine.code,
            "status": machine.status,
            "incident_code": incident.incident_code,
            "assessment_code": assessment.assessment_code,
            "output_at_risk": float(assessment.output_quantity_at_risk),
            "orders_affected": assessment.orders_affected_count,
            "delay_risk": assessment.overall_delay_risk,
        }

    @classmethod
    @transaction.atomic
    def recover_machine(cls, machine_code: str) -> Dict[str, Any]:
        """
        Restores a machine from breakdown back to OPERATIONAL, resumes interrupted
        assignments, resolves machine downtime bottlenecks, and updates capacities.
        """
        machine = Machine.objects.filter(code=machine_code).first()
        if not machine:
            return {"success": False, "error": f"Machine {machine_code} not found."}

        machine.status = MachineStatus.OPERATIONAL
        machine.current_health_score = Decimal("98.00")
        machine.save(update_fields=["status", "current_health_score"])

        # Resume assignments
        MachineProductionAssignment.objects.filter(machine=machine, status="INTERRUPTED").update(
            status="RUNNING"
        )
        ProductionBatch.objects.filter(machine=machine, status="PAUSED").update(
            status="RUNNING"
        )

        # Close active incidents
        FactoryIncident.objects.filter(
            machine=machine, status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING]
        ).update(status=IncidentStatus.RESOLVED, resolved_at=timezone.now())

        # Resolve machine bottlenecks
        ProductionBottleneck.objects.filter(
            machine=machine, bottleneck_type="MACHINE_DOWNTIME", is_active=True
        ).update(is_active=False, resolved_at=timezone.now())

        # Recalculate everything
        CapacityIntelligenceEngine.calculate_department_capacities()
        CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
        CapacityIntelligenceEngine.detect_and_sync_bottlenecks()

        return {
            "success": True,
            "machine_code": machine.code,
            "status": machine.status,
            "resumed_status": "OPERATIONAL",
        }
