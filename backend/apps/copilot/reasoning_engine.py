"""
Texora AI - Copilot Reasoning & Orchestration Engine (Phase 14)
Extracts factory entities, retrieves bounded domain records via FactoryContextEngine,
re-uses the multi-cloud router (GroqCloud primary, Gemini secondary), grounds all
answers in verified facts, enforces read-only industrial safety, and provides a
deterministic evidence-based fallback when cloud AI is unavailable.
"""

import re
import json
import time
import logging
from typing import Dict, Any, List, Optional, Tuple

from apps.ai_agents.llm_client import (
    MultiProviderRouter,
    LLMResponse,
    PROVENANCE_GROQ_LIVE,
    PROVENANCE_GEMINI_LIVE,
    PROVENANCE_DETERMINISTIC_FALLBACK,
)
from apps.copilot.context_engine import FactoryContextEngine, _sanitize_identifier
from apps.copilot.models import CopilotSession, CopilotMessage, CopilotRole

logger = logging.getLogger(__name__)

# Entity extraction patterns
MACHINE_PATTERN = re.compile(r"\b(SIM-[A-Z]{2,4}-[0-9A-Z]{2,6}|[A-Z]{2,4}-[A-Z]{2,4}-[0-9A-Z]{2,4})\b", re.IGNORECASE)
INCIDENT_PATTERN = re.compile(r"\b(INC-[A-Za-z0-9\-]+)\b", re.IGNORECASE)
TICKET_PATTERN = re.compile(r"\b(MNT-[A-Za-z0-9\-]+)\b", re.IGNORECASE)
ITEM_PATTERN = re.compile(r"\b(SPR-[A-Za-z0-9\-]+|DYE-[A-Za-z0-9\-]+)\b", re.IGNORECASE)
APPROVAL_PATTERN = re.compile(r"\b(APR-[A-Za-z0-9\-]+)\b", re.IGNORECASE)

# Dangerous write action patterns
MUTATION_INTENT_PATTERN = re.compile(
    r"\b(approve|reject|authorize|close incident|resolve incident|shut down|stop machine|emergency stop|"
    r"deduct spare|consume part|start repair|complete repair|modify ticket|change state)\b",
    re.IGNORECASE,
)


