from rest_framework import serializers
from .models import InventoryItem, InventoryTransaction, SparePartRequirement


class InventoryTransactionSerializer(serializers.ModelSerializer):
    item_code = serializers.CharField(source="item.item_code", read_only=True)
    item_name = serializers.CharField(source="item.name", read_only=True)

    class Meta:
        model = InventoryTransaction
        fields = "__all__"


class SparePartRequirementSerializer(serializers.ModelSerializer):
    machine_type_name = serializers.CharField(source="machine_type.name", read_only=True)
    item_name = serializers.CharField(source="item.name", read_only=True)

    class Meta:
        model = SparePartRequirement
        fields = "__all__"


class InventoryItemSerializer(serializers.ModelSerializer):
    is_low_stock = serializers.ReadOnlyField()

    class Meta:
        model = InventoryItem
        fields = "__all__"
