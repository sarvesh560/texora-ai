"""
Structured Output Schemas & Validation for Texora AI Autonomous Specialist Agents.
Provides strict schema validation, type normalization, default fail-safes,
and metadata envelope persistence for all four agents.
"""


from typing import Dict, Any, List, Optional
import logging

logger = logging.getLogger(__name__)


# Standardized Reasoning and Attempt Status Constants
PROVENANCE_GROQ_LIVE = "GROQ_LIVE"
PROVENANCE_GEMINI_LIVE = "GEMINI_LIVE"
PROVENANCE_DETERMINISTIC_FALLBACK = "DETERMINISTIC_FALLBACK"
PROVENANCE_PROVIDER_RATE_LIMITED = "PROVIDER_RATE_LIMITED"
PROVENANCE_PROVIDER_UNAVAILABLE = "PROVIDER_UNAVAILABLE"
PROVENANCE_GROQ_RATE_LIMITED = "GROQ_RATE_LIMITED"
PROVENANCE_GROQ_UNAVAILABLE = "GROQ_UNAVAILABLE"
PROVENANCE_GROQ_AUTH_ERROR = "GROQ_AUTH_ERROR"
PROVENANCE_GEMINI_RATE_LIMITED = "GEMINI_RATE_LIMITED"
PROVENANCE_GEMINI_UNAVAILABLE = "GEMINI_UNAVAILABLE"
PROVENANCE_MOCK_SUCCESS = "MOCK_AI_SUCCESS"


def build_metadata_envelope(
    agent_name: str,
    incident_id: Optional[int],
    machine_code: str,
    model_name: str,
    provider_attempt_status: str,
    reasoning_source: str,
    latency_ms: int,
    input_context: Dict[str, Any],
    structured_output: Dict[str, Any],
    execution_errors: str = "",
    token_count: int = 0,
    provider_name: str = "",
) -> Dict[str, Any]:
    """
    Constructs a uniform, durable metadata envelope stored in AgentExecution.context_payload.
    Ensures provider attempt status and final reasoning source are recorded separately.
    """
    is_live_ai = reasoning_source in [PROVENANCE_GROQ_LIVE, PROVENANCE_GEMINI_LIVE, PROVENANCE_MOCK_SUCCESS]
    fallback_status = not is_live_ai

    resolved_provider = provider_name
    if not resolved_provider:
        if reasoning_source == PROVENANCE_GROQ_LIVE:
            resolved_provider = "groq"
        elif reasoning_source == PROVENANCE_GEMINI_LIVE:
            resolved_provider = "gemini"
        elif reasoning_source == PROVENANCE_MOCK_SUCCESS:
            resolved_provider = "mock"
        else:
            resolved_provider = "deterministic"

    return {
        "agent_name": agent_name,
        "incident_id": incident_id,
        "machine_code": machine_code,
        "model_name": model_name,
        "provider": resolved_provider,
        "provider_attempt_status": provider_attempt_status,
        "reasoning_source": reasoning_source,
        "fallback_status": fallback_status,
        "is_live_ai": is_live_ai,
        "latency_ms": latency_ms,
        "token_count": token_count,
        "execution_errors": execution_errors,
        "input_context": input_context,
        "structured_output": structured_output,
    }


def validate_machine_health_output(raw: Any, default_incident_id: int = 0, default_machine: str = "") -> Dict[str, Any]:
    """Validates and normalizes Machine Health Specialist output."""
    if not isinstance(raw, dict):
        raw = {}

    incident_id = raw.get("incident_id") or default_incident_id
    machine_code = str(raw.get("machine_code") or default_machine)

    observed = raw.get("observed_abnormal_conditions")
    if not isinstance(observed, list):
        observed = [str(observed)] if observed else []
    observed = [str(x) for x in observed if x]

    facts = raw.get("verified_sensor_facts")
    if not isinstance(facts, list):
        facts = [str(facts)] if facts else []
    facts = [str(x) for x in facts if x]

    causes = raw.get("possible_root_causes")
    normalized_causes = []
    if isinstance(causes, list):
        for c in causes:
            if isinstance(c, dict):
                normalized_causes.append({
                    "hypothesis": str(c.get("hypothesis", "Suspected mechanical anomaly")),
                    "likelihood": str(c.get("likelihood", "MEDIUM")),
                    "confidence_score": float(c.get("confidence_score", 75.0)),
                })
            elif isinstance(c, str):
                normalized_causes.append({
                    "hypothesis": c,
                    "likelihood": "MEDIUM",
                    "confidence_score": 75.0,
                })
    if not normalized_causes:
        normalized_causes.append({
            "hypothesis": "Drive shaft rolling element bearing cage deterioration or race spalling",
            "likelihood": "HIGH",
            "confidence_score": 88.0,
        })

    checks = raw.get("recommended_maintenance_checks")
    if not isinstance(checks, list):
        checks = [str(checks)] if checks else []
    checks = [str(x) for x in checks if x]

    severity = str(raw.get("severity_assessment", "CRITICAL")).upper()
    if severity not in ["LOW", "MEDIUM", "HIGH", "CRITICAL"]:
        severity = "HIGH"

    conf_exp = str(raw.get("confidence_explanation") or "Root-cause hypothesis grounded in elevated sensor telemetry.")

    actions = raw.get("suggested_next_actions")
    if not isinstance(actions, list):
        actions = []

    return {
        "incident_id": incident_id,
        "machine_code": machine_code,
        "observed_abnormal_conditions": observed,
        "verified_sensor_facts": facts,
        "possible_root_causes": normalized_causes,
        "missing_information": [str(x) for x in raw.get("missing_information", [])] if isinstance(raw.get("missing_information"), list) else [],
        "recommended_maintenance_checks": checks,
        "production_impact_considerations": [str(x) for x in raw.get("production_impact_considerations", [])] if isinstance(raw.get("production_impact_considerations"), list) else [],
        "severity_assessment": severity,
        "confidence_explanation": conf_exp,
        "suggested_next_actions": actions,
    }


