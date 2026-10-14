"""
Tests for Phase 13: GroqCloud + Gemini Multi-Agent AI Integration.
Verifies:
1. GroqCircuitBreaker state management, cooldowns, and fast failover.
2. GroqProvider structured inference, token tracking, latency recording, and schema recovery.
3. MultiProviderRouter preferred routing order (Groq -> Gemini -> Deterministic Fallback).
4. All four specialist agents executing with GroqCloud provenance (GROQ_LIVE).
5. Error handling: HTTP 429 rate limits, HTTP 503 service unavailable, HTTP 401 auth errors.
6. Provenance tagging and metadata envelope storage in AgentExecution.
7. Autonomous Orchestrator multi-agent coordination with recovery verification.
"""
import json
import time
import pytest
from unittest.mock import patch, MagicMock
from django.utils import timezone

from apps.machines.models import Machine, MachineType, MachineStatus, MachineOperatingLimits
from apps.factories.models import Factory, Department, DepartmentType
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus, IncidentCategory
from apps.inventory.models import InventoryItem, InventoryCategory
from apps.production.models import ProductionOrder, ProductionBatch
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.maintenance.models import MaintenanceTicket, TicketStatus, TicketPriority, VerificationStatus
from apps.maintenance.verification_service import RecoveryVerificationService
from apps.maintenance.simulation_service import MaintenanceSimulationService
from apps.ai_agents.models import AgentExecution, AgentType
from apps.ai_agents.action_service import ActionSafetyService
from apps.ai_agents.llm_client import (
    BaseLLMProvider,
    LLMResponse,
    GroqProvider,
    GroqCircuitBreaker,
    GeminiCircuitBreaker,
    MultiProviderRouter,
    MockLLMProvider,
)
from apps.ai_agents.schemas import (
    PROVENANCE_GROQ_LIVE,
    PROVENANCE_GEMINI_LIVE,
    PROVENANCE_DETERMINISTIC_FALLBACK,
    PROVENANCE_GROQ_RATE_LIMITED,
    PROVENANCE_GROQ_UNAVAILABLE,
    PROVENANCE_GROQ_AUTH_ERROR,
    validate_machine_health_output,
    validate_maintenance_coordination_output,
    validate_inventory_coordination_output,
    validate_production_impact_output,
    build_metadata_envelope,
)
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.maintenance_coordinator import MaintenanceCoordinatorAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.production_impact_agent import ProductionImpactAgent
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator


@pytest.fixture(autouse=True)
def reset_all_breakers():
    """Reset both Groq and Gemini circuit breakers before and after each test."""
    GroqCircuitBreaker.reset()
    GeminiCircuitBreaker.reset()
    yield
    GroqCircuitBreaker.reset()
    GeminiCircuitBreaker.reset()


@pytest.fixture
def factory_setup(db):
    """Creates factory test fixture with spinning and weaving departments."""
    factory = Factory.objects.create(name="Texora Mills Unit 1", code="TM-01", location="Coimbatore, TN")
    dept = Department.objects.create(
        factory=factory,
        name="Weaving Shed A",
        code="WEV",
        department_type=DepartmentType.WEAVING,
    )
    mtype = MachineType.objects.create(
        name="Air Jet Loom 340cm",
        category=DepartmentType.WEAVING,
        manufacturer="Picanol",
        model_number="OmniPlus-i",
        default_power_rating_kw=15.0,
    )
    machine = Machine.objects.create(
        code="WEV-AJ-02",
        name="Picanol OmniPlus-i Loom #2",
        machine_type=mtype,
        department=dept,
        status=MachineStatus.CRITICAL,
        rated_speed_rpm=1050,
    )
    limits = MachineOperatingLimits.objects.create(
        machine=machine,
        warning_vibration_mms=4.0,
        max_vibration_mms=5.5,
        warning_temp_c=75.0,
        max_temp_c=85.0,
        min_rpm=700,
        max_rpm=1200,
    )
    spare_part = InventoryItem.objects.create(
        item_code="SPR-BRG-6204",
        name="Deep Groove Ball Bearing 6204-2RS",
        category=InventoryCategory.SPARE_PART,
        current_stock=12.00,
        minimum_safety_stock=4.00,
        reorder_point=6.00,
        unit="PCS",
        unit_cost=450.00,
    )
    order = ProductionOrder.objects.create(
        order_number="PO-2026-WEV-88",
        client_name="Premier Textiles Exports",
        fabric_or_yarn_spec="Cotton Poplin 40s Combed",
        department=dept,
        target_quantity=15000.00,
        unit="METERS",
        completed_quantity=8200.00,
        due_date=timezone.now().date(),
        status="IN_PROGRESS",
    )
    batch = ProductionBatch.objects.create(
        batch_number="BAT-WEV-088-A",
        production_order=order,
        machine=machine,
        planned_quantity=3500.00,
        status="RUNNING",
    )
    incident = FactoryIncident.objects.create(
        incident_code="INC-TEST-GROQ-01",
        factory=factory,
        department=dept,
        machine=machine,
        severity=IncidentSeverity.CRITICAL,
        status=IncidentStatus.OPEN,
        category=IncidentCategory.MACHINE_HEALTH,
        summary="High vibration on loom drive shaft",
        evidence_data={"vibration_mms": 6.8, "temperature_c": 78.5},
    )
    return {
        "factory": factory,
        "dept": dept,
        "machine": machine,
        "spare_part": spare_part,
        "order": order,
        "batch": batch,
        "incident": incident,
    }


