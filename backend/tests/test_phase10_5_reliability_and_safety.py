"""
Phase 10.5 Comprehensive Reliability, Operational Safety & Expo Readiness Regression Tests.
Verifies:
1. Digital Twin Multi-Objective Ranking Consistency (No duplicate Rank 1 ties when costs differ)
2. Worker Heartbeat Live Tracking & Stale Detection
3. Worker Health API Endpoint (/api/v1/health/workers/)
4. Gemini HTTP 429 Fast-Failover & Deterministic Provenance
5. Inventory Operational Safety Gating (No warehouse stock deduction before manager approval)
6. Server-side RBAC & AI Self-Approval Rejection
"""
import pytest
from unittest.mock import patch, MagicMock
from decimal import Decimal
from django.utils import timezone

from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import Machine, MachineType, MachineStatus, MachineOperatingLimits, MachineTelemetry
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus, WorkerHeartbeat
from apps.approvals.models import ApprovalRequest, ApprovalStatus
from apps.inventory.models import InventoryItem, InventoryTransaction, InventoryCategory
from apps.ai_agents.models import AgentDefinition, AgentExecution, AgentAction, AgentType, AutonomousWorkflowRun, AutonomousWorkflowStage
from apps.ai_agents.action_service import ActionSafetyService, ActionSafetyLevel
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.llm_client import GeminiProvider, LLMResponse
from apps.digital_twin.models import WhatIfScenario, ScenarioMachineChange
from apps.digital_twin.simulation_engine import WhatIfSimulationEngine


@pytest.fixture
def factory_setup(db):
    factory = Factory.objects.create(name="Texora Test Mill", code="TTM-01", location="Coimbatore")
    weaving_dept = Department.objects.create(
        factory=factory, name="Weaving Shed", code="WEV", department_type=DepartmentType.WEAVING
    )
    spinning_dept = Department.objects.create(
        factory=factory, name="Spinning Dept", code="SPN", department_type=DepartmentType.SPINNING
    )
    machine_type = MachineType.objects.create(
        name="Air Jet Loom",
        category=DepartmentType.WEAVING,
        manufacturer="Toyota Industries",
        model_number="JAT810",
    )
    loom = Machine.objects.create(
        department=weaving_dept,
        machine_type=machine_type,
        code="WEV-AJ-02",
        name="Air Jet Loom #02",
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("60.0"),
    )
    alt_loom = Machine.objects.create(
        department=weaving_dept,
        machine_type=machine_type,
        code="WEV-AJ-01",
        name="Air Jet Loom #01",
        status=MachineStatus.OPERATIONAL,
        rated_capacity_units_per_hour=Decimal("60.0"),
    )
    limits = MachineOperatingLimits.objects.create(
        machine=loom,
        warning_temp_c=70.0,
        max_temp_c=80.0,
        warning_vibration_mms=4.0,
        max_vibration_mms=5.5,
    )
    spare_bearing = InventoryItem.objects.create(
        item_code="SPR-BRG-6204",
        name="6204-2RS Deep Groove Ball Bearing",
        category=InventoryCategory.SPARE_PART,
        current_stock=Decimal("10.0"),
        minimum_safety_stock=Decimal("2.0"),
        reorder_point=Decimal("5.0"),
        unit_cost=Decimal("4500.00"),
        location_shelf="RACK-A-04",
    )
    return {
        "factory": factory,
        "weaving_dept": weaving_dept,
        "spinning_dept": spinning_dept,
        "machine_type": machine_type,
        "loom": loom,
        "alt_loom": alt_loom,
        "limits": limits,
        "spare_bearing": spare_bearing,
    }


