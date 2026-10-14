from datetime import date
from rest_framework import viewsets, permissions, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.decorators import action
from django.utils import timezone
from django.db.models import Sum, Avg, Count, Q

from .models import (
    ProductionOrder,
    ProductionBatch,
    ProductionSchedule,
    ProductionOutput,
    ProductionDelay,
    MachineProductionAssignment,
    ProductionProgress,
    ProductionCapacityProfile,
    ProductionBottleneck,
    ProductionImpactAssessment,
    OrderStatus,
    DelayRiskLevel,
)
from .serializers import (
    ProductionOrderSerializer,
    ProductionBatchSerializer,
    ProductionScheduleSerializer,
    ProductionOutputSerializer,
    ProductionDelaySerializer,
    MachineProductionAssignmentSerializer,
    ProductionProgressSerializer,
    ProductionCapacityProfileSerializer,
    ProductionBottleneckSerializer,
    ProductionImpactAssessmentSerializer,
)
from .capacity_engine import CapacityIntelligenceEngine
from .simulation_service import ProductionSimulationService


class ProductionOrderViewSet(viewsets.ModelViewSet):
    queryset = ProductionOrder.objects.select_related("department").prefetch_related("batches", "machine_assignments").all()
    serializer_class = ProductionOrderSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "status", "priority", "delay_risk_level"]
    search_fields = ["order_number", "client_name", "fabric_or_yarn_spec", "customer_po_number"]

    @action(detail=False, methods=["get"], url_path="at-risk")
    def at_risk_orders(self, request):
        """Returns orders that have HIGH or CRITICAL delay risk."""
        at_risk = self.get_queryset().filter(
            delay_risk_level__in=[DelayRiskLevel.HIGH, DelayRiskLevel.CRITICAL]
        )
        serializer = self.get_serializer(at_risk, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=["get"], url_path="timeline")
    def order_timeline(self, request, pk=None):
        """Returns detailed milestone schedule and routing progress for an order."""
        order = self.get_object()
        assignments = MachineProductionAssignment.objects.filter(production_order=order).select_related("machine", "department")
        progress = ProductionProgress.objects.filter(production_order=order).order_by("-recorded_at")[:10]

        return Response({
            "order_number": order.order_number,
            "client_name": order.client_name,
            "fabric_spec": order.fabric_or_yarn_spec,
            "routing_stages": order.routing_stages,
            "current_stage": order.current_stage,
            "target_quantity": float(order.target_quantity),
            "completed_quantity": float(order.completed_quantity),
            "progress_pct": order.progress_pct,
            "start_date": order.start_date.isoformat() if order.start_date else None,
            "due_date": order.due_date.isoformat() if order.due_date else None,
            "projected_completion_date": order.projected_completion_date.isoformat() if order.projected_completion_date else None,
            "estimated_remaining_hours": float(order.estimated_remaining_hours),
            "delay_risk_level": order.delay_risk_level,
            "delay_risk_score": float(order.delay_risk_score),
            "estimated_delay_hours": float(order.estimated_delay_hours),
            "assignments": MachineProductionAssignmentSerializer(assignments, many=True).data,
            "recent_progress": ProductionProgressSerializer(progress, many=True).data,
        })


class ProductionBatchViewSet(viewsets.ModelViewSet):
    queryset = ProductionBatch.objects.select_related("production_order", "machine", "department").all()
    serializer_class = ProductionBatchSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "machine", "department", "status"]


class MachineProductionAssignmentViewSet(viewsets.ModelViewSet):
    queryset = MachineProductionAssignment.objects.select_related("machine", "production_order", "production_batch", "department").all()
    serializer_class = MachineProductionAssignmentSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "production_order", "department", "status", "shift"]


class ProductionProgressViewSet(viewsets.ModelViewSet):
    queryset = ProductionProgress.objects.select_related("production_order", "production_batch", "machine", "department").all()
    serializer_class = ProductionProgressSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "machine", "department"]


class ProductionCapacityProfileViewSet(viewsets.ModelViewSet):
    queryset = ProductionCapacityProfile.objects.select_related("department").all()
    serializer_class = ProductionCapacityProfileSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "period_date", "bottleneck_severity"]


