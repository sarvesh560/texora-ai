import time
import signal
import sys
import logging
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.simulation.engine import SimulationEngine
from apps.simulation.models import SimulationState, InjectedScenario, ScenarioType
from apps.machines.models import Machine

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Runs the Texora AI Autonomous Factory Simulation Engine in foreground/background."

    def add_arguments(self, parser):
        parser.add_argument(
            "--ticks",
            type=int,
            default=0,
            help="Number of ticks to execute (0 for continuous loop until stopped).",
        )
        parser.add_argument(
            "--interval",
            type=float,
            default=3.0,
            help="Interval in seconds between simulation ticks (default: 3.0s).",
        )
        parser.add_argument(
            "--speed",
            type=float,
            default=1.0,
            help="Simulation speed multiplier (default: 1.0x).",
        )
        parser.add_argument(
            "--inject-scenario",
            type=str,
            choices=[c[0] for c in ScenarioType.choices],
            default=None,
            help="Optional scenario to inject upon starting.",
        )
        parser.add_argument(
            "--target-machine",
            type=str,
            default="",
            help="Target machine code for scenario injection (e.g. WEV-AJ-02).",
        )

    def handle(self, *args, **options):
        ticks_limit = options["ticks"]
        interval = options["interval"]
        speed = options["speed"]
        inject_scenario = options["inject_scenario"]
        target_machine = options["target_machine"]

        self.stdout.write(self.style.SUCCESS("=" * 70))
        self.stdout.write(self.style.SUCCESS("  TEXORA AI - AUTONOMOUS FACTORY SIMULATION ENGINE"))
        self.stdout.write(self.style.SUCCESS("=" * 70))
        self.stdout.write(f"  * Tick Interval:    {interval}s")
        self.stdout.write(f"  * Speed Multiplier: {speed}x")
        self.stdout.write(f"  * Target Mode:      {'Finite (' + str(ticks_limit) + ' ticks)' if ticks_limit > 0 else 'Continuous Loop'}")
        self.stdout.write(f"  * Machines Count:   {Machine.objects.filter(is_active=True).count()}")
        self.stdout.write(self.style.SUCCESS("-" * 70))

        if inject_scenario:
            scenario, _ = InjectedScenario.objects.update_or_create(
                scenario_type=inject_scenario,
                target_machine_code=target_machine,
                defaults={
                    "is_active": True,
                    "severity": "HIGH",
                    "description": f"CLI Injected {inject_scenario} on {target_machine or 'Factory'}",
                },
            )
            self.stdout.write(self.style.WARNING(f"  [SCENARIO INJECTED] {scenario}"))

        engine = SimulationEngine()

        if ticks_limit > 0:
            # Discrete finite execution mode
            self.stdout.write(self.style.HTTP_INFO(f"Executing {ticks_limit} discrete ticks synchronously..."))
            for i in range(1, ticks_limit + 1):
                res = engine.run_tick()
                self.stdout.write(
                    f"  [TICK #{res['tick']:04d}] TS: {res['timestamp']} | Updated: {res['machines_updated']} machines | Telemetry: {res['telemetry_recorded']} | Active Scenarios: {res['active_scenarios']}"
                )
                if i < ticks_limit:
                    time.sleep(max(0.1, interval / speed))
            self.stdout.write(self.style.SUCCESS(f"\n[OK] Completed {ticks_limit} simulation ticks successfully."))
            return

        # Continuous background loop mode with PID lock protection
        import os
        from django.conf import settings
        lock_file_path = settings.BASE_DIR / "simulation.lock"
        if lock_file_path.exists():
            try:
                with open(lock_file_path, "r") as f:
                    existing_pid = int(f.read().strip())
                # Check if process is actually running on Windows
                import ctypes
                kernel32 = ctypes.windll.kernel32
                handle = kernel32.OpenProcess(0x1000, False, existing_pid)
                if handle:
                    kernel32.CloseHandle(handle)
                    self.stdout.write(self.style.ERROR(f"Error: Simulation engine is already running under PID {existing_pid}."))
                    return
            except Exception:
                pass

        try:
            with open(lock_file_path, "w") as f:
                f.write(str(os.getpid()))
        except Exception:
            pass

        engine.start(speed_multiplier=speed, tick_interval=interval)
        self.stdout.write(self.style.SUCCESS("Simulation Engine running in background worker. Press Ctrl+C to stop.\n"))

        def handle_exit(signum, frame):
            self.stdout.write(self.style.WARNING("\nStopping simulation engine gracefully..."))
            engine.stop()
            try:
                if lock_file_path.exists():
                    lock_file_path.unlink()
            except Exception:
                pass
            self.stdout.write(self.style.SUCCESS("[OK] Simulation Engine stopped."))
            sys.exit(0)

        signal.signal(signal.SIGINT, handle_exit)
        signal.signal(signal.SIGTERM, handle_exit)

        try:
            while True:
                state = SimulationState.get_state()
                self.stdout.write(
                    f"\r  [RUNNING] Total Ticks: {state.total_ticks_generated} | Last Tick: {state.last_tick_at} | Speed: {state.speed_multiplier}x  ",
                    ending="",
                )
                self.stdout.flush()
                time.sleep(2.0)
        except KeyboardInterrupt:
            handle_exit(None, None)
