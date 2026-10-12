from rest_framework import serializers
from .models import ApprovalRequest


class ApprovalRequestSerializer(serializers.ModelSerializer):
    incident_summary = serializers.CharField(source="incident.summary", read_only=True)
    incident_code = serializers.CharField(source="incident.incident_code", read_only=True)

    class Meta:
        model = ApprovalRequest
        fields = "__all__"
