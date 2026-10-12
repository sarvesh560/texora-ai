import json
import logging
from typing import Any
from apps.ai_agents.llm_client import get_llm_provider, LLMResponse
from .models import WhatIfScenario, SimulationRun, SimulationResult, RecoveryStrategyEvaluation

logger = logging.getLogger(__name__)


class AIStrategyAdvisor:
    """Provides optional AI reasoning and executive strategy explanations for What-If simulation results."""

    SYSTEM_PROMPT = """You are the Texora AI Senior Industrial Operations & Factory Recovery Advisor.
Your objective is to provide executive-level decision support for factory managers evaluating What-If simulation results in a smart textile manufacturing mill.

CRITICAL RULES:
1. Ground your reasoning strictly on the provided deterministic simulation numbers. DO NOT invent, hallucinate, or alter any capacity, downtime, or output figures.
2. Clearly contrast Strategy A (Immediate Repair), Strategy B (Production Reroute), and Strategy C (Hybrid Prioritized Repair & Rerouting).
3. Clearly state assumptions, resource constraints (spare parts, technician count), and potential operational risks.
4. Output your analysis exclusively as valid JSON matching the required schema.
"""

    @classmethod
    def generate_strategy_explanation(
        cls,
        scenario: WhatIfScenario,
        run: SimulationRun,
        result: SimulationResult,
        evaluations: list[RecoveryStrategyEvaluation],
        force_provider: str | None = None,
    ) -> dict[str, Any]:
        """Generates structured reasoning via Google Gemini (with deterministic local fallback)."""

        eval_summaries = []
        for e in evaluations:
            eval_summaries.append({
                "strategy_code": e.strategy_code,
                "strategy_name": e.strategy_name,
                "rank": e.rank,
                "is_feasible": e.is_feasible,
                "infeasibility_reasons": e.infeasibility_reasons,
                "estimated_downtime_hours": e.estimated_downtime_hours,
                "capacity_recovered_pct": e.capacity_recovered_pct,
                "estimated_output_loss": e.estimated_output_loss,
                "recovery_time_hours": e.recovery_time_hours,
                "pros": e.pros,
                "cons": e.cons,
                "estimated_cost": e.estimated_cost,
            })

        evidence_payload = {
            "scenario_id": scenario.scenario_id,
            "scenario_name": scenario.name,
            "scenario_type": scenario.scenario_type,
            "failure_duration_hours": scenario.failure_duration_hours,
            "repair_duration_hours": scenario.repair_duration_hours,
            "spare_parts_availability": scenario.spare_parts_availability,
            "technicians_available": scenario.technicians_available,
            "bottleneck_department": result.bottleneck_department,
            "lost_machine_operating_hours": result.lost_machine_operating_hours,
            "capacity_reduction_pct": result.capacity_reduction_pct,
            "estimated_output_loss": result.estimated_output_loss,
            "potential_order_delays": result.potential_order_delays,
            "alternate_machines_count": len(result.alternative_machine_utilization),
            "strategy_evaluations": eval_summaries,
        }

        user_prompt = f"""
Evaluate the following What-If simulation results and produce an executive advisor report in JSON:

EVIDENCE:
{json.dumps(evidence_payload, indent=2)}

REQUIRED JSON FORMAT:
{{
  "executive_summary": "Concise 2-sentence summary of disruption and primary recovery vector.",
  "recommended_strategy_code": "STRATEGY_C",
  "recommended_strategy_title": "Strategy C — Hybrid Prioritized Repair & Rerouting",
  "recommendation_rationale": "Detailed evidence-backed explanation citing exact hours saved and output preserved.",
  "alternative_strategies_assessment": [
    {{
      "strategy_code": "STRATEGY_A",
      "verdict": "Sub-optimal / Feasible",
      "reason_for_lower_rank": "Explanation"
    }},
    {{
      "strategy_code": "STRATEGY_B",
      "verdict": "Partial Mitigation",
      "reason_for_lower_rank": "Explanation"
    }}
  ],
  "operational_risks": [
    "Key risk 1 (e.g. Technician multitasking strain)",
    "Key risk 2 (e.g. Spare part stockout tolerance)"
  ],
  "underlying_assumptions": [
    "Assumption 1",
    "Assumption 2"
  ]
}}
"""

        provider = get_llm_provider(force_provider=force_provider)
        response: LLMResponse = provider.generate_structured(
            system_prompt=cls.SYSTEM_PROMPT,
            user_prompt=user_prompt,
        )

        if response.status == "SUCCESS" and response.structured_json:
            advisor_data = response.structured_json
            advisor_data["is_live_gemini"] = (response.provider == "gemini")
            advisor_data["provider"] = response.provider
            advisor_data["model_name"] = response.model
            advisor_data["latency_ms"] = response.latency_ms
            advisor_data["source"] = "LIVE_AI_INFERENCE" if response.provider == "gemini" else "MOCK_AI_INFERENCE"
            return advisor_data

        # Robust Deterministic Fallback if LLM is offline or unconfigured
        logger.info("Falling back to deterministic Strategy Advisor (LLM status: %s)", response.status)
        top_strat = next((e for e in evaluations if e.rank == 1 and e.is_feasible), evaluations[0] if evaluations else None)
        top_code = top_strat.strategy_code if top_strat else "STRATEGY_C"
        top_name = top_strat.strategy_name if top_strat else "Hybrid Recovery"

        fallback_data = {
            "executive_summary": (
                f"Simulated disruption in {result.bottleneck_department} department incurs "
                f"{result.lost_machine_operating_hours} lost machine hours with a {result.capacity_reduction_pct}% capacity drop. "
                f"{top_name} provides the optimal balance of throughput continuity and asset restoration."
            ),
            "recommended_strategy_code": top_code,
            "recommended_strategy_title": top_name,
            "recommendation_rationale": (
                f"{top_name} recovers {top_strat.capacity_recovered_pct if top_strat else 100}% capacity in "
                f"{top_strat.recovery_time_hours if top_strat else 3.0} hours while mitigating output loss across active orders."
            ),
            "alternative_strategies_assessment": [
                {
                    "strategy_code": e.strategy_code,
                    "verdict": "Feasible Alternative" if e.is_feasible else "Infeasible Constraint",
                    "reason_for_lower_rank": (
                        f"Estimated downtime {e.estimated_downtime_hours}h produces higher cumulative delay "
                        f"compared to top-ranked {top_code}."
                    ),
                }
                for e in evaluations
                if e != top_strat
            ],
            "operational_risks": [
                f"Spare parts availability level: {scenario.spare_parts_availability}.",
                f"Technician capacity ({scenario.technicians_available} available) must support parallel work orders.",
                f"Downstream buffer depletion in {result.bottleneck_department} after {scenario.failure_duration_hours}h.",
            ],
            "underlying_assumptions": [
                f"Alternate machine headroom capped at 25% surge utilization.",
                f"Nominal factory shift duration: {scenario.shift_duration_hours}h.",
                "Material quality remains homogeneous across compatible machines.",
            ],
            "is_live_gemini": False,
            "provider": "deterministic_fallback",
            "model_name": "rule-based-advisor-v7",
            "latency_ms": 1,
            "source": "DETERMINISTIC_FALLBACK_ADVISOR",
            "fallback_reason": response.error_message or "Live LLM Provider offline / unconfigured",
        }
        return fallback_data