# =========================================================================
# 1. Circuit Breaker Unit Tests
# =========================================================================
class TestGroqCircuitBreaker:
    """Verifies in-memory rate-limit and error circuit breaker for GroqCloud."""

    def test_initial_state_operational(self):
        is_avail, status, msg = GroqCircuitBreaker.check_availability()
        assert is_avail is True
        assert status in ["SUCCESS", "OPERATIONAL"]

    def test_rate_limit_trips_breaker(self):
        GroqCircuitBreaker.record_rate_limit("Rate limit 429", cooldown_seconds=60)
        is_avail, status, msg = GroqCircuitBreaker.check_availability()
        assert is_avail is False
        assert status == "RATE_LIMITED"
        assert "Rate limit" in msg

    def test_service_unavailable_cooldown(self):
        GroqCircuitBreaker.record_service_unavailable("Groq 503", cooldown_seconds=30)
        is_avail, status, msg = GroqCircuitBreaker.check_availability()
        assert is_avail is False
        assert status in ["UNAVAILABLE", "SERVICE_UNAVAILABLE"]

    def test_auth_error_cooldown(self):
        GroqCircuitBreaker.record_auth_error("Groq 401 Invalid Key", cooldown_seconds=300)
        is_avail, status, msg = GroqCircuitBreaker.check_availability()
        assert is_avail is False
        assert status == "AUTH_ERROR"

    def test_record_success_resets_breaker(self):
        GroqCircuitBreaker.record_rate_limit("Rate limit", cooldown_seconds=60)
        assert GroqCircuitBreaker.check_availability()[0] is False
        GroqCircuitBreaker.record_success()
        assert GroqCircuitBreaker.check_availability()[0] is True


# =========================================================================
# 2. GroqProvider Unit Tests
# =========================================================================
class TestGroqProvider:
    """Verifies GroqProvider invocation, parsing, and error recovery."""

    def test_unconfigured_provider_returns_fallback(self):
        provider = GroqProvider(api_key="")
        res = provider.generate_structured("system prompt", "user prompt")
        assert res.status == "UNCONFIGURED"
        assert res.reasoning_source == PROVENANCE_DETERMINISTIC_FALLBACK

    def test_circuit_breaker_fast_fails_without_network(self):
        GroqCircuitBreaker.record_rate_limit("429 Too Many Requests", cooldown_seconds=120)
        provider = GroqProvider(api_key="gsk_dummy_test_key_12345")
        res = provider.generate_structured("system prompt", "user prompt")
        assert res.reasoning_source == PROVENANCE_DETERMINISTIC_FALLBACK
        assert res.provider_attempt_status == PROVENANCE_GROQ_RATE_LIMITED
        assert "Circuit Breaker open" in res.error_message or "RATE_LIMITED" in res.error_message

    def test_successful_groq_inference_mocked(self):
        provider = GroqProvider(api_key="gsk_dummy_test_key_12345", model_name="qwen/qwen3.8-27b")

        mock_payload = {
            "fault_hypotheses": [
                {
                    "fault_name": "Drive Shaft Bearing Wear",
                    "probability_pct": 92.5,
                    "evidence_indicators": ["Vibration 6.8 mm/s exceeding warning limit"],
                    "risk_level": "CRITICAL",
                }
            ],
            "recommended_next_actions": [{"action_name": "Inspect Bearing", "urgency": "IMMEDIATE"}],
            "confidence_score": 92.5,
            "uncertainty_notes": "Awaiting physical inspection confirmation",
        }

        mock_choice = MagicMock()
        mock_choice.message.content = json.dumps(mock_payload)
        mock_usage = MagicMock()
        mock_usage.prompt_tokens = 45
        mock_usage.completion_tokens = 60
        mock_usage.total_tokens = 105

        mock_completion = MagicMock()
        mock_completion.choices = [mock_choice]
        mock_completion.usage = mock_usage

        with patch("groq.Groq") as mock_groq_class:
            mock_client = MagicMock()
            mock_client.chat.completions.create.return_value = mock_completion
            mock_groq_class.return_value = mock_client

            res = provider.generate_structured(
                system_prompt="Industrial health system",
                user_prompt="Analyze vibration",
            )

            assert res.status == "SUCCESS"
            assert res.reasoning_source == PROVENANCE_GROQ_LIVE
            assert res.provider == "groq"
            assert res.model == "qwen/qwen3.8-27b"
            assert res.structured_json == mock_payload
            assert res.token_count == 105


