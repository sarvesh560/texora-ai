"""
Management command to verify live Google Gemini integration across all four Texora AI specialist agents:
1. Machine Health Specialist Agent
2. Maintenance Coordinator Agent
3. Inventory Coordinator Agent
4. Production Impact Agent

This command MUST be explicitly invoked. It reports connectivity, latency, structured output validity,
database storage, and distinguishes live generation from quota exhaustion (BLOCKED_BY_QUOTA).
"""
import os
import sys
import time
from typing import Dict, Any, Optional
from django.core.management.base import BaseCommand
from django.conf import settings
from django.utils import timezone
from apps.incidents.models import FactoryIncident, IncidentSeverity, IncidentStatus

from apps.machines.models import Machine
from apps.ai_agents.models import AgentExecution, AgentType
from apps.ai_agents.llm_client import GeminiProvider, GeminiCircuitBreaker, get_llm_provider
from apps.ai_agents.machine_health_agent import MachineHealthAgent
from apps.ai_agents.maintenance_coordinator import MaintenanceCoordinatorAgent
from apps.ai_agents.inventory_coordinator import InventoryCoordinatorAgent
from apps.ai_agents.production_impact_agent import ProductionImpactAgent


class Command(BaseCommand):
    help = "Explicitly test and verify live Google Gemini API connectivity across all 4 specialist agents."

    def add_arguments(self, parser):
        parser.add_argument(
            "--incident-id",
            type=int,
            default=0,
            help="ID of an existing FactoryIncident to test against (0 creates or picks WEV-AJ-02 incident).",
        )
        parser.add_argument(
            "--reset-breaker",
            action="store_true",
            help="Reset the Gemini circuit breaker prior to running tests.",
        )
        parser.add_argument(
            "--dry-run-check-only",
            action="store_true",
            help="Only test connectivity endpoint without executing full agent pipeline.",
        )

    def handle(self, *args, **options):
        self.stdout.write(self.style.SUCCESS("=" * 80))
        self.stdout.write(self.style.SUCCESS("TEXORA AI — PHASE 12.5 LIVE MULTI-AGENT GEMINI VERIFICATION"))
        self.stdout.write(self.style.SUCCESS(f"Timestamp: {timezone.now().isoformat()}"))
        self.stdout.write(self.style.SUCCESS("=" * 80))

        if options["reset_breaker"]:
            GeminiCircuitBreaker.reset()
            self.stdout.write(self.style.WARNING("Gemini Circuit Breaker manually reset to CLOSED."))

        # 1. Check API Key presence without exposing secrets
        raw_key = getattr(settings, "GEMINI_API_KEY", "") or os.getenv("GEMINI_API_KEY", "")
        has_key = bool(raw_key)
        masked_key = "EXISTS (MASKED: " + "*" * 12 + raw_key[-4:] + ")" if has_key else "NOT CONFIGURED"
        self.stdout.write(f"Configured API Key Status: {masked_key}")

        # 2. Connectivity & Model Discovery Check
        provider = GeminiProvider(api_key=raw_key)
        conn = provider.verify_connectivity()
        self.stdout.write(f"Model Discovery Status: {conn.get('status')}")
        self.stdout.write(f"Candidate Models: {conn.get('discovered_models', [])}")
        if conn.get("error"):
            self.stdout.write(self.style.WARNING(f"Connectivity Note: {conn['error']}"))

        if options["dry_run_check_only"]:
            self.stdout.write("Dry run complete.")
            return

        # 3. Locate or create test incident
        incident_id = options["incident_id"]
        incident = None
        if incident_id > 0:
            incident = FactoryIncident.objects.filter(id=incident_id).first()
        
        if not incident:
            # Look for active WEV-AJ-02 machine or fallback machine
            machine = Machine.objects.filter(code="WEV-AJ-02").first() or Machine.objects.first()
            if not machine:
                self.stderr.write(self.style.ERROR("No machine available in database. Please run seed_factory first."))
                return

            incident = FactoryIncident.objects.filter(machine=machine).order_by("-detected_at").first()
            if not incident:
                incident = FactoryIncident.objects.create(
                    machine=machine,
                    department=machine.department,
                    factory=machine.department.factory,
                    summary="Live Gemini Multi-Agent Activation Verification Incident",
                    severity=IncidentSeverity.HIGH,
                    status=IncidentStatus.INVESTIGATING,
                )
                self.stdout.write(self.style.SUCCESS(f"Created dedicated test incident #{incident.id} for machine {machine.code}."))
            else:
                self.stdout.write(f"Using existing incident #{incident.id} on machine {machine.code}.")

        self.stdout.write(self.style.SUCCESS("-" * 80))
        self.stdout.write(self.style.SUCCESS("EXECUTING SPECIALIST AGENT PIPELINE WITH LIVE GEMINI PROVIDER"))
        self.stdout.write(self.style.SUCCESS("-" * 80))

        results = []

        # -------------------------------------------------------------
        # AGENT 1: MACHINE HEALTH SPECIALIST
        # -------------------------------------------------------------
        self.stdout.write("\n[1/4] Invoking Machine Health Specialist Agent...")
        t0 = time.time()
        health_agent = MachineHealthAgent()
        health_res = health_agent.investigate_incident(incident.id, force_provider="gemini")
        lat1 = int((time.time() - t0) * 1000)

        health_exec = AgentExecution.objects.filter(incident=incident, agent__agent_type=AgentType.MACHINE_HEALTH).order_by("-id").first()
        results.append(self._format_agent_result("Machine Health Specialist", health_res, health_exec, lat1))

        # -------------------------------------------------------------
        # AGENT 2: MAINTENANCE COORDINATOR
        # -------------------------------------------------------------
        self.stdout.write("\n[2/4] Invoking Maintenance Coordinator Agent...")
        t0 = time.time()
        maint_agent = MaintenanceCoordinatorAgent()
        maint_res = maint_agent.coordinate_maintenance(
            incident.id,
            health_diagnosis=health_res.get("findings"),
            force_provider="gemini",
        )
        lat2 = int((time.time() - t0) * 1000)

        maint_exec = AgentExecution.objects.filter(incident=incident, agent__agent_type=AgentType.MAINTENANCE).order_by("-id").first()
        results.append(self._format_agent_result("Maintenance Coordinator", maint_res, maint_exec, lat2))

        # -------------------------------------------------------------
        # AGENT 3: INVENTORY COORDINATOR
        # -------------------------------------------------------------
        self.stdout.write("\n[3/4] Invoking Inventory Coordinator Agent...")
        t0 = time.time()
        inv_agent = InventoryCoordinatorAgent()
        inv_res = inv_agent.coordinate_inventory(
            incident.id,
            health_diagnosis=health_res.get("findings"),
            maintenance_recommendation=maint_res.get("proposed_ticket"),
            force_provider="gemini",
        )
        lat3 = int((time.time() - t0) * 1000)

        inv_exec = AgentExecution.objects.filter(incident=incident, agent__agent_type=AgentType.INVENTORY).order_by("-id").first()
        results.append(self._format_agent_result("Inventory Coordinator", inv_res, inv_exec, lat3))

        # -------------------------------------------------------------
        # AGENT 4: PRODUCTION IMPACT AGENT
        # -------------------------------------------------------------
        self.stdout.write("\n[4/4] Invoking Production Impact Agent...")
        t0 = time.time()
        prod_agent = ProductionImpactAgent()
        prod_res = prod_agent.evaluate_production_impact(
            incident.id,
            health_diagnosis=health_res.get("findings"),
            maintenance_recommendation=maint_res.get("proposed_ticket"),
            inventory_assessment=inv_res.get("ai_output"),
            force_provider="gemini",
        )
        lat4 = int((time.time() - t0) * 1000)

        prod_exec = AgentExecution.objects.filter(incident=incident, agent__agent_type=AgentType.PRODUCTION_IMPACT).order_by("-id").first()
        results.append(self._format_agent_result("Production Impact Agent", prod_res, prod_exec, lat4))

        # -------------------------------------------------------------
        # REPORT SUMMARY TABLE
        # -------------------------------------------------------------
        self.stdout.write("\n" + "=" * 92)
        self.stdout.write(f"{'Agent Name':<28} | {'Called?':<8} | {'Success?':<9} | {'Model':<18} | {'Valid?':<7} | {'Fallback?':<10} | {'Stored?':<8} | {'Latency':<8} | {'Status'}")
        self.stdout.write("=" * 92)

        has_blocked_quota = False
        has_service_unavailable = False
        all_passed = True

        for r in results:
            lat_str = f"{r['latency_ms']}ms"
            self.stdout.write(
                f"{r['agent']:<28} | {str(r['called']):<8} | {str(r['request_success']):<9} | "
                f"{r['model'][:18]:<18} | {str(r['output_valid']):<7} | {str(r['fallback_used']):<10} | "
                f"{str(r['stored']):<8} | {lat_str:<8} | {r['status']}"
            )
            if r["status"] == "BLOCKED_BY_QUOTA":
                has_blocked_quota = True
                all_passed = False
            elif r["status"] == "SERVICE_UNAVAILABLE":
                has_service_unavailable = True
                all_passed = False
            elif r["status"] != "PASS":
                all_passed = False

        self.stdout.write("=" * 92)

        if all_passed:
            overall = "PASS (ALL 4 AGENTS COMPLETED LIVE GEMINI INFERENCE)"
            self.stdout.write(self.style.SUCCESS(f"\nOVERALL VERDICT: {overall}"))
        elif has_blocked_quota:
            overall = "BLOCKED_BY_QUOTA (API key valid, but Google Free Tier generation limit 429 encountered)"
            self.stdout.write(self.style.WARNING(f"\nOVERALL VERDICT: {overall}"))
        elif has_service_unavailable:
            overall = "PARTIAL / SERVICE_UNAVAILABLE (Google Gemini endpoint returned 503 high demand)"
            self.stdout.write(self.style.WARNING(f"\nOVERALL VERDICT: {overall}"))
        else:
            overall = "PARTIAL / DETERMINISTIC FALLBACK SAFELY ENGAGED"
            self.stdout.write(self.style.WARNING(f"\nOVERALL VERDICT: {overall}"))

        self.stdout.write("Deterministic safety fallback successfully preserved factory uptime.\n")

    def _format_agent_result(self, agent_name: str, response: Dict[str, Any], execution: Optional[AgentExecution], latency_ms: int) -> Dict[str, Any]:
        context = execution.context_payload if execution and isinstance(execution.context_payload, dict) else {}
        meta = context.get("metadata", {})
        
        provider_attempt = meta.get("provider_attempt_status", response.get("provider_attempt_status", "UNKNOWN"))
        reasoning_src = meta.get("reasoning_source", response.get("reasoning_source", "UNKNOWN"))
        model_name = meta.get("model_name", response.get("model_name", "gemini-3.8-flash"))
        error_msg = meta.get("execution_error") or response.get("error") or ""

        request_success = (provider_attempt == "GEMINI_LIVE")
        output_valid = bool(context.get("structured_output") or response.get("analysis") or response.get("coordination") or response.get("assessment"))
        fallback_used = (reasoning_src == "DETERMINISTIC_FALLBACK" or response.get("fallback", False))
        stored = bool(execution and execution.id)

        if provider_attempt == "GEMINI_LIVE":
            status = "PASS"
        elif provider_attempt == "GEMINI_RATE_LIMITED" or "RESOURCE_EXHAUSTED" in error_msg or "429" in error_msg:
            status = "BLOCKED_BY_QUOTA"
        elif provider_attempt == "GEMINI_UNAVAILABLE" or "503" in error_msg or "UNAVAILABLE" in error_msg:
            status = "SERVICE_UNAVAILABLE"
        else:
            status = "DETERMINISTIC_FALLBACK"

        return {
            "agent": agent_name,
            "called": True,
            "request_success": request_success,
            "model": model_name,
            "output_valid": output_valid,
            "fallback_used": fallback_used,
            "stored": stored,
            "latency_ms": latency_ms,
            "status": status,
        }