class ProductionBottleneckViewSet(viewsets.ModelViewSet):
    queryset = ProductionBottleneck.objects.select_related("department", "machine").all()
    serializer_class = ProductionBottleneckSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "machine", "severity", "bottleneck_type", "is_active"]


class ProductionImpactAssessmentViewSet(viewsets.ModelViewSet):
    queryset = ProductionImpactAssessment.objects.select_related("machine", "incident").all()
    serializer_class = ProductionImpactAssessmentSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine", "overall_delay_risk", "is_latest"]


class ProductionScheduleViewSet(viewsets.ModelViewSet):
    queryset = ProductionSchedule.objects.select_related("production_order", "machine", "production_line").all()
    serializer_class = ProductionScheduleSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "machine", "shift", "is_active"]


class ProductionOutputViewSet(viewsets.ModelViewSet):
    queryset = ProductionOutput.objects.select_related("production_batch", "machine").all()
    serializer_class = ProductionOutputSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_batch", "machine"]


class ProductionDelayViewSet(viewsets.ModelViewSet):
    queryset = ProductionDelay.objects.select_related("production_order", "production_batch", "machine").all()
    serializer_class = ProductionDelaySerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_order", "delay_reason"]


# -------------------------------------------------------------------------
# Phase 15 Dedicated Production Intelligence API Endpoints
# -------------------------------------------------------------------------

class ProductionOverviewAPIView(APIView):
    """
    High-level factory-wide production operations overview.
    Combines active orders, department capacities, bottlenecks, and delivery risks.
    """
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        now_date = timezone.now().date()

        # Recalculate deterministic capacities & risks if none or requested
        dept_capacities = CapacityIntelligenceEngine.calculate_department_capacities(target_date=now_date)
        timelines = CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
        bottlenecks = CapacityIntelligenceEngine.detect_and_sync_bottlenecks()

        # KPI Metrics
        total_orders = ProductionOrder.objects.count()
        active_orders = ProductionOrder.objects.filter(status=OrderStatus.IN_PROGRESS).count()
        paused_orders = ProductionOrder.objects.filter(status=OrderStatus.PAUSED).count()
        completed_orders = ProductionOrder.objects.filter(status=OrderStatus.COMPLETED).count()

        at_risk_orders_count = ProductionOrder.objects.filter(
            delay_risk_level__in=[DelayRiskLevel.HIGH, DelayRiskLevel.CRITICAL]
        ).count()

        total_target_units = float(ProductionOrder.objects.filter(
            status__in=[OrderStatus.IN_PROGRESS, OrderStatus.PLANNED, OrderStatus.PAUSED]
        ).aggregate(tot=Sum("target_quantity"))["tot"] or 0.0)

        total_completed_units = float(ProductionOrder.objects.filter(
            status__in=[OrderStatus.IN_PROGRESS, OrderStatus.PLANNED, OrderStatus.PAUSED]
        ).aggregate(tot=Sum("completed_quantity"))["tot"] or 0.0)

        # Average plant capacity utilization
        if dept_capacities:
            avg_utilization = round(sum(d["utilization_pct"] for d in dept_capacities) / len(dept_capacities), 1)
            total_nominal_capacity = sum(d["nominal_capacity_daily"] for d in dept_capacities)
            total_effective_capacity = sum(d["effective_capacity_daily"] for d in dept_capacities)
            total_downtime_loss = sum(d["downtime_loss_daily"] for d in dept_capacities)
        else:
            avg_utilization = 0.0
            total_nominal_capacity = 0.0
            total_effective_capacity = 0.0
            total_downtime_loss = 0.0

        active_bottlenecks_count = ProductionBottleneck.objects.filter(is_active=True).count()
        active_assignments_count = MachineProductionAssignment.objects.filter(status="RUNNING").count()

        latest_assessments = ProductionImpactAssessment.objects.filter(is_latest=True).select_related("machine")[:3]
        impact_data = ProductionImpactAssessmentSerializer(latest_assessments, many=True).data

        return Response({
            "timestamp": timezone.now().isoformat(),
            "metrics": {
                "total_orders": total_orders,
                "active_orders": active_orders,
                "paused_orders": paused_orders,
                "completed_orders": completed_orders,
                "at_risk_orders_count": at_risk_orders_count,
                "total_target_units": total_target_units,
                "total_completed_units": total_completed_units,
                "overall_progress_pct": round((total_completed_units / max(1.0, total_target_units)) * 100.0, 1),
                "plant_utilization_pct": avg_utilization,
                "nominal_daily_capacity_units": total_nominal_capacity,
                "effective_daily_capacity_units": total_effective_capacity,
                "daily_downtime_loss_units": total_downtime_loss,
                "active_bottlenecks_count": active_bottlenecks_count,
                "active_machine_assignments_count": active_assignments_count,
            },
            "department_capacities": dept_capacities,
            "active_bottlenecks": bottlenecks,
            "recent_impact_assessments": impact_data,
        })


