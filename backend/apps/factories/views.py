from rest_framework import viewsets, permissions
from .models import Factory, Department, ProductionLine
from .serializers import FactorySerializer, DepartmentSerializer, ProductionLineSerializer


class FactoryViewSet(viewsets.ModelViewSet):
    queryset = Factory.objects.all()
    serializer_class = FactorySerializer
    permission_classes = [permissions.AllowAny]


class DepartmentViewSet(viewsets.ModelViewSet):
    queryset = Department.objects.all()
    serializer_class = DepartmentSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["factory", "department_type", "is_active"]


class ProductionLineViewSet(viewsets.ModelViewSet):
    queryset = ProductionLine.objects.all()
    serializer_class = ProductionLineSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["department", "is_active"]
