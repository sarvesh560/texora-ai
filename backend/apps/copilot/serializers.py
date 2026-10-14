from rest_framework import serializers
from .models import CopilotSession, CopilotMessage


class CopilotMessageSerializer(serializers.ModelSerializer):
    class Meta:
        model = CopilotMessage
        fields = [
            "id",
            "role",
            "content",
            "facts",
            "estimates",
            "recommendations",
            "references",
            "evidence_records",
            "missing_evidence",
            "is_simulated",
            "simulation_disclosure",
            "provider",
            "model",
            "latency_ms",
            "reasoning_source",
            "created_at",
        ]
        read_only_fields = fields


class CopilotSessionSerializer(serializers.ModelSerializer):
    message_count = serializers.SerializerMethodField()
    latest_message = serializers.SerializerMethodField()

    class Meta:
        model = CopilotSession
        fields = [
            "id",
            "session_id",
            "title",
            "active_machine_code",
            "active_incident_code",
            "context_state",
            "message_count",
            "latest_message",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_message_count(self, obj):
        return obj.messages.count()

    def get_latest_message(self, obj):
        latest = obj.messages.last()
        if latest:
            return {
                "role": latest.role,
                "content": latest.content[:100] + ("..." if len(latest.content) > 100 else ""),
                "created_at": latest.created_at.isoformat(),
            }
        return None


class CopilotChatRequestSerializer(serializers.Serializer):
    message = serializers.CharField(max_length=2000, required=True, trim_whitespace=True)


class SuggestedQuestionSerializer(serializers.Serializer):
    id = serializers.CharField()
    category = serializers.CharField()
    prompt = serializers.CharField()
    description = serializers.CharField()
    target_entity = serializers.CharField(allow_blank=True, required=False)