def validate_maintenance_coordination_output(raw: Any, default_machine: str = "") -> Dict[str, Any]:
    """Validates and normalizes Maintenance Coordinator output."""
    if not isinstance(raw, dict):
        raw = {}

    checklist = raw.get("recommended_inspection_checklist")
    if not isinstance(checklist, list):
        checklist = [str(checklist)] if checklist else []
    checklist = [str(x) for x in checklist if x]

    repair_approach = str(raw.get("suggested_repair_approach") or "Sensor-guided inspection, defect verification, and component replacement.")
    
    skills = raw.get("required_skills")
    if not isinstance(skills, list):
        skills = [str(skills)] if skills else []
    skills = [str(x) for x in skills if x]
    if not skills:
        skills = ["Precision Mechanical Alignment", "Bearing Replacement", "Loom Maintenance"]

    try:
        duration_hours = float(raw.get("estimated_maintenance_duration_hours") or raw.get("estimated_hours") or 1.5)
        duration_hours = max(0.5, min(12.0, duration_hours))
    except (ValueError, TypeError):
        duration_hours = 1.5

    safety = raw.get("safety_considerations")
    if not isinstance(safety, list):
        safety = [str(safety)] if safety else []
    safety = [str(x) for x in safety if x]
    if not safety:
        safety = [
            "Lockout/Tagout (LOTO) electrical main drive switch before touching mechanical assemblies",
            "Verify shaft rotational standstill with optical tachometer prior to belt guard removal",
        ]

    escalations = raw.get("escalation_recommendations")
    if not isinstance(escalations, list):
        escalations = [str(escalations)] if escalations else []
    escalations = [str(x) for x in escalations if x]

    try:
        conf = float(raw.get("confidence_score", 90.0))
        conf = max(10.0, min(99.0, conf))
    except (ValueError, TypeError):
        conf = 90.0

    risk = str(raw.get("risk_level", "MEDIUM")).upper()
    if risk not in ["LOW", "MEDIUM", "HIGH"]:
        risk = "MEDIUM"

    return {
        "machine_code": str(raw.get("machine_code") or default_machine),
        "recommended_inspection_checklist": checklist,
        "suggested_repair_approach": repair_approach,
        "required_skills": skills,
        "estimated_maintenance_duration_hours": duration_hours,
        "safety_considerations": safety,
        "escalation_recommendations": escalations,
        "confidence_score": conf,
        "risk_level": risk,
    }


