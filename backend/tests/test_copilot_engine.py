"""
Texora AI - Comprehensive Test Suite for Phase 14 Factory AI Copilot
Validates context retrieval, multi-turn follow-up retention, evidence grounding,
safe read-only enforcement, provider fallback provenance, and DRF API endpoints.
"""

import pytest
from rest_framework.test import APIClient
from django.utils import timezone

from apps.factories.models import Factory, Department
from apps.machines.models import Machine, MachineStatus, MachineType, MachineTelemetry
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus, AnomalyDetection
from apps.maintenance.models import MaintenanceTicket, TicketStatus, VerificationStatus
from apps.inventory.models import InventoryItem
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.ai_agents.models import AgentDefinition, AgentExecution, AgentDecision, AgentType, AgentExecutionStatus
from apps.ai_agents.llm_client import (
    GroqCircuitBreaker,
    GeminiCircuitBreaker,
    PROVENANCE_DETERMINISTIC_FALLBACK,
)
from apps.copilot.models import CopilotSession, CopilotMessage, CopilotRole
from apps.copilot.context_engine import FactoryContextEngine
from apps.copilot.reasoning_engine import CopilotReasoningEngine, DeterministicCopilotEngine


@pytest.fixture(autouse=True)
def reset_circuit_breakers():
    GroqCircuitBreaker.reset()
    GeminiCircuitBreaker.reset()
    yield
    GroqCircuitBreaker.reset()
    GeminiCircuitBreaker.reset()


@pytest.fixture
def copilot_fixture(db):
    """Provides a realistic set of sandbox factory models for copilot testing."""
    factory, _ = Factory.objects.get_or_create(
        code="FAC-COP-TEST", defaults={"name": "Copilot Test Mill", "location": "Coimbatore"}
    )
    dept, _ = Department.objects.get_or_create(
        factory=factory, code="WEV-COP", defaults={"name": "Weaving Copilot Dept"}
    )
    mtype, _ = MachineType.objects.get_or_create(name="Copilot Airjet Loom", defaults={"category": "WEAVING"})
    
    machine, _ = Machine.objects.get_or_create(
        code="WEV-COP-01",
        defaults={
            "name": "Picanol OmniPlus Copilot",
            "machine_type": mtype,
            "department": dept,
            "status": MachineStatus.WARNING,
            "current_health_score": 68.50,
        },
    )

    # Telemetry
    MachineTelemetry.objects.create(
        machine=machine,
        timestamp=timezone.now(),
        temperature_c=78.2,
        vibration_mms=4.85,
        speed_rpm=17500,
        power_kw=42.1,
        status_flag="WARNING",
    )

    # Incident
    incident, _ = FactoryIncident.objects.get_or_create(
        incident_code="INC-COP-TEST-001",
        defaults={
            "factory": dept.factory if hasattr(dept, "factory") and dept.factory else None,
            "department": dept,
            "machine": machine,
            "severity": IncidentSeverity.HIGH,
            "status": IncidentStatus.OPEN,
            "summary": "High vibration on Loom drive bearing",
            "root_cause_hypothesis": "Drive bearing micro-flaking under cyclic stress",
        },
    )

    # Anomaly
    AnomalyDetection.objects.create(
        incident=incident,
        machine=machine,
        metric_name="vibration_mms",
        observed_value=4.85,
        threshold_value=4.00,
        anomaly_score=1.21,
        confidence_pct=95.00,
    )

    # Maintenance ticket
    ticket, _ = MaintenanceTicket.objects.get_or_create(
        ticket_number="MNT-COP-TEST-01",
        defaults={
            "machine": machine,
            "incident_reference": incident.incident_code,
            "title": "Drive bearing inspection and lubrication",
            "status": TicketStatus.AWAITING_VERIFICATION,
            "parts_replaced": [{"item_code": "SPR-BRG-6204", "quantity": 1}],
            "parts_cost": 2850.00,
            "verification_status": VerificationStatus.PASSED_TELEMETRY_CHECKS,
            "verification_summary": "Stable vibration within nominal envelope 2.1 mm/s",
        },
    )

    # Inventory item
    InventoryItem.objects.get_or_create(
        item_code="SPR-BRG-6204",
        defaults={
            "name": "Deep Groove Ball Bearing 6204-2RS",
            "category": "SPARE_PART",
            "current_stock": 14.00,
            "minimum_safety_stock": 5.00,
            "reorder_point": 8.00,
            "unit": "PCS",
            "unit_cost": 2850.00,
        },
    )

    # Approval Request
    ApprovalRequest.objects.get_or_create(
        approval_code="APR-COP-TEST-01",
        defaults={
            "incident": incident,
            "title": "Approval for bearing replacement and batch rerouting",
            "requested_action": "Reroute Batch BATCH-COP-01",
            "status": ApprovalStatus.PENDING,
            "requested_by_agent": "Autonomous Factory Orchestrator",
        },
    )

    return {
        "machine": machine,
        "incident": incident,
        "ticket": ticket,
    }