class ProductionDepartmentCapacityAPIView(APIView):
    """Returns granular capacity utilization data by department."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        capacities = CapacityIntelligenceEngine.calculate_department_capacities()
        return Response(capacities)


class ProductionBottleneckAnalysisAPIView(APIView):
    """Returns detected production bottlenecks and root causes."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        bottlenecks = CapacityIntelligenceEngine.detect_and_sync_bottlenecks()
        return Response(bottlenecks)


class ProductionDelayRiskAPIView(APIView):
    """Returns delivery commitment delay predictions for all active orders."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        risks = CapacityIntelligenceEngine.calculate_order_timelines_and_risks()
        return Response(risks)


class ProductionTimelineAPIView(APIView):
    """Returns schedule timeline and routing milestones for Gantt representation."""
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        orders = ProductionOrder.objects.filter(
            status__in=[OrderStatus.IN_PROGRESS, OrderStatus.PLANNED, OrderStatus.PAUSED]
        ).select_related("department").prefetch_related("machine_assignments__machine")

        timeline = []
        for o in orders:
            assignments = o.machine_assignments.all()
            machine_codes = [a.machine.code for a in assignments if a.machine]
            timeline.append({
                "order_id": o.id,
                "order_number": o.order_number,
                "client_name": o.client_name,
                "department_code": o.department.code,
                "routing_stages": o.routing_stages,
                "current_stage": o.current_stage,
                "start_date": o.start_date.isoformat() if o.start_date else None,
                "due_date": o.due_date.isoformat() if o.due_date else None,
                "projected_completion_date": o.projected_completion_date.isoformat() if o.projected_completion_date else None,
                "progress_pct": o.progress_pct,
                "delay_risk_level": o.delay_risk_level,
                "estimated_delay_hours": float(o.estimated_delay_hours),
                "assigned_machines": machine_codes,
            })

        return Response(timeline)


class ProductionSimulateProgressionAPIView(APIView):
    """
    Controlled simulation control endpoint for advancing hours,
    inducing breakdown, recovering machines, or re-seeding baseline.
    """
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        sim_action = request.data.get("action", "advance")
        hours = float(request.data.get("hours", 2.0))
        machine_code = request.data.get("machine_code", "WEV-AJ-02")

        if sim_action == "seed":
            result = ProductionSimulationService.seed_production_baseline()
            return Response(result, status=status.HTTP_200_OK)

        elif sim_action == "advance":
            result = ProductionSimulationService.advance_production(hours=hours)
            return Response(result, status=status.HTTP_200_OK)

        elif sim_action == "breakdown":
            result = ProductionSimulationService.inject_machine_breakdown(
                machine_code=machine_code,
                estimated_downtime_hours=hours,
            )
            return Response(result, status=status.HTTP_200_OK)

        elif sim_action == "recover":
            result = ProductionSimulationService.recover_machine(machine_code=machine_code)
            return Response(result, status=status.HTTP_200_OK)

        else:
            return Response(
                {"error": f"Unknown action '{sim_action}'. Valid: seed, advance, breakdown, recover."},
                status=status.HTTP_400_BAD_REQUEST,
            )