@pytest.mark.django_db
class TestPhase105ReliabilityAndSafety:

    def test_digital_twin_ranking_consistency(self, factory_setup):
        """Test that Strategy A (Cost ₹6,921) and Strategy C (Cost ₹10,521) have distinct, correct ranks."""
        scenario = WhatIfScenario.objects.create(
            scenario_id="SCEN-TEST-RANK-01",
            name="Loom Bearing Disruption Test",
            scenario_type="SINGLE_MACHINE_FAILURE",
            failure_duration_hours=3.0,
            repair_duration_hours=1.5,
            capacity_reduction_pct=100.0,
            spare_parts_availability="FULL",
            technicians_available=2,
        )
        ScenarioMachineChange.objects.create(
            scenario=scenario,
            machine_code="WEV-AJ-02",
            simulated_state="CRITICAL",
            failure_type="MAIN_BEARING_FAILURE",
        )

        sim_run = WhatIfSimulationEngine.run_simulation(scenario)
        evals = list(sim_run.strategy_evaluations.all().order_by("rank"))

        assert len(evals) == 3
        # Assert each strategy has a distinct rank: 1, 2, 3
        ranks = [e.rank for e in evals]
        assert ranks == [1, 2, 3], f"Expected ranks [1, 2, 3] but got {ranks}"

        # Strategy A with lowest cost should be Rank 1
        rank_1_strat = evals[0]
        rank_2_strat = evals[1]
        cost_1 = rank_1_strat.estimated_cost.get("total_estimated_cost_inr", 0)
        cost_2 = rank_2_strat.estimated_cost.get("total_estimated_cost_inr", 0)
        assert cost_1 <= cost_2, "Rank 1 strategy must have cost <= Rank 2 strategy"

    def test_worker_heartbeat_live_tracking_and_stale_detection(self, db):
        """Test WorkerHeartbeat recording, computation, and stale heartbeat detection."""
        # 1. Record live heartbeat
        wb = WorkerHeartbeat.record_heartbeat(
            worker_name="ANOMALY_DETECTOR",
            process_id=1234,
            status="RUNNING",
            metrics={"total_processed": 500},
        )
        assert wb.status == "RUNNING"
        assert not wb.is_stale(max_seconds=15)
        assert wb.computed_status(max_seconds=15) == "RUNNING"

        # 2. Simulate stale heartbeat by setting last_heartbeat_at in the past
        past_time = timezone.now() - timezone.timedelta(seconds=60)
        WorkerHeartbeat.objects.filter(worker_name="ANOMALY_DETECTOR").update(last_heartbeat_at=past_time)

        stale_wb = WorkerHeartbeat.objects.get(worker_name="ANOMALY_DETECTOR")
        assert stale_wb.is_stale(max_seconds=15) is True
        assert stale_wb.computed_status(max_seconds=15) == "STOPPED"

    def test_worker_health_api_endpoint(self, client, db):
        """Test that GET /api/v1/health/workers/ accurately returns worker states."""
        WorkerHeartbeat.record_heartbeat(
            worker_name="AUTONOMOUS_ORCHESTRATOR",
            process_id=5678,
            status="RUNNING",
            metrics={"active_cases": 2},
        )

        response = client.get("/api/v1/health/workers/")
        assert response.status_code == 200
        data = response.json()
        assert "overall_status" in data
        assert "django_api" in data
        assert "database" in data
        assert "gemini_provider" in data
        assert "workers" in data
        assert "autonomous_orchestrator" in data["workers"]
        assert data["workers"]["autonomous_orchestrator"]["process_id"] == 5678

    def test_gemini_429_fast_failover(self, factory_setup):
        """Test that HTTP 429 quota exhaustion fast-fails over to deterministic fallback without slow loops."""
        provider = GeminiProvider(api_key="test_key")

        mock_response = MagicMock()
        mock_response.status_code = 429
        mock_response.text = '{"error": {"code": 429, "message": "RESOURCE_EXHAUSTED: Quota exceeded"}}'
        mock_response.json.return_value = {"error": {"code": 429, "message": "RESOURCE_EXHAUSTED: Quota exceeded"}}

        with patch("requests.post", return_value=mock_response) as mock_post:
            res: LLMResponse = provider.generate_structured("system prompt", "user query")
            assert res.status == "RATE_LIMITED"
            # Fast failover: should not loop across all retries
            assert mock_post.call_count == 1

    def test_machine_health_agent_provenance_on_fallback(self, factory_setup):
        """Test that MachineHealthAgent sets accurate provenance and never fabricates live Gemini inference."""
        loom = factory_setup["loom"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-001",
            factory=factory_setup["factory"],
            department=factory_setup["weaving_dept"],
            machine=loom,
            severity=IncidentSeverity.CRITICAL,
            summary="Vibration anomaly on WEV-AJ-02",
        )

        # Force unconfigured / fallback provider
        agent = MachineHealthAgent()
        agent.provider = GeminiProvider(api_key="")  # Unconfigured

        res = agent.investigate_incident(incident.id)
        assert res["success"] is True
        assert res["is_live_gemini"] is False
        assert "provenance" in res
        assert res["provenance"] in ["GEMINI_UNCONFIGURED", "DETERMINISTIC_FALLBACK"]

        # Verify incident hypothesis is tagged with fallback provenance
        incident.refresh_from_db()
        assert "[AI Root Cause Hypothesis]" not in incident.root_cause_hypothesis
        assert f"[{res['provenance']} Hypothesis]" in incident.root_cause_hypothesis

    def test_inventory_operational_safety_no_premature_stock_deduction(self, factory_setup):
        """Test that InventoryCoordinatorAgent ONLY proposes reservation without mutating warehouse stock."""
        loom = factory_setup["loom"]
        spare_bearing = factory_setup["spare_bearing"]
        initial_stock = spare_bearing.current_stock

        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-002",
            factory=factory_setup["factory"],
            department=factory_setup["weaving_dept"],
            machine=loom,
            severity=IncidentSeverity.HIGH,
            summary="Bearing wear detected",
        )

        coord = InventoryCoordinatorAgent()
        result = coord.coordinate_inventory(incident.id)
        assert result["success"] is True

        # Assert warehouse inventory stock has NOT been deducted
        spare_bearing.refresh_from_db()
        assert spare_bearing.current_stock == initial_stock, "Inventory stock must not mutate before approval!"

        # Assert no InventoryTransaction was created yet
        tx_count = InventoryTransaction.objects.filter(item=spare_bearing).count()
        assert tx_count == 0

        # Assert approval request was created
        approval = ApprovalRequest.objects.filter(incident=incident, requested_action="RESERVE_SPARE_PART").first()
        assert approval is not None
        assert approval.status == ApprovalStatus.PENDING

        # Now approve with authorized role
        exec_res = ActionSafetyService.approve_and_execute(
            approval_id=approval.id,
            approved_by="Warehouse Operations Manager",
            user_role="WAREHOUSE_MANAGER",
        )
        assert exec_res["success"] is True

        # Now verify reservation transaction was created post-approval
        post_tx = InventoryTransaction.objects.filter(item=spare_bearing).first()
        assert post_tx is not None
        assert post_tx.transaction_type == "RESERVATION"

    def test_ai_agent_self_approval_rejection(self, factory_setup):
        """Test that AI agent identities cannot self-authorize operational mutations."""
        loom = factory_setup["loom"]
        incident = FactoryIncident.objects.create(
            incident_code="INC-TEST-003",
            factory=factory_setup["factory"],
            department=factory_setup["weaving_dept"],
            machine=loom,
            severity=IncidentSeverity.CRITICAL,
            summary="Drive failure",
        )
        approval = ApprovalRequest.objects.create(
            approval_code="APR-TEST-SELF-01",
            incident=incident,
            title="Authorize Ticket",
            requested_action="CREATE_MAINTENANCE_TICKET",
            status=ApprovalStatus.PENDING,
        )

        # Attempt self-approval as AI agent identity
        res = ActionSafetyService.approve_and_execute(
            approval_id=approval.id,
            approved_by="machine_health_agent",
            user_role="MAINTENANCE_MANAGER",
        )
        assert res["success"] is False
        assert "Security Violation" in res["error"]