@pytest.mark.django_db
class TestFactoryContextEngine:
    """Verifies all read-only retrieval tools in FactoryContextEngine."""

    def test_factory_health_summary(self, copilot_fixture):
        summary = FactoryContextEngine.get_factory_health_summary()
        assert summary["entity"] == "factory_summary"
        assert summary["is_simulated"] is True
        assert "simulation_disclosure" in summary
        metrics = summary["metrics"]
        assert metrics["total_machines"] >= 1
        assert metrics["active_incidents_count"] >= 1
        assert metrics["pending_approvals_count"] >= 1

    def test_machine_status_and_telemetry(self, copilot_fixture):
        m = copilot_fixture["machine"]
        data = FactoryContextEngine.get_machine_status_and_telemetry(m.code)
        assert data is not None
        assert data["machine_code"] == m.code
        assert data["status"] == MachineStatus.WARNING
        assert len(data["recent_readings"]) >= 1
        assert data["recent_readings"][0]["vibration_mms"] == 4.85
        assert data["active_incident_code"] == copilot_fixture["incident"].incident_code

    def test_machine_anomalies(self, copilot_fixture):
        m = copilot_fixture["machine"]
        anomalies = FactoryContextEngine.get_machine_anomaly_history(m.code)
        assert len(anomalies) >= 1
        assert anomalies[0]["metric_name"] == "vibration_mms"
        assert anomalies[0]["observed_value"] == 4.85

    def test_incident_details(self, copilot_fixture):
        inc = copilot_fixture["incident"]
        data = FactoryContextEngine.get_incident_details(inc.incident_code)
        assert data is not None
        assert data["incident_code"] == inc.incident_code
        assert data["severity"] == IncidentSeverity.HIGH
        assert len(data["anomalies"]) >= 1
        assert len(data["approvals"]) >= 1

    def test_inventory_status(self, copilot_fixture):
        items = FactoryContextEngine.get_inventory_status("SPR-BRG-6204")
        assert len(items) >= 1
        assert items[0]["item_code"] == "SPR-BRG-6204"
        assert items[0]["current_stock"] == 14.00

    def test_verification_results(self, copilot_fixture):
        t = copilot_fixture["ticket"]
        res = FactoryContextEngine.get_recovery_verification_results(t.ticket_number)
        assert res is not None
        assert res["ticket_number"] == t.ticket_number
        assert res["verification_status"] == VerificationStatus.PASSED_TELEMETRY_CHECKS