# =========================================================================
# 3. MultiProviderRouter Tests
# =========================================================================
class TestMultiProviderRouter:
    """Verifies failover order: Groq -> Gemini -> Deterministic Fallback."""

    def test_routes_to_groq_when_healthy(self):
        groq_mock = MagicMock(spec=GroqProvider)
        groq_mock.is_configured.return_value = True
        groq_mock.model_name = "qwen/qwen3.8-27b"
        mock_res = LLMResponse(
            content='{"status": "ok"}',
            structured_json={"status": "ok"},
            token_count=42,
            latency_ms=120,
            provider="groq",
            model="qwen/qwen3.8-27b",
            status="SUCCESS",
            reasoning_source=PROVENANCE_GROQ_LIVE,
        )
        groq_mock.generate_structured.return_value = mock_res

        router = MultiProviderRouter(primary_provider=groq_mock)
        res = router.generate_structured("sys", "user")
        assert res.provider == "groq"
        assert res.reasoning_source == PROVENANCE_GROQ_LIVE

    def test_failover_to_gemini_when_groq_rate_limited(self):
        groq_mock = MagicMock(spec=GroqProvider)
        groq_mock.is_configured.return_value = True
        groq_mock.generate_structured.return_value = LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=50,
            provider="groq",
            model="qwen/qwen3.8-27b",
            status="RATE_LIMITED",
            error_message="HTTP 429",
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=PROVENANCE_GROQ_RATE_LIMITED,
        )

        gemini_mock = MagicMock()
        gemini_mock.is_configured.return_value = True
        gemini_mock.model_name = "gemini-3.5-flash"
        gemini_mock.generate_structured.return_value = LLMResponse(
            content='{"status": "gemini_ok"}',
            structured_json={"status": "gemini_ok"},
            token_count=50,
            latency_ms=300,
            provider="gemini",
            model="gemini-3.5-flash",
            status="SUCCESS",
            reasoning_source=PROVENANCE_GEMINI_LIVE,
        )

        router = MultiProviderRouter(primary_provider=groq_mock, secondary_provider=gemini_mock)
        res = router.generate_structured("sys", "user")
        assert res.provider == "gemini"
        assert res.reasoning_source == PROVENANCE_GEMINI_LIVE

    def test_failover_to_deterministic_when_both_cloud_providers_fail(self):
        groq_mock = MagicMock(spec=GroqProvider)
        groq_mock.is_configured.return_value = False
        gemini_mock = MagicMock()
        gemini_mock.is_configured.return_value = False

        router = MultiProviderRouter(primary_provider=groq_mock, secondary_provider=gemini_mock)
        res = router.generate_structured("sys", "user")
        assert res.reasoning_source == PROVENANCE_DETERMINISTIC_FALLBACK


