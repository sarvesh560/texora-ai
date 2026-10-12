from rest_framework import serializers
from .models import Machine, MachineType, MachineOperatingLimits, MachineTelemetry, MachineStateHistory


class MachineOperatingLimitsSerializer(serializers.ModelSerializer):
    class Meta:
        model = MachineOperatingLimits
        fields = "__all__"


class MachineTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = MachineType
        fields = "__all__"


class MachineTelemetrySerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = MachineTelemetry
        fields = "__all__"


class MachineStateHistorySerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = MachineStateHistory
        fields = "__all__"


class MachineSerializer(serializers.ModelSerializer):
    machine_type_name = serializers.CharField(source="machine_type.name", read_only=True)
    department_name = serializers.CharField(source="department.name", read_only=True)
    department_code = serializers.CharField(source="department.code", read_only=True)
    operating_limits = MachineOperatingLimitsSerializer(read_only=True)
    latest_telemetry = serializers.SerializerMethodField()

    class Meta:
        model = Machine
        fields = "__all__"

    def get_latest_telemetry(self, obj):
        latest = obj.telemetry_readings.first()
        if latest:
            return {
                "timestamp": latest.timestamp,
                "temperature_c": latest.temperature_c,
                "vibration_mms": latest.vibration_mms,
                "speed_rpm": latest.speed_rpm,
                "power_kw": latest.power_kw,
                "utilization_pct": latest.utilization_pct,
                "status_flag": latest.status_flag,
            }
        return None
