from rest_framework import viewsets, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import InventoryItem, InventoryTransaction, SparePartRequirement
from .serializers import InventoryItemSerializer, InventoryTransactionSerializer, SparePartRequirementSerializer


class InventoryItemViewSet(viewsets.ModelViewSet):
    queryset = InventoryItem.objects.all()
    serializer_class = InventoryItemSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["category", "is_active"]
    search_fields = ["name", "item_code"]

    @action(detail=False, methods=["get"])
    def low_stock(self, request):
        items = [item for item in self.get_queryset() if item.is_low_stock]
        serializer = self.get_serializer(items, many=True)
        return Response(serializer.data)


class InventoryTransactionViewSet(viewsets.ModelViewSet):
    queryset = InventoryTransaction.objects.select_related("item").all()
    serializer_class = InventoryTransactionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["item", "transaction_type"]


class SparePartRequirementViewSet(viewsets.ModelViewSet):
    queryset = SparePartRequirement.objects.select_related("machine_type", "item").all()
    serializer_class = SparePartRequirementSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["machine_type", "item"]