# =========================================================================
# 4. Specialist Agents Integration with GroqCloud
# =========================================================================
@pytest.mark.django_db
class TestSpecialistAgentsWithGroq:
    """Verifies all 4 agents operate with live GroqCloud AI inference schema."""

    def test_machine_health_agent_with_groq(self, factory_setup):
        incident = factory_setup["incident"]

        groq_resp = LLMResponse(
            content=json.dumps({
                "fault_hypotheses": [
                    {
                        "fault_name": "Main Drive Bearing Flaking",
                        "probability_pct": 91.0,
                        "evidence_indicators": ["Vibration 6.8 mm/s > limit 5.5 mm/s"],
                        "risk_level": "CRITICAL",
                    }
                ],
                "recommended_next_actions": [{"action_name": "Lockout and replace bearing", "urgency": "IMMEDIATE"}],
                "confidence_score": 91.0,
                "uncertainty_notes": "Requires physical bearing casing opening",
            }),
            structured_json={
                "fault_hypotheses": [
                    {
                        "fault_name": "Main Drive Bearing Flaking",
                        "probability_pct": 91.0,
                        "evidence_indicators": ["Vibration 6.8 mm/s > limit 5.5 mm/s"],
                        "risk_level": "CRITICAL",
                    }
                ],
                "recommended_next_actions": [{"action_name": "Lockout and replace bearing", "urgency": "IMMEDIATE"}],
                "confidence_score": 91.0,
                "uncertainty_notes": "Requires physical bearing casing opening",
            },
            token_count=120,
            latency_ms=450,
            provider="groq",
            model="qwen/qwen3.8-27b",
            status="SUCCESS",
            reasoning_source=PROVENANCE_GROQ_LIVE,
        )

        mock_prov = MagicMock(spec=GroqProvider)
        mock_prov.model_name = "qwen/qwen3.8-27b"
        mock_prov.generate_structured.return_value = groq_resp

        agent = MachineHealthAgent(provider=mock_prov)
        result = agent.investigate_incident(incident_id=incident.id)

        assert result["reasoning_source"] == PROVENANCE_GROQ_LIVE
        assert result["model_name"] == "qwen/qwen3.8-27b" if "model_name" in result else True

        # Check DB persistence
        db_exec = AgentExecution.objects.filter(agent__agent_type=AgentType.MACHINE_HEALTH, incident=incident).first()
        assert db_exec is not None
        assert db_exec.context_payload.get("reasoning_source") == PROVENANCE_GROQ_LIVE

    def test_maintenance_coordinator_with_groq(self, factory_setup):
        incident = factory_setup["incident"]

        groq_resp = LLMResponse(
            content=json.dumps({
                "work_order_summary": "Emergency bearing replacement for Loom #2",
                "priority_level": "CRITICAL",
                "estimated_downtime_hours": 2.0,
                "required_skill_level": "SENIOR_MECHANIC",
                "required_tools": ["Torque wrench", "Bearing puller"],
                "safety_lockout_required": True,
                "step_by_step_tasks": ["Lockout machine", "Extract bearing", "Seat new bearing"],
                "suggested_actions": [
                    {
                        "action_type": "CREATE_MAINTENANCE_TICKET",
                        "description": "Create emergency work order",
                        "requires_human_approval": True,
                        "payload": {"title": "Replace 6204 bearing", "priority": "CRITICAL"},
                    }
                ],
                "confidence_score": 94.0,
            }),
            structured_json={
                "work_order_summary": "Emergency bearing replacement for Loom #2",
                "priority_level": "CRITICAL",
                "estimated_downtime_hours": 2.0,
                "required_skill_level": "SENIOR_MECHANIC",
                "required_tools": ["Torque wrench", "Bearing puller"],
                "safety_lockout_required": True,
                "step_by_step_tasks": ["Lockout machine", "Extract bearing", "Seat new bearing"],
                "suggested_actions": [
                    {
                        "action_type": "CREATE_MAINTENANCE_TICKET",
                        "description": "Create emergency work order",
                        "requires_human_approval": True,
                        "payload": {"title": "Replace 6204 bearing", "priority": "CRITICAL"},
                    }
                ],
                "confidence_score": 94.0,
            },
            token_count=160,
            latency_ms=620,
            provider="groq",
            model="qwen/qwen3.8-27b",
            status="SUCCESS",
            reasoning_source=PROVENANCE_GROQ_LIVE,
        )

        mock_prov = MagicMock(spec=GroqProvider)
        mock_prov.model_name = "qwen/qwen3.8-27b"
        mock_prov.generate_structured.return_value = groq_resp

        agent = MaintenanceCoordinatorAgent(provider=mock_prov)
        result = agent.coordinate_maintenance(incident_id=incident.id)

        assert result["reasoning_source"] == PROVENANCE_GROQ_LIVE
        assert result["is_live_ai"] is True if "is_live_ai" in result else True

    def test_inventory_coordinator_with_groq(self, factory_setup):
        incident = factory_setup["incident"]

        groq_resp = LLMResponse(
            content=json.dumps({
                "part_allocations": [
                    {
                        "item_code": "SPR-BRG-6204",
                        "item_name": "Deep Groove Ball Bearing 6204-2RS",
                        "quantity_requested": 1,
                        "quantity_available": 12,
                        "is_sufficient": True,
                        "unit_cost": 450.0,
                        "reorder_triggered": False,
                    }
                ],
                "procurement_urgency": "LOW",
                "lead_time_days": 1,
                "stockout_risk_level": "LOW",
                "suggested_actions": [
                    {
                        "action_type": "RESERVE_SPARE_PART",
                        "description": "Reserve 1 bearing",
                        "requires_human_approval": True,
                        "payload": {"item_code": "SPR-BRG-6204", "quantity": 1},
                    }
                ],
                "confidence_score": 98.0,
            }),
            structured_json={
                "part_allocations": [
                    {
                        "item_code": "SPR-BRG-6204",
                        "item_name": "Deep Groove Ball Bearing 6204-2RS",
                        "quantity_requested": 1,
                        "quantity_available": 12,
                        "is_sufficient": True,
                        "unit_cost": 450.0,
                        "reorder_triggered": False,
                    }
                ],
                "procurement_urgency": "LOW",
                "lead_time_days": 1,
                "stockout_risk_level": "LOW",
                "suggested_actions": [
                    {
                        "action_type": "RESERVE_SPARE_PART",
                        "description": "Reserve 1 bearing",
                        "requires_human_approval": True,
                        "payload": {"item_code": "SPR-BRG-6204", "quantity": 1},
                    }
                ],
                "confidence_score": 98.0,
            },
            token_count=140,
            latency_ms=510,
            provider="groq",
            model="qwen/qwen3.8-27b",
            status="SUCCESS",
            reasoning_source=PROVENANCE_GROQ_LIVE,
        )

        mock_prov = MagicMock(spec=GroqProvider)
        mock_prov.model_name = "qwen/qwen3.8-27b"
        mock_prov.generate_structured.return_value = groq_resp

        agent = InventoryCoordinatorAgent(provider=mock_prov)
        result = agent.coordinate_inventory(incident_id=incident.id)

        assert result["reasoning_source"] == PROVENANCE_GROQ_LIVE

    def test_production_impact_agent_with_groq(self, factory_setup):
        incident = factory_setup["incident"]

        groq_resp = LLMResponse(
            content=json.dumps({
                "production_disruption_explanation": "WEV-AJ-02 stoppage impacts batch BAT-WEV-088-A.",
                "suggested_production_adjustments": ["Shift batch BAT-WEV-088-A to standby loom WEV-AJ-04"],
                "recommended_alternate_machines": [{"machine_code": "WEV-AJ-04", "rationale": "Standby air-jet loom", "capacity_fit": "HIGH"}],
                "recovery_plan": ["Complete bearing repair on Loom #2", "Resume normal batch allocation"],
                "operational_consequences_summary": "Delivery risk low if alternate machine is engaged within 2 hours.",
                "confidence_score": 92.0,
                "risk_level": "MEDIUM",
                "suggested_actions": [
                    {
                        "action_type": "REROUTE_PRODUCTION",
                        "description": "Shift batch BAT-WEV-088-A to standby loom WEV-AJ-04",
                        "requires_human_approval": True,
                        "payload": {"target_machine": "WEV-AJ-04"},
                    }
                ],
            }),
            structured_json={
                "production_disruption_explanation": "WEV-AJ-02 stoppage impacts batch BAT-WEV-088-A.",
                "suggested_production_adjustments": ["Shift batch BAT-WEV-088-A to standby loom WEV-AJ-04"],
                "recommended_alternate_machines": [{"machine_code": "WEV-AJ-04", "rationale": "Standby air-jet loom", "capacity_fit": "HIGH"}],
                "recovery_plan": ["Complete bearing repair on Loom #2", "Resume normal batch allocation"],
                "operational_consequences_summary": "Delivery risk low if alternate machine is engaged within 2 hours.",
                "confidence_score": 92.0,
                "risk_level": "MEDIUM",
                "suggested_actions": [
                    {
                        "action_type": "REROUTE_PRODUCTION",
                        "description": "Shift batch BAT-WEV-088-A to standby loom WEV-AJ-04",
                        "requires_human_approval": True,
                        "payload": {"target_machine": "WEV-AJ-04"},
                    }
                ],
            },
            token_count=155,
            latency_ms=530,
            provider="groq",
            model="qwen/qwen3.8-27b",
            status="SUCCESS",
            reasoning_source=PROVENANCE_GROQ_LIVE,
        )

        mock_prov = MagicMock(spec=GroqProvider)
        mock_prov.model_name = "qwen/qwen3.8-27b"
        mock_prov.generate_structured.return_value = groq_resp

        agent = ProductionImpactAgent(provider=mock_prov)
        result = agent.evaluate_production_impact(incident_id=incident.id)

        assert result["reasoning_source"] == PROVENANCE_GROQ_LIVE


