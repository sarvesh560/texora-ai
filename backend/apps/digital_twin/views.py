import uuid
from rest_framework import status, views
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from django.shortcuts import get_object_or_404
from .models import (
    DigitalTwinSnapshot,
    WhatIfScenario,
    ScenarioMachineChange,
    SimulationRun,
    SimulationResult,
    RecoveryStrategyEvaluation,
)
from .serializers import (
    DigitalTwinSnapshotSerializer,
    WhatIfScenarioSerializer,
    WhatIfScenarioCreateSerializer,
    SimulationRunSerializer,
    SimulationResultSerializer,
)
from .twin_engine import DigitalTwinEngine
from .simulation_engine import WhatIfSimulationEngine
from .ai_advisor import AIStrategyAdvisor


class DigitalTwinSnapshotView(views.APIView):
    """GET: Generates or fetches the latest dynamic factory digital twin snapshot."""
    permission_classes = [AllowAny]

    def get(self, request):
        force_refresh = request.query_params.get("refresh", "false").lower() in ["true", "1"]
        factory_code = request.query_params.get("factory", "FAC-01")

        snapshot_dict = DigitalTwinEngine.capture_snapshot(
            factory_code=factory_code, save_to_db=force_refresh
        )
        return Response({
            "status": "success",
            "data": snapshot_dict,
        }, status=status.HTTP_200_OK)


class DigitalTwinDepartmentsView(views.APIView):
    """GET: Returns department-level breakdown and capacity summary."""
    permission_classes = [AllowAny]

    def get(self, request):
        snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=False)
        operational_summary = snapshot_dict.get("operational_summary", {})
        dept_summaries = operational_summary.get("department_summaries", {})
        return Response({
            "status": "success",
            "departments": dept_summaries,
            "system_label": operational_summary.get("system_label", "SIMULATED FACTORY DIGITAL TWIN"),
        }, status=status.HTTP_200_OK)


class DigitalTwinMachineDetailView(views.APIView):
    """GET: Returns high-fidelity virtual twin state, telemetry, limits, and assignments for a machine."""
    permission_classes = [AllowAny]

    def get(self, request, machine_code):
        snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=False)
        machines = snapshot_dict.get("machine_states", [])
        m_state = next((m for m in machines if m["code"].upper() == machine_code.upper()), None)

        if not m_state:
            return Response({
                "status": "error",
                "message": f"Machine with code '{machine_code}' not found in virtual digital twin.",
            }, status=status.HTTP_404_NOT_FOUND)

        # Include compatible alternate machines
        compatibles = WhatIfSimulationEngine.get_compatible_alternates(machine_code.upper())
        m_state["compatible_alternates"] = compatibles

        return Response({
            "status": "success",
            "machine": m_state,
        }, status=status.HTTP_200_OK)


class FactoryDependencyGraphView(views.APIView):
    """GET: Material flow dependency topology across spinning, weaving, knitting, dyeing, finishing."""
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({
            "status": "success",
            "topology": WhatIfSimulationEngine.FACTORY_DEPENDENCY_GRAPH,
            "compatibility_groups": WhatIfSimulationEngine.COMPATIBILITY_GROUPS,
            "process_units": WhatIfSimulationEngine.DEPARTMENT_UNITS,
        }, status=status.HTTP_200_OK)


class WhatIfScenarioListView(views.APIView):
    """GET: List scenario history. POST: Create a new hypothetical scenario."""
    permission_classes = [AllowAny]

    def get(self, request):
        scenarios = WhatIfScenario.objects.all().order_by("-created_at")[:20]
        serializer = WhatIfScenarioSerializer(scenarios, many=True)
        return Response({
            "status": "success",
            "count": len(serializer.data),
            "scenarios": serializer.data,
        }, status=status.HTTP_200_OK)

    def post(self, request):
        serializer = WhatIfScenarioCreateSerializer(data=request.data)
        if not serializer.is_valid():
            return Response({
                "status": "error",
                "errors": serializer.errors,
            }, status=status.HTTP_400_BAD_REQUEST)

        data = serializer.validated_data
        machine_codes = data.pop("machine_codes", [])
        failure_type = data.pop("failure_type", "MECHANICAL_FAULT")

        # Capture baseline snapshot
        snapshot_dict = DigitalTwinEngine.capture_snapshot(save_to_db=True)
        snapshot_obj = DigitalTwinSnapshot.objects.get(id=snapshot_dict["id"])

        scenario_id = f"SCEN-{uuid.uuid4().hex[:8].upper()}"
        scenario = WhatIfScenario.objects.create(
            scenario_id=scenario_id,
            baseline_snapshot=snapshot_obj,
            **data,
        )

        # Create machine changes
        for code in machine_codes:
            ScenarioMachineChange.objects.create(
                scenario=scenario,
                machine_code=code.strip().upper(),
                simulated_state="CRITICAL",
                failure_type=failure_type,
                capacity_loss_pct=scenario.capacity_reduction_pct,
            )

        # Auto-run simulation immediately
        run = WhatIfSimulationEngine.run_simulation(scenario)

        response_serializer = WhatIfScenarioSerializer(scenario)
        return Response({
            "status": "success",
            "scenario": response_serializer.data,
            "run_id": str(run.run_id),
        }, status=status.HTTP_201_CREATED)


