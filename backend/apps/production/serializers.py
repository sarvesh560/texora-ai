from rest_framework import serializers
from .models import ProductionOrder, ProductionBatch, ProductionSchedule, ProductionOutput, ProductionDelay


class ProductionBatchSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = ProductionBatch
        fields = "__all__"


class ProductionOrderSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(source="department.name", read_only=True)
    progress_pct = serializers.ReadOnlyField()
    batches = ProductionBatchSerializer(many=True, read_only=True)

    class Meta:
        model = ProductionOrder
        fields = "__all__"


class ProductionScheduleSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)

    class Meta:
        model = ProductionSchedule
        fields = "__all__"


class ProductionOutputSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductionOutput
        fields = "__all__"


class ProductionDelaySerializer(serializers.ModelSerializer):
    order_number = serializers.CharField(source="production_order.order_number", read_only=True)

    class Meta:
        model = ProductionDelay
        fields = "__all__"
