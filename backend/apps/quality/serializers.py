from rest_framework import serializers
from .models import QualityInspection, QualityDefect


class QualityDefectSerializer(serializers.ModelSerializer):
    defect_type_display = serializers.CharField(source="get_defect_type_display", read_only=True)

    class Meta:
        model = QualityDefect
        fields = "__all__"


class QualityInspectionSerializer(serializers.ModelSerializer):
    batch_number = serializers.CharField(source="production_batch.batch_number", read_only=True)
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    defects = QualityDefectSerializer(many=True, read_only=True)

    class Meta:
        model = QualityInspection
        fields = "__all__"