class WhatIfScenarioDetailView(views.APIView):
    """GET: Retrieve scenario configuration and latest run."""
    permission_classes = [AllowAny]

    def get(self, request, scenario_id):
        scenario = get_object_or_404(WhatIfScenario, scenario_id=scenario_id)
        serializer = WhatIfScenarioSerializer(scenario)
        return Response({
            "status": "success",
            "scenario": serializer.data,
        }, status=status.HTTP_200_OK)


class WhatIfSimulateView(views.APIView):
    """POST: Execute deterministic simulation run on scenario."""
    permission_classes = [AllowAny]

    def post(self, request, scenario_id):
        scenario = get_object_or_404(WhatIfScenario, scenario_id=scenario_id)
        run = WhatIfSimulationEngine.run_simulation(scenario)
        serializer = SimulationRunSerializer(run)
        return Response({
            "status": "success",
            "run": serializer.data,
        }, status=status.HTTP_200_OK)


class WhatIfResultsView(views.APIView):
    """GET: Retrieve latest simulation results, strategy evaluations, and playback timeline."""
    permission_classes = [AllowAny]

    def get(self, request, scenario_id):
        scenario = get_object_or_404(WhatIfScenario, scenario_id=scenario_id)
        run = scenario.runs.order_by("-executed_at").first()
        if not run:
            # Trigger run if never executed
            run = WhatIfSimulationEngine.run_simulation(scenario)

        run_serializer = SimulationRunSerializer(run)
        return Response({
            "status": "success",
            "scenario_id": scenario.scenario_id,
            "scenario_name": scenario.name,
            "run": run_serializer.data,
        }, status=status.HTTP_200_OK)


class WhatIfAIExplainView(views.APIView):
    """POST: Request Gemini-backed (or fallback) AI strategy explanation."""
    permission_classes = [AllowAny]

    def post(self, request, scenario_id):
        scenario = get_object_or_404(WhatIfScenario, scenario_id=scenario_id)
        run = scenario.runs.order_by("-executed_at").first()
        if not run:
            run = WhatIfSimulationEngine.run_simulation(scenario)

        result = getattr(run, "result", None)
        evaluations = list(run.strategy_evaluations.all())

        if not result or not evaluations:
            return Response({
                "status": "error",
                "message": "Simulation result or strategy evaluations missing for this scenario.",
            }, status=status.HTTP_400_BAD_REQUEST)

        force_provider = request.data.get("force_provider")
        explanation = AIStrategyAdvisor.generate_strategy_explanation(
            scenario=scenario,
            run=run,
            result=result,
            evaluations=evaluations,
            force_provider=force_provider,
        )

        return Response({
            "status": "success",
            "scenario_id": scenario.scenario_id,
            "ai_explanation": explanation,
        }, status=status.HTTP_200_OK)


class WhatIfDemoScenariosView(views.APIView):
    """GET: List the 3 Expo demonstration scenarios."""
    permission_classes = [AllowAny]

    def get(self, request):
        demos = [
            {
                "demo_code": "DEMO_A",
                "title": "Demo A — Single Loom Failure (WEV-AJ-02)",
                "target_machine": "WEV-AJ-02",
                "department": "Weaving Shed (WEV)",
                "description": "Hypothetical bearing seizure on Air Jet Loom WEV-AJ-02. Demonstrates localized repair vs rerouting to WEV-AJ-01.",
                "failure_duration": "4.0 hours",
                "repair_duration": "2.5 hours",
                "spare_parts": "FULL",
                "technicians": 2,
            },
            {
                "demo_code": "DEMO_B",
                "title": "Demo B — Multiple Weaving Cluster Failure (3 Looms)",
                "target_machine": "WEV-AJ-01, WEV-AJ-02, WEV-AJ-04",
                "department": "Weaving Shed (WEV)",
                "description": "Simultaneous severe drive and motor vibration alarms. Demonstrates department-wide capacity bottleneck and technician resource allocation.",
                "failure_duration": "6.0 hours",
                "repair_duration": "4.0 hours",
                "spare_parts": "PARTIAL",
                "technicians": 2,
            },
            {
                "demo_code": "DEMO_C",
                "title": "Demo C — Cross-Department Material Disruption",
                "target_machine": "SPN-RS-01",
                "department": "Spinning (SPN) -> Weaving & Knitting",
                "description": "Hypothetical Ring Spinning thermal excursion on SPN-RS-01 reducing yarn output by 80%. Evaluates downstream yarn buffer depletion and loom starvation.",
                "failure_duration": "8.0 hours",
                "repair_duration": "4.5 hours",
                "spare_parts": "FULL",
                "technicians": 3,
            },
        ]
        return Response({
            "status": "success",
            "demo_scenarios": demos,
        }, status=status.HTTP_200_OK)


class WhatIfLoadDemoView(views.APIView):
    """POST: Loads and runs one of the 3 Expo Demo Scenarios immediately."""
    permission_classes = [AllowAny]

    def post(self, request, demo_code):
        try:
            scenario = WhatIfSimulationEngine.load_demo_scenario(demo_code.upper())
            run = WhatIfSimulationEngine.run_simulation(scenario)
            run_serializer = SimulationRunSerializer(run)
            scenario_serializer = WhatIfScenarioSerializer(scenario)

            return Response({
                "status": "success",
                "message": f"Demo scenario {demo_code} loaded and simulated successfully.",
                "scenario": scenario_serializer.data,
                "run": run_serializer.data,
            }, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({
                "status": "error",
                "message": f"Failed to load demo scenario: {str(e)}",
            }, status=status.HTTP_400_BAD_REQUEST)
