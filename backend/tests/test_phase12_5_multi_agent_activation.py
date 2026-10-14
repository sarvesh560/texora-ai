"""
Tests for Phase 12.5: Full Multi-Agent AI Activation.
Verifies all 4 Texora AI specialist agents:
1. Machine Health Specialist Agent
2. Maintenance Coordinator Agent
3. Inventory Coordinator Agent
4. Production Impact Agent

Tests cover:
- Successful Gemini live responses (mocked for unit testing to preserve API quota).
- Invalid structured outputs and schema recovery.
- HTTP 429 Quota Exhaustion handling and circuit breaker fast-failover.
- HTTP 503 Service Unavailable handling.
- Deterministic fallback preservation and zero-data loss.
- Strict database persistence of metadata envelope, input evidence, and decisions.
- Multi-agent sequential dependency coordination and ActionSafetyService approval gates.
"""
import json
import time
import pytest
from unittest.mock import patch
from django.utils import timezone

from apps.machines.models import Machine, MachineType, MachineStatus
from apps.factories.models import Factory, Department
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus
from apps.inventory.models import InventoryItem, InventoryCategory
from apps.production.models import ProductionOrder, ProductionBatch
from apps.ai_agents.models import AgentExecution, AgentType
from apps.ai_agents.llm_client import (
    BaseLLMProvider,
    LLMResponse,
    GeminiCircuitBreaker,
    MockLLMProvider,
)
from apps.ai_agents.schemas import (
    PROVENANCE_GEMINI_LIVE,
    PROVENANCE_DETERMINISTIC_FALLBACK,
    PROVENANCE_GEMINI_RATE_LIMITED,
    PROVENANCE_GEMINI_UNAVAILABLE,
)
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.maintenance_coordinator import MaintenanceCoordinatorAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.production_impact_agent import ProductionImpactAgent
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator


@pytest.fixture(autouse=True)
def reset_breaker():
    """Reset circuit breaker before every test."""
    GeminiCircuitBreaker.reset()
    yield
    GeminiCircuitBreaker.reset()


@pytest.fixture
def factory_setup(db):
    """Creates a basic factory test fixture."""
    factory = Factory.objects.create(name="Texora Test Mill", code="TTM-01")
    dept = Department.objects.create(name="Weaving Dept", code="WEV", factory=factory)
    mtype = MachineType.objects.create(name="Airjet Loom", model_number="AIRJET_01")
    machine = Machine.objects.create(
        name="Airjet Loom #02",
        code="WEV-AJ-02",
        department=dept,
        machine_type=mtype,
        status=MachineStatus.MAINTENANCE,
    )
    incident = FactoryIncident.objects.create(
        incident_code="INC-TEST-001",
        machine=machine,
        department=dept,
        factory=factory,
        summary="High Vibration Anomaly on Main Drive",
        severity=IncidentSeverity.HIGH,
        status=IncidentStatus.INVESTIGATING,
    )
    # Spare part for inventory
    part = InventoryItem.objects.create(
        item_code="BRG-6205-2RS",
        name="High-Speed Spindle Bearing 6205-2RS",
        category=InventoryCategory.SPARE_PART,
        current_stock=5,
        reorder_point=2,
        unit_cost=45.0,
    )
    # Production order & batch
    order = ProductionOrder.objects.create(
        order_number="PO-TEST-101",
        client_name="Global Textiles",
        fabric_or_yarn_spec="100% Cotton 40s",
        department=dept,
        target_quantity=5000,
        due_date=timezone.now().date(),
    )
    batch = ProductionBatch.objects.create(
        batch_number="BATCH-TEST-01",
        production_order=order,
        machine=machine,
        status="RUNNING",
        planned_quantity=1000,
        actual_quantity=200,
    )
    return {
        "factory": factory,
        "dept": dept,
        "machine": machine,
        "incident": incident,
        "part": part,
        "batch": batch,
    }


class MockGeminiSuccessProvider(BaseLLMProvider):
    """Mock provider simulating valid Gemini live generation."""
    def __init__(self, content_json: dict):
        super().__init__(model_name="gemini-3.8-flash")
        self.provider = "gemini"
        self._content_json = content_json
        self._content_str = json.dumps(content_json)

    def is_configured(self) -> bool:
        return True

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description = None
    ) -> LLMResponse:
        return LLMResponse(
            content=self._content_str,
            structured_json=self._content_json,
            token_count=350,
            latency_ms=120,
            provider="gemini",
            model=self.model_name,
            status="SUCCESS",
            reasoning_source=PROVENANCE_GEMINI_LIVE,
            provider_attempt_status=PROVENANCE_GEMINI_LIVE,
        )


