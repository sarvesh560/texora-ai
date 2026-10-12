from rest_framework import serializers
from .models import Factory, Department, ProductionLine


class ProductionLineSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(source="department.name", read_only=True)

    class Meta:
        model = ProductionLine
        fields = "__all__"


class DepartmentSerializer(serializers.ModelSerializer):
    factory_name = serializers.CharField(source="factory.name", read_only=True)
    production_lines = ProductionLineSerializer(many=True, read_only=True)

    class Meta:
        model = Department
        fields = "__all__"


class FactorySerializer(serializers.ModelSerializer):
    departments = DepartmentSerializer(many=True, read_only=True)

    class Meta:
        model = Factory
        fields = "__all__"
