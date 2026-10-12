from rest_framework import serializers
from .models import (
    MaintenanceTicket,
    MaintenanceActivity,
    MaintenanceHistory,
    WorkOrderTransition,
    WorkOrderAttachment,
)


class WorkOrderTransitionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkOrderTransition
        fields = "__all__"


class WorkOrderAttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkOrderAttachment
        fields = "__all__"


class MaintenanceActivitySerializer(serializers.ModelSerializer):
    class Meta:
        model = MaintenanceActivity
        fields = "__all__"


class MaintenanceTicketSerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)
    machine_name = serializers.CharField(source="machine.name", read_only=True)
    machine_type_name = serializers.CharField(source="machine.machine_type.name", read_only=True)
    department_name = serializers.CharField(source="machine.department.name", read_only=True)
    department_code = serializers.CharField(source="machine.department.code", read_only=True)
    activities = MaintenanceActivitySerializer(many=True, read_only=True)
    transitions = WorkOrderTransitionSerializer(many=True, read_only=True)
    attachments = WorkOrderAttachmentSerializer(many=True, read_only=True)

    class Meta:
        model = MaintenanceTicket
        fields = "__all__"


class MaintenanceHistorySerializer(serializers.ModelSerializer):
    machine_code = serializers.CharField(source="machine.code", read_only=True)

    class Meta:
        model = MaintenanceHistory
        fields = "__all__"