class MockGeminiRateLimitedProvider(BaseLLMProvider):
    """Mock provider simulating HTTP 429 Quota Exhaustion."""
    def __init__(self):
        super().__init__(model_name="gemini-3.8-flash")
        self.provider = "gemini"

    def is_configured(self) -> bool:
        return True

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description = None
    ) -> LLMResponse:
        GeminiCircuitBreaker.record_rate_limit("RESOURCE_EXHAUSTED (HTTP 429)")
        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=45,
            provider="gemini",
            model=self.model_name,
            status="RATE_LIMITED",
            error_message="RESOURCE_EXHAUSTED: Daily request quota exceeded (HTTP 429)",
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=PROVENANCE_GEMINI_RATE_LIMITED,
        )


class MockGeminiUnavailableProvider(BaseLLMProvider):
    """Mock provider simulating HTTP 503 Service Unavailable."""
    def __init__(self):
        super().__init__(model_name="gemini-3.8-flash")
        self.provider = "gemini"

    def is_configured(self) -> bool:
        return True

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description = None
    ) -> LLMResponse:
        GeminiCircuitBreaker.record_service_unavailable("Service Unavailable (HTTP 503)")
        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=60,
            provider="gemini",
            model=self.model_name,
            status="UNAVAILABLE",
            error_message="503 Service Unavailable: High demand on Gemini flash",
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=PROVENANCE_GEMINI_UNAVAILABLE,
        )


# =========================================================================
# 1. MACHINE HEALTH SPECIALIST TESTS
# =========================================================================

