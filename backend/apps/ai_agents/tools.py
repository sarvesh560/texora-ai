"""
Validated Read-Only Industrial Tools for the Machine Health Specialist Agent.
All tools strictly query actual Django ORM models without allowing arbitrary code execution.
"""
from typing import Dict, Any, List, Optional
from django.utils import timezone
from apps.machines.models import Machine, MachineOperatingLimits, MachineTelemetry
from apps.incidents.models import FactoryIncident, IncidentStatus
from apps.maintenance.models import MaintenanceTicket
from apps.production.models import ProductionBatch, ProductionOrder
from apps.inventory.models import InventoryItem, InventoryCategory


def _get_machine(machine_id_or_code: Any) -> Optional[Machine]:
    """Helper to resolve Machine by either integer ID or string code."""
    if isinstance(machine_id_or_code, int) or (isinstance(machine_id_or_code, str) and machine_id_or_code.isdigit()):
        return Machine.objects.filter(id=int(machine_id_or_code)).select_related("department", "department__factory").first()
    return Machine.objects.filter(code__iexact=str(machine_id_or_code).strip()).select_related("department", "department__factory").first()


def get_machine_details(machine_id_or_code: Any) -> Dict[str, Any]:
    """
    Tool 1: Retrieves machine metadata, specifications, operational status, and health score.
    """
    machine = _get_machine(machine_id_or_code)
    if not machine:
        return {"error": f"Machine '{machine_id_or_code}' not found."}

    return {
        "id": machine.id,
        "code": machine.code,
        "name": machine.name,
        "factory": machine.department.factory.name,
        "department": machine.department.name,
        "department_code": machine.department.code,
        "status": machine.status,
        "current_health_score": float(machine.current_health_score),
        "model_number": getattr(machine.machine_type, "model_number", ""),
        "manufacturer": getattr(machine.machine_type, "manufacturer", ""),
        "serial_number": getattr(machine, "serial_number", ""),
        "rated_speed_rpm": machine.rated_speed_rpm,
        "rated_capacity_units_per_hour": float(machine.rated_capacity_units_per_hour),
        "last_serviced_at": machine.last_serviced_at.isoformat() if machine.last_serviced_at else None,
        "installation_date": str(machine.installation_date) if machine.installation_date else None,
        "is_active": machine.is_active,
    }


def get_recent_machine_telemetry(machine_id_or_code: Any, limit: int = 20) -> Dict[str, Any]:
    """
    Tool 2: Retrieves high-frequency physical telemetry readings (temperature, vibration, RPM, kW).
    """
    machine = _get_machine(machine_id_or_code)
    if not machine:
        return {"error": f"Machine '{machine_id_or_code}' not found."}

    limit = min(max(1, limit), 50)
    readings = (
        MachineTelemetry.objects.filter(machine=machine)
        .order_by("-timestamp")[:limit]
    )

    data = []
    for r in readings:
        data.append({
            "id": r.id,
            "timestamp": r.timestamp.isoformat(),
            "temperature_c": r.temperature_c,
            "vibration_mms": r.vibration_mms,
            "speed_rpm": r.speed_rpm,
            "power_kw": r.power_kw,
            "utilization_pct": r.utilization_pct,
            "output_rate": r.output_rate,
            "status_flag": r.status_flag,
            "raw_sensor_data": r.raw_sensor_data,
        })

    return {
        "machine_code": machine.code,
        "record_count": len(data),
        "telemetry_history": data,
    }


def get_machine_operating_limits(machine_id_or_code: Any) -> Dict[str, Any]:
    """
    Tool 3: Retrieves calibrated industrial operating thresholds and safety limits.
    """
    machine = _get_machine(machine_id_or_code)
    if not machine:
        return {"error": f"Machine '{machine_id_or_code}' not found."}

    limits = getattr(machine, "operating_limits", None)
    if not limits:
        return {
            "machine_code": machine.code,
            "warning": "No specific operating limits configured; using system defaults.",
            "warning_temp_c": 75.0,
            "max_temp_c": 85.0,
            "warning_vibration_mms": 4.0,
            "max_vibration_mms": 5.5,
            "min_rpm": 1000,
            "max_rpm": 22000,
            "max_power_kw": 60.0,
        }

    return {
        "machine_code": machine.code,
        "warning_temp_c": limits.warning_temp_c,
        "max_temp_c": limits.max_temp_c,
        "warning_vibration_mms": limits.warning_vibration_mms,
        "max_vibration_mms": limits.max_vibration_mms,
        "min_rpm": limits.min_rpm,
        "max_rpm": limits.max_rpm,
        "max_power_kw": limits.max_power_kw,
        "max_utilization_pct": limits.max_utilization_pct,
    }