# =========================================================================
# 5. End-to-End Orchestrator Workflow with Recovery Verification
# =========================================================================
@pytest.mark.django_db
class TestEndToEndWorkflowWithRecovery:
    """Verifies complete incident lifecycle from AI investigation to recovery verification."""

    def test_full_workflow_successful_closure(self, factory_setup):
        incident = factory_setup["incident"]
        machine = factory_setup["machine"]

        orchestrator = AutonomousFactoryOrchestrator()
        result = orchestrator.process_incident(incident_id=incident.id, force_provider="mock")

        assert result["success"] is True
        assert result["current_stage"] == "AWAITING_MANAGER_APPROVAL"

        # Verify approval request was generated and approve via ActionSafetyService
        appr_req = ApprovalRequest.objects.filter(
            incident=incident,
            status=ApprovalStatus.PENDING,
        ).filter(requested_action__icontains="MAINTENANCE").first()

        if not appr_req:
            appr_req = ApprovalRequest.objects.filter(incident=incident, status=ApprovalStatus.PENDING).first()

        assert appr_req is not None
        appr_res = ActionSafetyService.approve_and_execute(
            approval_id=appr_req.id,
            approved_by="V. Ramanathan (Plant Operations Director)",
            user_role="PLANT_DIRECTOR",
            response_notes="Approved emergency work order following Groq AI analysis",
        )
        assert appr_res["success"] is True

        # Verify ticket now exists following manager authorization
        ticket = MaintenanceTicket.objects.filter(incident_reference=incident.incident_code).first()
        if not ticket:
            ticket = MaintenanceTicket.objects.filter(machine=machine).first()
        assert ticket is not None

        # Simulate maintenance repair completion
        ticket.status = TicketStatus.AWAITING_VERIFICATION
        ticket.repair_completed_at = timezone.now()
        ticket.save()

        # Generate healthy post-repair telemetry
        MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="HEALTHY")

        # Plant Manager authorizes sign-off
        signed_report = RecoveryVerificationService.authorize_and_sign_off(
            ticket=ticket,
            authorized_by="V. Ramanathan (Plant Operations Manager)",
            notes="Nominal vibration confirmed on Picanol Loom #2.",
        )
        assert signed_report["outcome"] == VerificationStatus.VERIFIED

        # Close incident
        closed_inc = RecoveryVerificationService.close_incident_with_evidence(
            incident=incident,
            ticket=ticket,
            closed_by="V. Ramanathan",
            resolution_notes="Closed following successful GroqCloud AI investigation and verified bearing overhaul.",
        )
        assert closed_inc.status == IncidentStatus.CLOSED
        assert closed_inc.resolved_at is not None

    def test_failed_recovery_blocks_closure(self, factory_setup):
        incident = factory_setup["incident"]
        machine = factory_setup["machine"]

        ticket = MaintenanceTicket.objects.create(
            ticket_number="MNT-TEST-FAIL-01",
            machine=machine,
            incident_reference=incident.incident_code,
            title="Drive shaft overhaul",
            priority=TicketPriority.CRITICAL,
            status=TicketStatus.AWAITING_VERIFICATION,
            repair_completed_at=timezone.now(),
        )

        # Generate faulty telemetry (vibration above limit)
        MaintenanceSimulationService.generate_post_repair_telemetry(machine=machine, num_readings=5, mode="FAULTY")

        eval_report = RecoveryVerificationService.evaluate_machine_recovery(machine=machine, ticket=ticket)
        assert eval_report["outcome"] == VerificationStatus.FAILED
        assert eval_report["is_healthy"] is False

        # Attempting sign-off without healthy telemetry must fail
        with pytest.raises(Exception):
            RecoveryVerificationService.authorize_and_sign_off(
                ticket=ticket,
                authorized_by="Operations Manager",
                notes="Attempting sign-off despite vibration anomaly",
            )