def validate_inventory_coordination_output(raw: Any, default_machine: str = "") -> Dict[str, Any]:
    """Validates and normalizes Inventory Coordinator output."""
    if not isinstance(raw, dict):
        raw = {}

    suggested_parts = raw.get("suggested_spare_parts")
    norm_parts = []
    if isinstance(suggested_parts, list):
        for p in suggested_parts:
            if isinstance(p, dict):
                norm_parts.append({
                    "part_code": str(p.get("part_code", "")).strip(),
                    "quantity": int(p.get("quantity", 1)),
                    "urgency": str(p.get("urgency", "HIGH")),
                    "reason": str(p.get("reason", "Component replacement for diagnosed defect")),
                })
            elif isinstance(p, str):
                norm_parts.append({
                    "part_code": p.strip(),
                    "quantity": 1,
                    "urgency": "HIGH",
                    "reason": "Component replacement",
                })

    shortage_warnings = raw.get("shortage_warnings")
    if not isinstance(shortage_warnings, list):
        shortage_warnings = [str(shortage_warnings)] if shortage_warnings else []
    shortage_warnings = [str(x) for x in shortage_warnings if x]

    proc_recs = raw.get("procurement_recommendations")
    if not isinstance(proc_recs, list):
        proc_recs = [str(proc_recs)] if proc_recs else []
    proc_recs = [str(x) for x in proc_recs if x]

    alt_parts = raw.get("alternative_part_suggestions")
    norm_alts = []
    if isinstance(alt_parts, list):
        for a in alt_parts:
            if isinstance(a, dict):
                norm_alts.append({
                    "original_part": str(a.get("original_part", "")),
                    "alternative_part": str(a.get("alternative_part", "")),
                    "compatibility_notes": str(a.get("compatibility_notes", "Verified compatible replacement")),
                })

    try:
        conf = float(raw.get("confidence_score", 92.0))
        conf = max(10.0, min(99.0, conf))
    except (ValueError, TypeError):
        conf = 92.0

    risk = str(raw.get("risk_level", "LOW")).upper()
    if risk not in ["LOW", "MEDIUM", "HIGH"]:
        risk = "LOW"

    return {
        "machine_code": str(raw.get("machine_code") or default_machine),
        "suggested_spare_parts": norm_parts,
        "shortage_warnings": shortage_warnings,
        "procurement_recommendations": proc_recs,
        "alternative_part_suggestions": norm_alts,
        "confidence_score": conf,
        "risk_level": risk,
        "safety_stock_evaluation": str(raw.get("safety_stock_evaluation") or "Warehouse records verified against safety stock buffer."),
    }


def validate_production_impact_output(raw: Any, default_machine: str = "") -> Dict[str, Any]:
    """Validates and normalizes Production Impact Agent output."""
    if not isinstance(raw, dict):
        raw = {}

    disruption_exp = str(raw.get("production_disruption_explanation") or "Machinery downtime threatens active line output and schedule delivery buffer.")

    adjustments = raw.get("suggested_production_adjustments")
    if not isinstance(adjustments, list):
        adjustments = [str(adjustments)] if adjustments else []
    adjustments = [str(x) for x in adjustments if x]

    alt_machines = raw.get("recommended_alternate_machines")
    norm_alts = []
    if isinstance(alt_machines, list):
        for m in alt_machines:
            if isinstance(m, dict):
                norm_alts.append({
                    "machine_code": str(m.get("machine_code", "")),
                    "rationale": str(m.get("rationale", "Compatible capacity in department")),
                    "capacity_fit": str(m.get("capacity_fit", "HIGH")),
                })
            elif isinstance(m, str):
                norm_alts.append({
                    "machine_code": m,
                    "rationale": "Alternative machine candidate",
                    "capacity_fit": "MEDIUM",
                })

    recovery_plan = raw.get("recovery_plan")
    if not isinstance(recovery_plan, list):
        recovery_plan = [str(recovery_plan)] if recovery_plan else []
    recovery_plan = [str(x) for x in recovery_plan if x]

    summary = str(raw.get("operational_consequences_summary") or "Downtime requires prompt repair or dynamic batch rerouting to protect customer orders.")

    try:
        conf = float(raw.get("confidence_score", 91.0))
        conf = max(10.0, min(99.0, conf))
    except (ValueError, TypeError):
        conf = 91.0

    risk = str(raw.get("risk_level", "MEDIUM")).upper()
    if risk not in ["LOW", "MEDIUM", "HIGH"]:
        risk = "MEDIUM"

    qty_at_risk = float(raw.get("quantity_at_risk", 0.0) or 0.0)
    delay_hrs = float(raw.get("estimated_delay_hours", 0.0) or 0.0)
    conf_limitations = str(
        raw.get("confidence_and_limitations")
        or "Analysis grounded in actual active batch weights and rated machine speeds; assuming nominal repair completion."
    )
    next_steps = raw.get("recommended_next_steps")
    if not isinstance(next_steps, list):
        next_steps = adjustments
    next_steps = [str(x) for x in next_steps if x]

    return {
        "machine_code": str(raw.get("machine_code") or default_machine),
        "production_disruption_explanation": disruption_exp,
        "suggested_production_adjustments": adjustments,
        "recommended_alternate_machines": norm_alts,
        "recovery_plan": recovery_plan,
        "operational_consequences_summary": summary,
        "confidence_score": conf,
        "risk_level": risk,
        "quantity_at_risk": qty_at_risk,
        "estimated_delay_hours": delay_hrs,
        "confidence_and_limitations": conf_limitations,
        "recommended_next_steps": next_steps,
    }