def get_machine_maintenance_history(machine_id_or_code: Any, limit: int = 10) -> Dict[str, Any]:
    """
    Tool 4: Retrieves historical maintenance work orders, technician logs, and previous failures.
    """
    machine = _get_machine(machine_id_or_code)
    if not machine:
        return {"error": f"Machine '{machine_id_or_code}' not found."}

    limit = min(max(1, limit), 25)
    tickets = (
        MaintenanceTicket.objects.filter(machine=machine)
        .order_by("-created_at")[:limit]
    )

    ticket_list = []
    for t in tickets:
        ticket_list.append({
            "ticket_number": t.ticket_number,
            "title": t.title,
            "priority": t.priority,
            "status": t.status,
            "assigned_technician": t.assigned_technician,
            "created_by_agent": t.created_by_agent,
            "root_cause": t.root_cause,
            "corrective_action": t.corrective_action,
            "labor_hours": float(t.labor_hours),
            "parts_cost": float(t.parts_cost),
            "created_at": t.created_at.isoformat(),
            "resolved_at": t.resolved_at.isoformat() if t.resolved_at else None,
        })

    return {
        "machine_code": machine.code,
        "total_tickets": len(ticket_list),
        "maintenance_history": ticket_list,
    }


def get_active_machine_incidents(machine_id_or_code: Any) -> Dict[str, Any]:
    """
    Tool 5: Retrieves active or open factory operational incidents for the given machine.
    """
    machine = _get_machine(machine_id_or_code)
    if not machine:
        return {"error": f"Machine '{machine_id_or_code}' not found."}

    incidents = (
        FactoryIncident.objects.filter(
            machine=machine,
            status__in=[IncidentStatus.OPEN, IncidentStatus.INVESTIGATING, IncidentStatus.MITIGATING],
        )
        .order_by("-detected_at")
    )

    incident_list = []
    for inc in incidents:
        incident_list.append({
            "id": inc.id,
            "incident_code": inc.incident_code,
            "severity": inc.severity,
            "category": inc.category,
            "status": inc.status,
            "summary": inc.summary,
            "root_cause_hypothesis": inc.root_cause_hypothesis,
            "evidence_data": inc.evidence_data,
            "detected_at": inc.detected_at.isoformat(),
        })

    return {
        "machine_code": machine.code,
        "active_incidents_count": len(incident_list),
        "incidents": incident_list,
    }


def get_affected_production_orders(machine_id_or_code: Any) -> Dict[str, Any]:
    """
    Tool 6: Retrieves active production batches, client orders, and due dates running on this machine.
    """
    machine = _get_machine(machine_id_or_code)
    if not machine:
        return {"error": f"Machine '{machine_id_or_code}' not found."}

    batches = (
        ProductionBatch.objects.filter(
            machine=machine,
            status__in=["STAGED", "RUNNING", "PAUSED"],
        )
        .select_related("production_order")
        .order_by("-created_at")[:10]
    )

    batch_list = []
    for b in batches:
        order = b.production_order
        batch_list.append({
            "batch_number": b.batch_number,
            "order_number": order.order_number,
            "client_name": order.client_name,
            "fabric_or_yarn_spec": order.fabric_or_yarn_spec,
            "order_priority": order.priority,
            "planned_quantity": float(b.planned_quantity),
            "actual_quantity": float(b.actual_quantity),
            "defect_quantity": float(b.defect_quantity),
            "due_date": str(order.due_date),
            "batch_status": b.status,
        })

    return {
        "machine_code": machine.code,
        "active_batches_count": len(batch_list),
        "affected_batches": batch_list,
    }


def get_relevant_spare_parts(machine_id_or_code: Any) -> Dict[str, Any]:
    """
    Tool 7: Retrieves relevant spare parts, inventory stock levels, and replenishment status.
    """
    machine = _get_machine(machine_id_or_code)
    dept_code = machine.department.code if machine else ""

    # Look for spare parts matching machine department or general spare parts
    items = InventoryItem.objects.filter(
        category__in=[InventoryCategory.SPARE_PART, InventoryCategory.CONSUMABLE],
        is_active=True,
    )[:15]

    part_list = []
    for item in items:
        part_list.append({
            "item_code": item.item_code,
            "name": item.name,
            "category": item.category,
            "current_stock": float(item.current_stock),
            "reorder_point": float(item.reorder_point),
            "unit": item.unit,
            "unit_cost": float(item.unit_cost),
            "location_shelf": item.location_shelf,
            "is_low_stock": item.is_low_stock,
        })

    return {
        "machine_code": machine.code if machine else "GENERAL",
        "available_parts_count": len(part_list),
        "spare_parts": part_list,
    }


# Map of available tool names for reflection and security whitelist checks
AVAILABLE_TOOLS = {
    "get_machine_details": get_machine_details,
    "get_recent_machine_telemetry": get_recent_machine_telemetry,
    "get_machine_operating_limits": get_machine_operating_limits,
    "get_machine_maintenance_history": get_machine_maintenance_history,
    "get_active_machine_incidents": get_active_machine_incidents,
    "get_affected_production_orders": get_affected_production_orders,
    "get_relevant_spare_parts": get_relevant_spare_parts,
}
