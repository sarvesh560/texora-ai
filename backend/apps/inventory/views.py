from rest_framework import viewsets, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django.db.models import Sum, F
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

    @action(detail=False, methods=["get"])
    def summary(self, request):
        items = list(self.get_queryset())
        total_items = len(items)
        low_stock_items = [i for i in items if i.is_low_stock]
        critical_shortage_items = [i for i in items if i.current_stock <= 0]

        total_value = sum(float(i.current_stock) * float(i.unit_cost) for i in items)

        # Category distribution
        category_map = {}
        for item in items:
            cat = item.category
            if cat not in category_map:
                category_map[cat] = {"category": cat, "count": 0, "value": 0.0}
            category_map[cat]["count"] += 1
            category_map[cat]["value"] += float(item.current_stock) * float(item.unit_cost)

        recent_txs = InventoryTransaction.objects.select_related("item").order_by("-timestamp")[:10]
        tx_data = InventoryTransactionSerializer(recent_txs, many=True).data

        recommendations = []
        for lsi in low_stock_items:
            deficit = float(lsi.reorder_point) - float(lsi.current_stock)
            recommendations.append({
                "item_code": lsi.item_code,
                "name": lsi.name,
                "urgency": "HIGH" if lsi.current_stock <= lsi.minimum_safety_stock else "MEDIUM",
                "recommended_order_quantity": max(deficit * 2, 5.0),
                "estimated_cost_inr": round(max(deficit * 2, 5.0) * float(lsi.unit_cost), 2),
                "reason": f"Current stock ({lsi.current_stock} {lsi.unit}) below reorder point ({lsi.reorder_point} {lsi.unit}).",
            })

        return Response({
            "total_items": total_items,
            "total_inventory_value_inr": round(total_value, 2),
            "low_stock_count": len(low_stock_items),
            "critical_shortage_count": len(critical_shortage_items),
            "category_breakdown": list(category_map.values()),
            "recent_transactions": tx_data,
            "ai_recommendations": recommendations,
        })


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
