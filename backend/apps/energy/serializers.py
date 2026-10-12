from rest_framework import serializers
from .models import EnergyReading


class EnergyReadingSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(source="department.name", read_only=True)
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = EnergyReading
        fields = "__all__"