class DeterministicCopilotEngine:
    """
    Evidence-based fallback reasoning engine for supported factory queries
    when GroqCloud and Gemini are both unavailable or rate-limited.
    Provides verifiable, factual answers grounded exclusively in DB records.
    """

    @classmethod
    def generate_grounded_response(
        cls,
        user_query: str,
        context: Dict[str, Any],
        active_machine: Optional[str] = None,
        active_incident: Optional[str] = None,
    ) -> Dict[str, Any]:
        q_lower = user_query.lower()

        # Check for mutation / action requests
        if MUTATION_INTENT_PATTERN.search(user_query):
            return {
                "answer": (
                    "Safety Notice: The Factory AI Copilot operates in strict READ-ONLY advisory mode. "
                    "I cannot authorize approvals, close incidents, deduct spare parts, or trigger physical machine controls. "
                    "Please navigate to the Manager Approval Center (Tab 5) or Maintenance Execution Center (Tab 7) "
                    "to perform authorized operations."
                ),
                "facts": ["Copilot permission level: READ-ONLY INDUSTRIAL ADVISORY"],
                "estimates": [],
                "recommendations": [
                    "Use Manager Approval Center to review pending gates",
                    "Use Maintenance Execution Center for work order state transitions",
                ],
                "references": [],
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 1. Machine-Specific Telemetry or Status Query
        if context.get("machine_status"):
            m = context["machine_status"]
            readings = m.get("recent_readings", [])
            latest_reading = readings[0] if readings else {}
            vib = latest_reading.get("vibration_mms", "N/A")
            temp = latest_reading.get("temperature_c", "N/A")
            status = m.get("status", "UNKNOWN")
            health = m.get("current_health_score", 0)
            code = m.get("machine_code") or m.get("code") or "UNKNOWN"
            name = m.get("name", code)

            # Check if user asked "Why" or "What happened"
            if "why" in q_lower or "cause" in q_lower or "happen" in q_lower:
                anoms = context.get("machine_anomalies", [])
                anom_summary = (
                    f"Identified {len(anoms)} recent telemetry deviations. "
                    f"Top anomaly: {anoms[0]['metric_name']} reached {anoms[0]['observed_value']} "
                    f"(expected <= {anoms[0]['expected_threshold']})."
                    if anoms
                    else "No localized anomaly events currently logged for this machine asset."
                )
                answer = (
                    f"Investigation for {code} ({name}): Machine is currently in status '{status}' "
                    f"with health score {health}%. {anom_summary} "
                    f"Latest telemetry shows vibration at {vib} mm/s and temperature at {temp} °C."
                )
            # Check if user asked "What next" or "recommendation"
            elif "next" in q_lower or "recommend" in q_lower or "do" in q_lower or "action" in q_lower:
                strat_list = context.get("recovery_strategies", [])
                rec_strat = strat_list[0].get("recommended_strategy", "Prioritized Inspection & Bearing Replacement") if strat_list else "Perform sensor-guided inspection and verify bearing play."
                answer = (
                    f"Recommended next steps for {code}: Recommended strategy is {rec_strat}. "
                    f"Active work order ticket is {m.get('active_ticket_number') or 'none'} and "
                    f"active incident is {m.get('active_incident_code') or 'none'}."
                )
            else:
                answer = (
                    f"Machine {code} ({name}) is currently {status} with health score {health}%. "
                    f"Latest recorded vibration is {vib} mm/s and temperature is {temp} °C. "
                    f"Operating department: {m.get('department', '')}."
                )

            facts = [
                f"Machine {code} status is {status}",
                f"Health score: {health}%",
                f"Latest vibration: {vib} mm/s, temperature: {temp} °C",
            ]
            estimates = [f"Rated speed: {m.get('rated_speed_rpm', 0)} RPM"]
            recommendations = []
            if m.get("active_incident_code"):
                recommendations.append(f"Review active incident {m['active_incident_code']}")
            if m.get("active_ticket_number"):
                recommendations.append(f"Inspect work order ticket {m['active_ticket_number']}")

            refs = [{"type": "machine", "id": code, "label": f"{code} ({name})"}]
            if m.get("active_incident_code"):
                refs.append({"type": "incident", "id": m["active_incident_code"], "label": m["active_incident_code"]})
            if m.get("active_ticket_number"):
                refs.append({"type": "ticket", "id": m["active_ticket_number"], "label": m["active_ticket_number"]})

            return {
                "answer": answer,
                "facts": facts,
                "estimates": estimates,
                "recommendations": recommendations,
                "references": refs,
                "missing_evidence": "" if readings else "No recent telemetry time-series records available.",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 2. Incident-Specific Query
        if context.get("incident_details"):
            inc = context["incident_details"]
            answer = (
                f"Incident {inc['incident_code']}: Severity {inc['severity']}, Status {inc['status']}. "
                f"Summary: {inc['summary']}. Root cause hypothesis: {inc['root_cause_hypothesis'] or 'Under autonomous evaluation'}. "
                f"Affects machine {inc['machine_code']} in {inc['department']} department."
            )
            facts = [
                f"Incident {inc['incident_code']} severity: {inc['severity']}",
                f"Current status: {inc['status']}",
                f"Root cause hypothesis: {inc['root_cause_hypothesis'] or 'Pending diagnosis'}",
            ]
            refs = [
                {"type": "incident", "id": inc["incident_code"], "label": inc["incident_code"]},
                {"type": "machine", "id": inc["machine_code"], "label": inc["machine_code"]},
            ]
            return {
                "answer": answer,
                "facts": facts,
                "estimates": [f"Category: {inc['category']}"],
                "recommendations": ["Awaiting manager approval or technician dispatch" if inc['status'] != "CLOSED" else "Incident closed and verified"],
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 3. Spare Parts / Inventory Query
        if context.get("inventory_status"):
            items = context["inventory_status"]
            item_summaries = [f"{it['item_code']} ({it['name']}): {it['current_stock']} {it['unit']} in stock (Reorder point: {it['reorder_point']})" for it in items[:3]]
            answer = f"Spare parts inventory check: Found {len(items)} matching stock item(s). " + "; ".join(item_summaries)
            facts = [f"{it['item_code']}: {it['current_stock']} {it['unit']} available" for it in items[:4]]
            refs = [{"type": "inventory", "id": it["item_code"], "label": it["name"]} for it in items[:3]]
            return {
                "answer": answer,
                "facts": facts,
                "estimates": [],
                "recommendations": ["Reorder immediately if current stock is below reorder point"],
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 4. Factory Health Summary Query
        if "factory" in q_lower or "plant" in q_lower or "overview" in q_lower or "summary" in q_lower or "how are we doing" in q_lower:
            f = context.get("factory_summary", {})
            m = f.get("metrics", {})
            answer = (
                f"Factory Health Overview: Operating {m.get('total_machines', 0)} active machines with an average "
                f"health score of {m.get('average_health_score', 0)}%. "
                f"Machine status breakdown: {m.get('operational_machines', 0)} Operational, "
                f"{m.get('warning_machines', 0)} Warning, {m.get('critical_machines', 0)} Critical, "
                f"{m.get('maintenance_machines', 0)} Under Maintenance. "
                f"There are {m.get('active_incidents_count', 0)} active incident(s) and {m.get('pending_approvals_count', 0)} pending manager approval(s)."
            )
            facts = [
                f"Total machines: {m.get('total_machines', 0)}",
                f"Operational: {m.get('operational_machines', 0)}, Critical: {m.get('critical_machines', 0)}, Warning: {m.get('warning_machines', 0)}",
                f"Active incidents: {m.get('active_incidents_count', 0)}",
                f"Pending approvals: {m.get('pending_approvals_count', 0)}",
            ]
            refs = [
                {"type": "incident", "id": inc["incident_code"], "label": f"{inc['incident_code']} ({inc['machine_code']})"}
                for inc in f.get("recent_incidents", [])[:3]
            ]
            return {
                "answer": answer,
                "facts": facts,
                "estimates": [f"Average machine health: {m.get('average_health_score', 0)}%"],
                "recommendations": ["Review critical machines in Digital Twin (Tab 1)", "Process pending gates in Approval Center (Tab 5)"],
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 5. Production Intelligence: Target Query
        if any(w in q_lower for w in ["production target", "today's target", "today's production target", "daily target", "target quantity"]):
            p = context.get("production_overview") or FactoryContextEngine.get_production_overview()
            tot_tgt = p.get("total_target_units", 0)
            tot_done = p.get("total_completed_units", 0)
            prog = p.get("progress_pct", 0)
            active_orders = p.get("active_orders", 0)
            util = p.get("plant_utilization_pct", 0)

            answer = (
                f"Today's Textile Production Target: The plant has a cumulative active target of {tot_tgt:,.0f} units "
                f"across {active_orders} active customer orders. Currently, {tot_done:,.0f} units have been produced "
                f"({prog}% completed). Plant-wide capacity utilization is currently running at {util}%."
            )
            facts = [
                f"Active target: {tot_tgt:,.0f} units",
                f"Completed: {tot_done:,.0f} units ({prog}%)",
                f"Active production orders: {active_orders}",
                f"Overall plant utilization: {util}%",
            ]
            refs = [
                {"type": "order", "id": o["order_number"], "label": f"{o['order_number']} ({o['client_name']})"}
                for o in p.get("at_risk_orders", [])[:2]
            ]
            return {
                "answer": answer,
                "facts": facts,
                "estimates": [f"Progress: {prog}% towards active targets"],
                "recommendations": ["Inspect department throughput in Production Intelligence Workspace (Tab 10)"],
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 6. Production Intelligence: At-Risk Orders & Delivery Deadlines
        if any(w in q_lower for w in ["orders are at risk", "orders at risk", "order at risk", "delivery deadline", "meet our current delivery deadlines", "delivery commitments"]):
            at_risk = context.get("orders_at_risk") or FactoryContextEngine.get_orders_at_risk()
            if at_risk:
                order_items = [
                    f"{o['order_number']} ({o['client_name']}) — Due: {o['due_date']} (Risk: {o['delay_risk_level']}, Est. Delay: +{o['estimated_delay_hours']}h, Spec: {o['spec'][:30]})"
                    for o in at_risk[:3]
                ]
                answer = (
                    f"Delivery Risk Alert: Found {len(at_risk)} customer order(s) currently at high or critical delay risk. "
                    f"Threatened commitments: {'; '.join(order_items)}. "
                    "Meeting all deadlines will require immediate maintenance resolution or rerouting to parallel looms/frames."
                )
                facts = [f"{o['order_number']}: +{o['estimated_delay_hours']}h delay risk ({o['delay_risk_level']})" for o in at_risk[:4]]
                refs = [{"type": "order", "id": o["order_number"], "label": f"{o['order_number']} ({o['client_name']})"} for o in at_risk[:3]]
                recs = [
                    "Reroute affected batches to compatible alternate machines via Production Impact Agent",
                    "Review order schedules in Production Intelligence Workspace (Tab 10)",
                ]
            else:
                answer = "Delivery Deadline Assessment: All active production orders are currently ON SCHEDULE with adequate time buffers. No orders are flagged with HIGH or CRITICAL delay risk."
                facts = ["0 orders currently flagged at critical delay risk"]
                refs = []
                recs = ["Maintain nominal machine speeds and shift allocations"]

            return {
                "answer": answer,
                "facts": facts,
                "estimates": [f"At-risk orders: {len(at_risk)}"],
                "recommendations": recs,
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 7. Production Intelligence: Department Bottlenecks
        if any(w in q_lower for w in ["bottleneck", "which department is the production bottleneck", "overloaded department"]):
            bottlenecks = context.get("production_bottlenecks") or FactoryContextEngine.get_production_bottlenecks()
            if bottlenecks:
                b_summaries = [
                    f"{b['department_code']} ({b['severity']}): {b['primary_cause'][:80]} [Deficit: ~{b['throughput_deficit_per_hr']} units/hr]"
                    for b in bottlenecks[:3]
                ]
                answer = (
                    f"Production Bottleneck Report: Identified {len(bottlenecks)} active operational bottleneck(s). "
                    + " | ".join(b_summaries)
                )
                facts = [f"{b['department_code']}: {b['bottleneck_type']} ({b['severity']})" for b in bottlenecks[:4]]
                refs = [
                    {"type": "department", "id": b["department_code"], "label": f"Dept {b['department_code']} Bottleneck"}
                    for b in bottlenecks[:3]
                ]
            else:
                answer = "Production Bottleneck Report: All 5 manufacturing departments (Spinning, Weaving, Knitting, Dyeing, Finishing) are operating within balanced throughput capacity without active bottlenecks."
                facts = ["No active bottlenecks detected across factory departments"]
                refs = []

            return {
                "answer": answer,
                "facts": facts,
                "estimates": [],
                "recommendations": ["Rebalance batch lot sizes or schedule overtime shifts in affected bays"],
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 8. Production Intelligence: Available Capacity
        if any(w in q_lower for w in ["capacity", "headroom", "available capacity", "how much production capacity", "utilization"]):
            p = context.get("production_overview") or FactoryContextEngine.get_production_overview()
            caps = p.get("department_capacities", [])
            cap_lines = [
                f"{c['department_code']}: {c['utilization_pct']}% utilized ({c['active_machines']}/{c['total_machines']} running, Headroom: ~{c['available_headroom_units']} units/day)"
                for c in caps[:5]
            ]
            answer = (
                f"Plant Production Capacity Status: Overall factory utilization is {p.get('plant_utilization_pct', 0)}%. "
                f"Department capacity headroom: " + "; ".join(cap_lines)
            )
            facts = [f"{c['department_code']}: {c['utilization_pct']}% utilization" for c in caps[:5]]
            refs = [{"type": "department", "id": c["department_code"], "label": f"{c['department_name']} Capacity"} for c in caps[:3]]
            return {
                "answer": answer,
                "facts": facts,
                "estimates": [f"Overall utilization: {p.get('plant_utilization_pct', 0)}%"],
                "recommendations": ["Check available machine slots in Production Intelligence (Tab 10)"],
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 9. Production Intelligence: Machine Failures Impact
        if any(w in q_lower for w in ["machine failure", "machine failures affect", "failures affect production", "downtime affect", "breakdown affect"]):
            impacts = context.get("machine_production_impacts") or FactoryContextEngine.get_machine_production_impact(active_machine)
            if impacts:
                top = impacts[0]
                answer = (
                    f"Production Disruption Analysis: Impairment on {top['machine_code']} ({top['machine_name']}) "
                    f"induces an estimated throughput deficit of ~{top['output_quantity_at_risk']} units "
                    f"(estimated value loss ₹{top['deterministic_loss_inr']:,.2f}) over {top['estimated_downtime_hours']}h downtime. "
                    f"{top['orders_affected_count']} customer order(s) are directly affected (Delay Risk: {top['overall_delay_risk']}). "
                    f"AI Explanation: {top['ai_explanation'][:120]}"
                )
                facts = [
                    f"Machine: {top['machine_code']}",
                    f"Throughput deficit: ~{top['output_quantity_at_risk']} units",
                    f"Loss value: ₹{top['deterministic_loss_inr']:,.2f}",
                    f"Orders affected: {top['orders_affected_count']}",
                ]
                refs = [
                    {"type": "machine", "id": top["machine_code"], "label": f"{top['machine_code']} Breakdown"},
                ]
                recs = top.get("recommendations", []) or ["Reroute active batches to compatible machinery"]
            else:
                answer = "Machinery Impact Evaluation: No critical machine breakdown impact assessments are currently active. All operational machines are running within scheduled capacity."
                facts = ["No active breakdown impact assessments found"]
                refs = []
                recs = ["Continue routine preventive monitoring"]

            return {
                "answer": answer,
                "facts": facts,
                "estimates": [],
                "recommendations": recs,
                "references": refs,
                "missing_evidence": "",
                "is_simulated": True,
                "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
            }

        # 10. Unsupported query under Deterministic Fallback
        return {
            "answer": (
                "Deterministic Copilot Advisory: Cloud AI multi-provider inference is currently offline or rate-limited. "
                "In offline deterministic mode, I can provide grounded reports for: "
                "(1) Specific machine telemetry & status, (2) Active incident diagnoses & root causes, "
                "(3) Spare parts stock levels, (4) Plant-wide health overviews, and (5) Recovery verification signoffs. "
                f"Your query '{user_query[:60]}' could not be matched to an active machine or record in the local database. "
                "Please specify a machine code (e.g. WEV-AJ-02) or incident ID (e.g. INC-2026...)."
            ),
            "facts": [],
            "estimates": [],
            "recommendations": ["Query a specific machine code like WEV-AJ-02 or ask 'Factory health overview'"],
            "references": [],
            "missing_evidence": f"No records found matching query parameters in local database.",
            "is_simulated": True,
            "simulation_disclosure": FactoryContextEngine.SIMULATION_DISCLOSURE,
        }


class CopilotReasoningEngine:
    """
    Main Copilot reasoning orchestrator.
    Manages session context, extracts entities, retrieves grounded evidence,
    calls cloud LLM or fallback, and saves structured messages.
    """

    SYSTEM_PROMPT = """You are the Texora AI Factory Copilot, an industrial intelligence assistant for textile manufacturing plant managers.
Your role is to answer questions using ONLY the provided FACTORY DATABASE CONTEXT.

STRICT INDUSTRIAL SAFETY & GROUNDING RULES:
1. ONLY make claims supported by the provided database context. NEVER hallucinate sensor readings, temperatures, vibration levels, part costs, or dates.
2. Clearly separate your response into:
   - "facts": Exact data points confirmed by DB records.
   - "estimates": Projections, simulations, or AI calculations.
   - "recommendations": Actionable advice for the factory manager.
3. If data is missing or incomplete, explicitly state it in "missing_evidence". Do not invent numbers.
4. You operate in strict READ-ONLY mode. If the user asks you to approve actions, shut down machines, close tickets, or deduct parts, refuse firmly and direct them to the appropriate human UI.
5. All factory data is simulated industrial demonstration data; acknowledge this in "simulation_disclosure".
6. Respond with valid JSON strictly conforming to the requested schema.

RESPONSE SCHEMA:
{
  "answer": "Clear, professional, concise explanation for the manager.",
  "facts": ["Fact 1", "Fact 2"],
  "estimates": ["Estimate 1"],
  "recommendations": ["Recommendation 1"],
  "references": [{"type": "machine|incident|ticket|inventory|approval", "id": "identifier", "label": "Label"}],
  "missing_evidence": "Any missing context, or empty string",
  "is_simulated": true,
  "simulation_disclosure": "Data Notice: Telemetry and maintenance records are simulated industrial demonstration data."
}
"""

    @classmethod
    def process_user_query(cls, session: CopilotSession, user_query: str) -> CopilotMessage:
        """
        Processes a user question within a CopilotSession, retrieving grounded context,
        running multi-provider reasoning (with circuit breaker fallback), and persisting
        the turn to the database.
        """
        start_time = time.time()

        # 1. Persist User Message
        user_msg = CopilotMessage.objects.create(
            session=session,
            role=CopilotRole.USER,
            content=user_query,
            is_simulated=True,
            simulation_disclosure=FactoryContextEngine.SIMULATION_DISCLOSURE,
        )

        # 2. Extract Entities or inherit from session context
        extracted_machine = cls._extract_machine(user_query) or session.active_machine_code
        extracted_incident = cls._extract_incident(user_query) or session.active_incident_code
        extracted_ticket = cls._extract_ticket(user_query)
        extracted_item = cls._extract_item(user_query)

        # Update session active context
        if extracted_machine and extracted_machine != session.active_machine_code:
            session.active_machine_code = extracted_machine
        if extracted_incident and extracted_incident != session.active_incident_code:
            session.active_incident_code = extracted_incident
        session.save(update_fields=["active_machine_code", "active_incident_code", "updated_at"])

        # 3. Retrieve Grounded Context
        context: Dict[str, Any] = {}
        evidence_records: List[Dict[str, Any]] = []

        # Factory summary context
        if any(w in user_query.lower() for w in ["factory", "plant", "overview", "summary", "how are we doing"]):
            fs = FactoryContextEngine.get_factory_health_summary()
            context["factory_summary"] = fs
            evidence_records.append({"type": "factory_summary", "data": fs["metrics"]})

        # Machine context
        if extracted_machine:
            m_status = FactoryContextEngine.get_machine_status_and_telemetry(extracted_machine)
            if m_status:
                context["machine_status"] = m_status
                evidence_records.append({"type": "machine_telemetry", "machine": extracted_machine, "data": m_status})
                # If machine has active incident and none extracted, inherit it
                if m_status.get("active_incident_code") and not extracted_incident:
                    extracted_incident = m_status["active_incident_code"]
                    session.active_incident_code = extracted_incident
                    session.save(update_fields=["active_incident_code"])

            anoms = FactoryContextEngine.get_machine_anomaly_history(extracted_machine)
            if anoms:
                context["machine_anomalies"] = anoms
                evidence_records.append({"type": "anomalies", "count": len(anoms), "top": anoms[:2]})

            impact = FactoryContextEngine.get_production_impact(extracted_machine)
            if impact and "error" not in impact:
                context["production_impact"] = impact

            strats = FactoryContextEngine.get_digital_twin_recovery_strategies(extracted_machine)
            if strats:
                context["recovery_strategies"] = strats

        # Incident context
        if extracted_incident:
            inc = FactoryContextEngine.get_incident_details(extracted_incident)
            if inc:
                context["incident_details"] = inc
                evidence_records.append({"type": "incident", "code": extracted_incident, "data": inc})
                if inc.get("machine_code") and not extracted_machine:
                    extracted_machine = inc["machine_code"]
                    session.active_machine_code = extracted_machine
                    session.save(update_fields=["active_machine_code"])

        # Ticket / Maintenance context
        if extracted_ticket or extracted_machine:
            maint = FactoryContextEngine.get_maintenance_history(
                machine_code=extracted_machine, ticket_number=extracted_ticket
            )
            if maint:
                context["maintenance_history"] = maint
                evidence_records.append({"type": "maintenance_tickets", "count": len(maint)})

        # Inventory context
        if extracted_item or any(w in user_query.lower() for w in ["part", "stock", "bearing", "inventory", "spare"]):
            inv = FactoryContextEngine.get_inventory_status(extracted_item or "SPR")
            if inv:
                context["inventory_status"] = inv
                evidence_records.append({"type": "inventory", "count": len(inv)})

        # Approvals context
        if any(w in user_query.lower() for w in ["approval", "gate", "pending", "manager review"]):
            apps = FactoryContextEngine.get_approval_requests(incident_code=extracted_incident)
            if apps:
                context["approvals"] = apps
                evidence_records.append({"type": "approvals", "count": len(apps)})

        # Verification context
        if any(w in user_query.lower() for w in ["verification", "signoff", "recovered", "post-repair"]):
            ver = FactoryContextEngine.get_recovery_verification_results(extracted_ticket or extracted_machine or "")
            if ver:
                context["verification_results"] = ver
                evidence_records.append({"type": "verification", "data": ver})

        # Production intelligence context
        if any(w in user_query.lower() for w in ["production", "target", "order", "deadline", "bottleneck", "capacity", "utilization", "delay", "commitment", "delivery", "fail"]):
            prod_overview = FactoryContextEngine.get_production_overview()
            context["production_overview"] = prod_overview
            evidence_records.append({"type": "production_overview", "data": prod_overview})

            at_risk = FactoryContextEngine.get_orders_at_risk()
            if at_risk:
                context["orders_at_risk"] = at_risk
                evidence_records.append({"type": "orders_at_risk", "count": len(at_risk)})

            bottlenecks = FactoryContextEngine.get_production_bottlenecks()
            if bottlenecks:
                context["production_bottlenecks"] = bottlenecks
                evidence_records.append({"type": "production_bottlenecks", "count": len(bottlenecks)})

            impacts = FactoryContextEngine.get_machine_production_impact(extracted_machine)
            if impacts:
                context["machine_production_impacts"] = impacts
                evidence_records.append({"type": "machine_production_impacts", "count": len(impacts)})

        # 4. Attempt Cloud AI Reasoning with MultiProviderRouter
        router = MultiProviderRouter()
        user_prompt = f"USER QUERY: {user_query}\n\nACTIVE FOCUSED ENTITIES:\nMachine: {extracted_machine or 'None'}\nIncident: {extracted_incident or 'None'}\n\nRETRIEVED FACTORY EVIDENCE CONTEXT:\n{json.dumps(context, indent=2, default=str)}"

        llm_resp = router.generate_structured(
            system_prompt=cls.SYSTEM_PROMPT,
            user_prompt=user_prompt,
            schema_description="CopilotStructuredReasoningSchema",
        )

        latency = int((time.time() - start_time) * 1000)

        # 5. Check if Cloud AI succeeded with valid structured JSON
        if llm_resp.status == "SUCCESS" and llm_resp.structured_json and "answer" in llm_resp.structured_json:
            parsed = llm_resp.structured_json
            assistant_msg = CopilotMessage.objects.create(
                session=session,
                role=CopilotRole.ASSISTANT,
                content=parsed.get("answer", ""),
                facts=parsed.get("facts", []),
                estimates=parsed.get("estimates", []),
                recommendations=parsed.get("recommendations", []),
                references=parsed.get("references", []),
                evidence_records=evidence_records,
                missing_evidence=parsed.get("missing_evidence", ""),
                is_simulated=True,
                simulation_disclosure=FactoryContextEngine.SIMULATION_DISCLOSURE,
                provider=llm_resp.provider,
                model=llm_resp.model,
                latency_ms=llm_resp.latency_ms or latency,
                reasoning_source=llm_resp.reasoning_source,
            )
            return assistant_msg

        # 6. Cloud AI Unavailable / Circuit Breaker Active -> Engage Deterministic Engine
        logger.info(
            "[CopilotReasoningEngine] Cloud LLM returned %s (%s). Engaging DeterministicCopilotEngine fallback.",
            llm_resp.status,
            llm_resp.error_message[:80],
        )
        det_result = DeterministicCopilotEngine.generate_grounded_response(
            user_query=user_query,
            context=context,
            active_machine=extracted_machine,
            active_incident=extracted_incident,
        )

        assistant_msg = CopilotMessage.objects.create(
            session=session,
            role=CopilotRole.ASSISTANT,
            content=det_result.get("answer", ""),
            facts=det_result.get("facts", []),
            estimates=det_result.get("estimates", []),
            recommendations=det_result.get("recommendations", []),
            references=det_result.get("references", []),
            evidence_records=evidence_records,
            missing_evidence=det_result.get("missing_evidence", ""),
            is_simulated=True,
            simulation_disclosure=FactoryContextEngine.SIMULATION_DISCLOSURE,
            provider="deterministic_fallback",
            model="fallback-rules-v1",
            latency_ms=latency,
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
        )
        return assistant_msg

    @staticmethod
    def _extract_machine(text: str) -> Optional[str]:
        m = MACHINE_PATTERN.search(text)
        return m.group(1).upper() if m else None

    @staticmethod
    def _extract_incident(text: str) -> Optional[str]:
        m = INCIDENT_PATTERN.search(text)
        return m.group(1).upper() if m else None

    @staticmethod
    def _extract_ticket(text: str) -> Optional[str]:
        m = TICKET_PATTERN.search(text)
        return m.group(1).upper() if m else None

    @staticmethod
    def _extract_item(text: str) -> Optional[str]:
        m = ITEM_PATTERN.search(text)
        return m.group(1).upper() if m else None
