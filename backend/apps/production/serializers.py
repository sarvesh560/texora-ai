from rest_framework import serializers
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
)


class MachineProductionAssignmentSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)
    department_code = serializers.CharField(source="department.code", read_only=True)

    class Meta:
        model = MachineProductionAssignment
        fields = "__all__"


class ProductionProgressSerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    department_code = serializers.CharField(source="department.code", read_only=True)

    class Meta:
        model = ProductionProgress
        fields = "__all__"


class ProductionBatchSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)
    progress_pct = serializers.ReadOnlyField()

    class Meta:
        model = ProductionBatch
        fields = "__all__"


class ProductionOrderSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(source="department.name", read_only=True)
    department_code = serializers.CharField(source="department.code", read_only=True)
    progress_pct = serializers.ReadOnlyField()
    remaining_quantity = serializers.ReadOnlyField()
    batches = ProductionBatchSerializer(many=True, read_only=True)
    machine_assignments = MachineProductionAssignmentSerializer(many=True, read_only=True)

    class Meta:
        model = ProductionOrder
        fields = "__all__"


class ProductionCapacityProfileSerializer(serializers.ModelSerializer):
    department_code = serializers.CharField(source="department.code", read_only=True)
    department_name = serializers.CharField(source="department.name", read_only=True)

    class Meta:
        model = ProductionCapacityProfile
        fields = "__all__"


class ProductionBottleneckSerializer(serializers.ModelSerializer):
    department_code = serializers.CharField(source="department.code", read_only=True)
    department_name = serializers.CharField(source="department.name", read_only=True)
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)

    class Meta:
        model = ProductionBottleneck
        fields = "__all__"


class ProductionImpactAssessmentSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)
    incident_code = serializers.CharField(source="incident.incident_code", read_only=True)

    class Meta:
        model = ProductionImpactAssessment
        fields = "__all__"


class ProductionScheduleSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)

    class Meta:
        model = ProductionSchedule
        fields = "__all__"


class ProductionOutputSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = ProductionOutput
        fields = "__all__"


class ProductionDelaySerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = ProductionDelay
        fields = "__all__"