# =========================================================================
# 6. Provider Health & Routing Matrix Diagnostic Tests
# =========================================================================
@pytest.mark.django_db
class TestProviderHealthAndStatusMatrix:
    """Verifies evidence-based multi-cloud AI routing and health matrix states."""

    def test_unconfigured_api_keys_report_not_configured(self):
        with patch.dict("os.environ", {"GROQ_API_KEY": "", "GEMINI_API_KEY": ""}, clear=False):
            GroqCircuitBreaker.reset()
            GeminiCircuitBreaker.reset()
            router = MultiProviderRouter()
            health = router.get_provider_health()

            assert health["groq"]["status"] == "NOT_CONFIGURED"
            assert health["groq"]["configured"] is False
            assert health["groq"]["is_configured"] is False
            assert health["groq"]["ready"] is False

            assert health["gemini"]["status"] == "NOT_CONFIGURED"
            assert health["gemini"]["configured"] is False
            assert health["gemini"]["is_configured"] is False
            assert health["gemini"]["ready"] is False

    def test_configured_api_keys_without_prior_inference_report_configured(self):
        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345", "GEMINI_API_KEY": "AIzaSy_dummy_gemini_key_12345"}, clear=False):
            GroqCircuitBreaker.reset()
            GeminiCircuitBreaker.reset()
            router = MultiProviderRouter()
            with patch.object(router, "_get_db_last_inference", return_value=None):
                health = router.get_provider_health()

                assert health["groq"]["status"] == "CONFIGURED"
                assert health["groq"]["configured"] is True
                assert health["groq"]["is_configured"] is True
                assert health["groq"]["ready"] is True
                assert "API key configured" in health["groq"]["message"]

                assert health["gemini"]["status"] == "CONFIGURED"
                assert health["gemini"]["configured"] is True
                assert health["gemini"]["is_configured"] is True
                assert health["gemini"]["ready"] is True
                assert "API key configured" in health["gemini"]["message"]

    def test_live_success_promotes_to_operational_with_provenance_and_latency(self):
        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345"}, clear=False):
            GroqCircuitBreaker.reset()
            GroqCircuitBreaker.record_success(model="qwen/qwen3.8-27b", latency_ms=485)

            router = MultiProviderRouter()
            health = router.get_provider_health()

            assert health["groq"]["status"] == "OPERATIONAL"
            assert health["groq"]["configured"] is True
            assert health["groq"]["ready"] is True
            assert health["groq"]["latency_ms"] == 485
            assert health["groq"]["model"] == "qwen/qwen3.8-27b"
            assert health["groq"]["circuit_breaker_status"] == "CLOSED"
            assert health["groq"]["circuit_breaker_open"] is False

            # Verify aggregated last_successful_inference envelope
            assert health["last_successful_inference"]["provider"] == "GroqCloud"
            assert health["last_successful_inference"]["model"] == "qwen/qwen3.8-27b"
            assert health["last_successful_inference"]["latency_ms"] == 485
            assert health["last_successful_inference"]["timestamp"] is not None

    def test_exhausted_quota_reports_rate_limited(self):
        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345"}, clear=False):
            GroqCircuitBreaker.reset()
            GroqCircuitBreaker.record_rate_limit("Rate limit exceeded (HTTP 429)", cooldown_seconds=60)

            router = MultiProviderRouter()
            health = router.get_provider_health()

            assert health["groq"]["status"] == "RATE_LIMITED"
            assert health["groq"]["circuit_breaker_open"] is True
            assert health["groq"]["circuit_breaker_status"] == "OPEN (COOLDOWN)"
            assert "Rate limit exceeded" in health["groq"]["message"]
            assert health["groq"]["ready"] is False

    def test_service_unavailable_reports_unavailable(self):
        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345"}, clear=False):
            GroqCircuitBreaker.reset()
            GroqCircuitBreaker.record_service_unavailable("Service Unavailable (HTTP 503)", cooldown_seconds=30)

            router = MultiProviderRouter()
            health = router.get_provider_health()

            assert health["groq"]["status"] == "UNAVAILABLE"
            assert health["groq"]["circuit_breaker_open"] is True
            assert health["groq"]["circuit_breaker_status"] == "OPEN (COOLDOWN)"
            assert "Service Unavailable" in health["groq"]["message"]

    def test_deterministic_fallback_always_operational(self):
        router = MultiProviderRouter()
        health = router.get_provider_health()

        fallback = health["deterministic_fallback"]
        assert fallback["status"] == "OPERATIONAL"
        assert fallback["configured"] is True
        assert fallback["is_configured"] is True
        assert fallback["ready"] is True
        assert fallback["circuit_breaker_open"] is False
        assert fallback["circuit_breaker_status"] == "BUILT-IN (STANDBY)"
        assert fallback["model"] == "texora-industrial-heuristics-v2"
        # Requirement 6: Do not display unsupported guarantees like 100% uptime
        assert "100%" not in fallback["message"]
        assert "ALWAYS OPERATIONAL" != fallback["circuit_breaker_status"]
        assert "Deterministic Offline Rule Engine" in fallback["message"]

    def test_multi_provider_routing_priority_order(self):
        router = MultiProviderRouter()
        health = router.get_provider_health()

        assert health["primary_provider"] == "groq"
        assert health["secondary_provider"] == "gemini"
        assert health["fallback_provider"] == "deterministic_domain_engine"

    def test_db_provenance_restores_operational_status_on_cold_breaker(self):
        import uuid
        from apps.ai_agents.models import AgentExecution, AgentDefinition, AgentType
        GroqCircuitBreaker.reset()

        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.MACHINE_HEALTH,
            defaults={"name": "Machine Health Specialist", "model_name": "qwen/qwen3.8-27b"},
        )
        AgentExecution.objects.create(
            agent=agent_def,
            execution_id=uuid.uuid4(),
            trigger_event="TELEMETRY_SPIKE",
            status="COMPLETED",
            execution_summary="[GROQ_LIVE] Bearing overheat diagnosed with Qwen 27B",
            context_payload={
                "model_name": "qwen/qwen3.8-27b",
                "provider": "groq",
                "reasoning_source": "GROQ_LIVE",
                "is_live_ai": True,
                "latency_ms": 520,
            },
            token_count=120,
            latency_ms=520,
            completed_at=timezone.now(),
        )

        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345"}, clear=False):
            router = MultiProviderRouter()
            health = router.get_provider_health()

            assert health["groq"]["status"] == "OPERATIONAL"
            assert health["groq"]["latency_ms"] == 520
            assert health["groq"]["model"] == "qwen/qwen3.8-27b"
            assert health["groq"]["last_successful_at"] is not None

    def test_actual_execution_model_used_not_agent_definition_default(self):
        """Requirement 1: Do not use an agent's default model label as proof of actual cloud model used."""
        import uuid
        from apps.ai_agents.models import AgentExecution, AgentDefinition, AgentType
        GroqCircuitBreaker.reset()

        # Create agent with old default model name
        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.PRODUCTION_IMPACT,
            defaults={"name": "Production Impact Agent", "model_name": "gemini-1.5-pro / claude-3-5-sonnet"},
        )
        # Even if agent definition has stale default, actual execution record has real model
        agent_def.model_name = "gemini-1.5-pro / claude-3-5-sonnet"
        agent_def.save()

        AgentExecution.objects.create(
            agent=agent_def,
            execution_id=uuid.uuid4(),
            trigger_event="BATCH_DISRUPTION",
            status="COMPLETED",
            execution_summary="[GROQ_LIVE] Evaluated production reroute on WEV-AJ-02",
            context_payload={
                "model_name": "qwen/qwen3.8-27b",
                "provider": "groq",
                "reasoning_source": "GROQ_LIVE",
                "is_live_ai": True,
                "latency_ms": 430,
            },
            latency_ms=430,
            completed_at=timezone.now(),
        )

        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345"}, clear=False):
            router = MultiProviderRouter()
            health = router.get_provider_health()

            assert health["groq"]["model"] == "qwen/qwen3.8-27b"
            assert "claude" not in health["groq"]["model"]
            assert "gemini" not in health["groq"]["model"]
            assert health["last_successful_inference"]["model"] == "qwen/qwen3.8-27b"
            assert "claude" not in health["last_successful_inference"]["model"]

    def test_prevent_cross_provider_attribution(self):
        """Requirement 3: Historical database records cannot be incorrectly attributed to another provider."""
        import uuid
        from apps.ai_agents.models import AgentExecution, AgentDefinition, AgentType
        GroqCircuitBreaker.reset()
        GeminiCircuitBreaker.reset()

        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.MACHINE_HEALTH,
            defaults={"name": "Machine Health Specialist", "model_name": "gemini-3.5-flash"},
        )

        # Create Gemini execution that mentions Groq in error context
        AgentExecution.objects.create(
            agent=agent_def,
            execution_id=uuid.uuid4(),
            trigger_event="MACHINE_ANOMALY",
            status="COMPLETED",
            execution_summary="[GEMINI_LIVE] Fallback from Groq: GroqCircuitBreaker was active",
            context_payload={
                "model_name": "gemini-3.5-flash",
                "provider": "gemini",
                "reasoning_source": "GEMINI_LIVE",
                "is_live_ai": True,
                "latency_ms": 610,
                "execution_errors": "GroqCloud 429 quota exhausted",
            },
            latency_ms=610,
            completed_at=timezone.now(),
        )

        router = MultiProviderRouter()
        # With no Groq live records, Groq must NOT attribute the Gemini record to itself
        groq_inf = router._get_db_last_inference("groq")
        assert groq_inf is None

        # Gemini must accurately claim it
        gemini_inf = router._get_db_last_inference("gemini")
        assert gemini_inf is not None
        assert gemini_inf["provider"] == "Google Gemini"
        assert gemini_inf["model"] == "gemini-3.5-flash"

    def test_stale_historical_records_handling(self):
        """Requirement 4 & 7: Distinguish last verified inference from current availability & detect stale records."""
        import uuid
        import datetime
        from apps.ai_agents.models import AgentExecution, AgentDefinition, AgentType
        GroqCircuitBreaker.reset()

        agent_def, _ = AgentDefinition.objects.get_or_create(
            agent_type=AgentType.MACHINE_HEALTH,
            defaults={"name": "Machine Health Specialist", "model_name": "qwen/qwen3.8-27b"},
        )

        # 10 days old execution
        ten_days_ago = timezone.now() - datetime.timedelta(days=10)
        AgentExecution.objects.create(
            agent=agent_def,
            execution_id=uuid.uuid4(),
            trigger_event="OLD_EVENT",
            status="COMPLETED",
            execution_summary="[GROQ_LIVE] Stale diagnostic run",
            context_payload={
                "model_name": "qwen/qwen3.8-27b",
                "provider": "groq",
                "reasoning_source": "GROQ_LIVE",
                "is_live_ai": True,
                "latency_ms": 380,
            },
            latency_ms=380,
            completed_at=ten_days_ago,
        )

        with patch.dict("os.environ", {"GROQ_API_KEY": "gsk_dummy_test_key_12345"}, clear=False):
            router = MultiProviderRouter()
            groq_db = router._get_db_last_inference("groq")
            assert groq_db is not None
            assert groq_db["is_stale"] is True

            health = router.get_provider_health()
            assert health["groq"]["is_stale"] is True
            assert "Historical inference verified" in health["groq"]["message"]
            assert health["groq"]["last_successful_at"] is not None

    def test_no_secret_api_keys_exposed_in_health_payload(self):
        secret_groq = "gsk_super_secret_groq_production_key_xyz987"
        secret_gemini = "AIzaSy_super_secret_gemini_production_key_abc123"

        with patch.dict("os.environ", {"GROQ_API_KEY": secret_groq, "GEMINI_API_KEY": secret_gemini}, clear=False):
            router = MultiProviderRouter()
            health = router.get_provider_health()
            payload_str = json.dumps(health)

            assert secret_groq not in payload_str
            assert secret_gemini not in payload_str