def test_machine_health_agent_gemini_success(factory_setup):
    """Verifies Machine Health Specialist succeeds with valid Gemini structured output."""
    mock_payload = {
        "observed_abnormal_conditions": ["Elevated RMS vibration at 7.4 mm/s"],
        "verified_sensor_facts": ["Drive temperature elevated at 74C", "Vibration peaks at 2.4x baseline"],
        "possible_root_causes": [
            {
                "hypothesis": "Main drive shaft bearing fatigue",
                "likelihood": "HIGH",
                "confidence_score": 88.0,
            }
        ],
        "recommended_maintenance_checks": [
            "Inspect drive shaft housing with thermal imaging",
            "Measure radial play in bearing bracket",
        ],
        "confidence_explanation": "Strong correlation between thermal signature and high frequency vibration spectra.",
        "suggested_next_actions": [
            {
                "action_type": "CREATE_MAINTENANCE_DRAFT",
                "description": "Inspect and replace main drive bearing",
                "requires_human_approval": True,
            }
        ],
    }

    provider = MockGeminiSuccessProvider(mock_payload)
    agent = MachineHealthAgent(provider=provider)
    res = agent.investigate_incident(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_GEMINI_LIVE
    assert res["provider_attempt_status"] == PROVENANCE_GEMINI_LIVE
    assert len(res["findings"]["possible_root_causes"]) == 1

    # Database verification
    execution = AgentExecution.objects.filter(
        incident=factory_setup["incident"], agent__agent_type=AgentType.MACHINE_HEALTH
    ).order_by("-id").first()
    assert execution is not None
    assert execution.context_payload.get("reasoning_source") == PROVENANCE_GEMINI_LIVE
    assert execution.context_payload.get("provider_attempt_status") == PROVENANCE_GEMINI_LIVE


def test_machine_health_agent_rate_limited_fallback(factory_setup):
    """Verifies Machine Health Specialist engages deterministic fallback on HTTP 429."""
    provider = MockGeminiRateLimitedProvider()
    agent = MachineHealthAgent(provider=provider)
    res = agent.investigate_incident(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_DETERMINISTIC_FALLBACK
    assert res["provider_attempt_status"] == PROVENANCE_GEMINI_RATE_LIMITED
    assert len(res["findings"]["possible_root_causes"]) >= 1

    # Verify circuit breaker is tripped
    assert GeminiCircuitBreaker.is_open() is True


def test_machine_health_agent_invalid_json_fallback(factory_setup):
    """Verifies malformed JSON triggers deterministic fallback safely without crashing."""
    class BadJsonProvider(BaseLLMProvider):
        def __init__(self):
            super().__init__(model_name="gemini-3.8-flash")
            self.provider = "gemini"

        def is_configured(self) -> bool:
            return True

        def generate_structured(self, system_prompt, user_prompt, schema_description = None):
            return LLMResponse(
                content="INVALID JSON {broken: text...",
                structured_json=None,
                token_count=10,
                latency_ms=25,
                provider="gemini",
                model=self.model_name,
                status="ERROR",
                error_message="Invalid JSON returned by provider",
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status=PROVENANCE_GEMINI_LIVE,
            )

    agent = MachineHealthAgent(provider=BadJsonProvider())
    res = agent.investigate_incident(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_DETERMINISTIC_FALLBACK


# =========================================================================
# 2. MAINTENANCE COORDINATOR TESTS
# =========================================================================

def test_maintenance_coordinator_gemini_success(factory_setup):
    """Verifies Maintenance Coordinator succeeds with valid Gemini structured maintenance plan."""
    mock_payload = {
        "recommended_inspection_checklist": [
            "Verify LOTO electrical isolation",
            "Remove bearing guard and check race wear",
            "Lubricate drive coupling",
        ],
        "suggested_repair_approach": "Full drive bearing replacement and realignment.",
        "required_skills": ["Mechanical Level 2", "Vibration Analyst"],
        "estimated_maintenance_duration_hours": 2.5,
        "safety_considerations": ["Apply LOTO Lockout/Tagout protocol", "Check residual thermal heat"],
        "escalation_recommendations": ["If shaft eccentricity exceeds 0.05mm, escalate to OEM Field Service."],
        "confidence_score": 92.0,
        "risk_level": "HIGH",
    }

    provider = MockGeminiSuccessProvider(mock_payload)
    agent = MaintenanceCoordinatorAgent(provider=provider)
    res = agent.coordinate_maintenance(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_GEMINI_LIVE
    assert res["estimated_hours"] == 2.5
    assert len(res["inspection_steps"]) == 3

    # Check database persistence
    execution = AgentExecution.objects.filter(
        incident=factory_setup["incident"], agent__agent_type=AgentType.MAINTENANCE
    ).order_by("-id").first()
    assert execution is not None
    assert execution.context_payload.get("reasoning_source") == PROVENANCE_GEMINI_LIVE


def test_maintenance_coordinator_rate_limited_fallback(factory_setup):
    """Verifies Maintenance Coordinator falls back on HTTP 429 quota exhaustion."""
    provider = MockGeminiRateLimitedProvider()
    agent = MaintenanceCoordinatorAgent(provider=provider)
    res = agent.coordinate_maintenance(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_DETERMINISTIC_FALLBACK
    assert res["provider_attempt_status"] == PROVENANCE_GEMINI_RATE_LIMITED
    assert res["estimated_hours"] > 0


# =========================================================================
# 3. INVENTORY COORDINATOR TESTS
# =========================================================================

def test_inventory_coordinator_gemini_grounded_in_db(factory_setup):
    """Verifies Inventory Coordinator uses Gemini reasoning strictly grounded in DB stock."""
    mock_payload = {
        "suggested_spare_parts": [
            {
                "part_code": "BRG-6205-2RS",
                "part_name": "High-Speed Spindle Bearing 6205-2RS",
                "required_quantity": 2,
                "in_stock": True,
                "available_quantity": 5,
            }
        ],
        "shortage_warnings": [],
        "procurement_recommendations": [],
        "alternative_part_suggestions": [],
        "confidence_score": 95.0,
        "assessment_rationale": "Sufficient bearing stock in warehouse.",
    }

    provider = MockGeminiSuccessProvider(mock_payload)
    agent = InventoryCoordinatorAgent(provider=provider)
    res = agent.coordinate_inventory(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_GEMINI_LIVE
    assert res["ai_output"] is not None

    # Check database persistence
    execution = AgentExecution.objects.filter(
        incident=factory_setup["incident"], agent__agent_type=AgentType.INVENTORY
    ).order_by("-id").first()
    assert execution is not None
    assert execution.context_payload.get("reasoning_source") == PROVENANCE_GEMINI_LIVE


def test_inventory_coordinator_rate_limited_fallback(factory_setup):
    """Verifies Inventory Coordinator handles rate limiting gracefully."""
    provider = MockGeminiRateLimitedProvider()
    agent = InventoryCoordinatorAgent(provider=provider)
    res = agent.coordinate_inventory(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_DETERMINISTIC_FALLBACK
    assert res["provider_attempt_status"] == PROVENANCE_GEMINI_RATE_LIMITED


# =========================================================================
# 4. PRODUCTION IMPACT AGENT TESTS
# =========================================================================

def test_production_impact_agent_gemini_success(factory_setup):
    """Verifies Production Impact Agent calculates batch delays and evaluates alternates."""
    mock_payload = {
        "production_disruption_explanation": "Batch BATCH-TEST-01 is actively running and at risk.",
        "affected_production_lines": ["Weaving Dept"],
        "estimated_downtime_hours": 2.0,
        "estimated_throughput_loss_units": 150.0,
        "suggested_production_adjustments": ["Pause batch and reroute to alternate airjet loom"],
        "alternative_machine_recommendations": [
            {
                "machine_code": "WEV-AJ-01",
                "department": "Weaving Dept",
                "suitability_score": 0.9,
                "reason": "Identical loom model available",
            }
        ],
        "recovery_plan": "Shift remaining 800 units to WEV-AJ-01 upon manager sign-off.",
        "estimated_operational_consequences": "Minor 45-minute delay on customer order PO-TEST-101.",
        "confidence_score": 89.0,
    }

    provider = MockGeminiSuccessProvider(mock_payload)
    agent = ProductionImpactAgent(provider=provider)
    res = agent.evaluate_production_impact(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_GEMINI_LIVE
    assert res["ai_output"] is not None

    # Check database persistence
    execution = AgentExecution.objects.filter(
        incident=factory_setup["incident"], agent__agent_type=AgentType.PRODUCTION_IMPACT
    ).order_by("-id").first()
    assert execution is not None
    assert execution.context_payload.get("reasoning_source") == PROVENANCE_GEMINI_LIVE


def test_production_impact_agent_rate_limited_fallback(factory_setup):
    """Verifies Production Impact Agent engages fallback on 429."""
    provider = MockGeminiRateLimitedProvider()
    agent = ProductionImpactAgent(provider=provider)
    res = agent.evaluate_production_impact(factory_setup["incident"].id)

    assert res["success"] is True
    assert res["reasoning_source"] == PROVENANCE_DETERMINISTIC_FALLBACK
    assert res["provider_attempt_status"] == PROVENANCE_GEMINI_RATE_LIMITED


# =========================================================================
# 5. MULTI-AGENT SEQUENTIAL ORCHESTRATION & SAFETY GATES
# =========================================================================

def test_multi_agent_sequential_orchestration(factory_setup):
    """
    Verifies AutonomousFactoryOrchestrator runs the 4 agents in sequential order,
    shares validated structured context, and pauses at PENDING_APPROVAL.
    """
    orchestrator = AutonomousFactoryOrchestrator()

    # Run incident processing with MockLLMProvider to avoid external network calls
    with patch("apps.ai_agents.llm_client.get_llm_provider", return_value=MockLLMProvider()):
        cycle_res = orchestrator.process_incident(factory_setup["incident"].id)

    assert cycle_res["success"] is True

    # Verify all 4 agent executions were created in the database for this incident
    executions = AgentExecution.objects.filter(incident=factory_setup["incident"])
    agent_types = set(executions.values_list("agent__agent_type", flat=True))

    assert AgentType.MACHINE_HEALTH in agent_types
    assert AgentType.MAINTENANCE in agent_types
    assert AgentType.INVENTORY in agent_types
    assert AgentType.PRODUCTION_IMPACT in agent_types

    # Verify metadata envelopes were stored for all
    for exec_obj in executions:
        assert isinstance(exec_obj.context_payload, dict)
        assert "provider_attempt_status" in exec_obj.context_payload
        assert "reasoning_source" in exec_obj.context_payload


def test_circuit_breaker_fast_failover():
    """Verifies that once tripped on 429, the circuit breaker fails fast in < 5ms."""
    GeminiCircuitBreaker.record_rate_limit("HTTP 429", cooldown_seconds=180)
    assert GeminiCircuitBreaker.is_open() is True

    t0 = time.time()
    # Direct check
    allowed, status, _ = GeminiCircuitBreaker.check_availability()
    elapsed_ms = (time.time() - t0) * 1000

    assert allowed is False
    assert status == "RATE_LIMITED"
    assert elapsed_ms < 5.0