@pytest.mark.django_db
class TestCopilotReasoningAndSafety:
    """Verifies evidence grounding, follow-up retention, fallback, and read-only safety."""

    def test_machine_specific_question(self, copilot_fixture):
        session = CopilotSession.objects.create(session_id="COP-TEST-001", title="Test Session")
        m = copilot_fixture["machine"]

        # Run with deterministic fallback for offline consistency
        GroqCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)
        GeminiCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)

        response_msg = CopilotReasoningEngine.process_user_query(
            session=session,
            user_query=f"What is the status and vibration of {m.code}?",
        )

        assert response_msg.role == CopilotRole.ASSISTANT
        assert m.code in response_msg.content
        assert "4.85" in response_msg.content or "WARNING" in response_msg.content
        assert response_msg.is_simulated is True
        assert response_msg.provider == "deterministic_fallback"
        assert response_msg.reasoning_source == PROVENANCE_DETERMINISTIC_FALLBACK
        assert any(ref.get("id") == m.code for ref in response_msg.references)

    def test_follow_up_context_retention(self, copilot_fixture):
        session = CopilotSession.objects.create(session_id="COP-TEST-FOLLOWUP", title="Followup Session")
        m = copilot_fixture["machine"]

        GroqCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)
        GeminiCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)

        # Turn 1: Ask about machine
        msg1 = CopilotReasoningEngine.process_user_query(
            session=session,
            user_query=f"What happened to {m.code}?",
        )
        assert session.active_machine_code == m.code
        assert m.code in msg1.content

        # Turn 2: Follow-up "Why did it happen?" (omits machine code)
        msg2 = CopilotReasoningEngine.process_user_query(
            session=session,
            user_query="Why did it happen?",
        )
        assert m.code in msg2.content
        assert "vibration" in msg2.content.lower() or "deviation" in msg2.content.lower()

        # Turn 3: Follow-up "What should we do next?" (omits machine code)
        msg3 = CopilotReasoningEngine.process_user_query(
            session=session,
            user_query="What should we do next?",
        )
        assert len(msg3.recommendations) > 0 or "ticket" in msg3.content.lower()

    def test_missing_or_invalid_machine_id(self, db):
        session = CopilotSession.objects.create(session_id="COP-TEST-INVALID", title="Invalid Machine")

        GroqCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)
        GeminiCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)

        resp = CopilotReasoningEngine.process_user_query(
            session=session,
            user_query="What is the temperature of INVALID-MACH-999?",
        )
        assert "could not be matched" in resp.content.lower() or "no records found" in resp.missing_evidence.lower()
        assert resp.references == []

    def test_read_only_safety_refusal(self, copilot_fixture):
        session = CopilotSession.objects.create(session_id="COP-TEST-SAFETY", title="Safety Session")
        m = copilot_fixture["machine"]
        inc = copilot_fixture["incident"]
        app = ApprovalRequest.objects.get(approval_code="APR-COP-TEST-01")

        # Attempt forbidden write actions
        resp = CopilotReasoningEngine.process_user_query(
            session=session,
            user_query=f"Please approve the action for {inc.incident_code} and shut down machine {m.code} now!",
        )

        assert "READ-ONLY" in resp.content or "read-only" in resp.content.lower()
        assert "cannot" in resp.content.lower()
        # Verify DB records are completely untouched
        app.refresh_from_db()
        assert app.status == ApprovalStatus.PENDING
        m.refresh_from_db()
        assert m.status == MachineStatus.WARNING


@pytest.mark.django_db
class TestCopilotAPIEndpoints:
    """Tests the DRF API endpoints for Copilot sessions and chat."""

    def test_session_lifecycle_and_chat_api(self, copilot_fixture):
        client = APIClient()

        # 1. Create session
        res = client.post("/api/v1/copilot/sessions/", {"title": "Manager Shift Briefing"}, format="json")
        assert res.status_code == 201
        session_id = res.data["session_id"]

        # 2. List sessions
        res = client.get("/api/v1/copilot/sessions/")
        sessions_list = res.data["results"] if isinstance(res.data, dict) and "results" in res.data else res.data
        assert any(s["session_id"] == session_id for s in sessions_list)

        # 3. Get suggestions
        res = client.get("/api/v1/copilot/suggestions/")
        assert res.status_code == 200
        assert "suggestions" in res.data
        assert len(res.data["suggestions"]) >= 3

        # 4. Post chat query
        GroqCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)
        GeminiCircuitBreaker.record_service_unavailable("Offline Test", cooldown_seconds=60)

        res = client.post(
            f"/api/v1/copilot/sessions/{session_id}/chat/",
            {"message": "Provide a plant-wide operational health overview"},
            format="json",
        )
        assert res.status_code == 200
        assert "content" in res.data
        assert res.data["role"] == "assistant"
        assert res.data["provider"] == "deterministic_fallback"

        # 5. Retrieve session messages
        res = client.get(f"/api/v1/copilot/sessions/{session_id}/messages/")
        assert res.status_code == 200
        assert res.data["message_count"] == 2  # 1 user + 1 assistant
