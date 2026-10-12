from rest_framework import serializers
from .models import FactoryIncident, AnomalyDetection, DetectionCheckpoint


class AnomalyDetectionSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)
    department_code = serializers.CharField(source="machine.department.code", read_only=True)

    class Meta:
        model = AnomalyDetection
        fields = "__all__"


class FactoryIncidentSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True, default=None)
    machine_name = serializers.CharField(source="machine.name", read_only=True, default=None)
    department_code = serializers.CharField(source="department.code", read_only=True)
    department_name = serializers.CharField(source="department.name", read_only=True)
    anomalies = AnomalyDetectionSerializer(many=True, read_only=True)

    class Meta:
        model = FactoryIncident
        fields = "__all__"


class DetectionCheckpointSerializer(serializers.ModelSerializer):
    is_thread_alive = serializers.SerializerMethodField()

    class Meta:
        model = DetectionCheckpoint
        fields = "__all__"

    def get_is_thread_alive(self, obj) -> bool:
        from .detector import AnomalyDetector
        return AnomalyDetector().is_active()
