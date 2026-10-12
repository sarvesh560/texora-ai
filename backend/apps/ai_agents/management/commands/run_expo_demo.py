import json
from django.core.management.base import BaseCommand
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator


class Command(BaseCommand):
    help = "Executes the Texora AI One-Click PSG Expo Demonstration Scenario (Weaving Loom Loom Vibration Anomaly)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--machine",
            type=str,
            default="WEV-RAP-01",
            help="Machine code to inject anomaly into (default: WEV-RAP-01)",
        )
        parser.add_argument(
            "--provider",
            type=str,
            default=None,
            help="Force specific AI provider (e.g. 'fallback' or 'gemini-3.5-flash')",
        )

    def handle(self, *args, **options):
        machine_code = options["machine"]
        force_provider = options.get("provider")
        self.stdout.write(self.style.SUCCESS("=" * 75))
        self.stdout.write(self.style.SUCCESS(f"[INITIATING] ONE-CLICK EXPO DEMO SCENARIO ON {machine_code}"))
        self.stdout.write(self.style.SUCCESS("PSG College Coimbatore Expo - Texora AI Autonomous Operations"))
        self.stdout.write(self.style.SUCCESS("=" * 75))

        orchestrator = AutonomousFactoryOrchestrator()
        result = orchestrator.execute_expo_demo(
            machine_code=machine_code, force_provider=force_provider
        )

        if not result.get("success"):
            self.stderr.write(self.style.ERROR(f"[ERROR] Demo Execution Failed: {result.get('error')}"))
            return

        self.stdout.write(self.style.NOTICE(f"\n[1] Telemetry Injected: Vibration peak 6.85 mm/s on {machine_code}"))
        self.stdout.write(self.style.NOTICE(f"[2] Incident Created: #{result.get('incident_id')} ({result.get('incident_code')})"))
        self.stdout.write(self.style.NOTICE(f"[3] Workflow Run: {result.get('workflow_run_id')}"))
        self.stdout.write(self.style.NOTICE(f"[4] AI Provider: {result.get('ai_provider')}"))
        self.stdout.write(self.style.NOTICE(f"[5] What-If Scenario: {result.get('scenario_code')}"))
        self.stdout.write(self.style.NOTICE(f"[6] Recommended Strategy: {result.get('recommended_strategy')}"))
        self.stdout.write(self.style.NOTICE(f"[7] Approval Request: #{result.get('approval_request_id')} ({result.get('approval_code')})"))
        self.stdout.write(self.style.NOTICE(f"[8] Status: {result.get('status')}"))

        self.stdout.write(self.style.SUCCESS("\n" + "=" * 75))
        self.stdout.write(self.style.SUCCESS("[OK] AUTONOMOUS PIPELINE COMPLETED UP TO HUMAN APPROVAL GATE"))
        self.stdout.write(self.style.SUCCESS("Review recommendation in Executive Command Center & Manager Approval Inbox."))
        self.stdout.write(self.style.SUCCESS("=" * 75))
