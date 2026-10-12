"""
Django Management Command to run the Autonomous Machine Health Specialist AI Agent Daemon.
Continuously investigates unhandled machine health incidents, runs evidence pipelines, and proposes actions.
"""
import os
import sys
import time
import signal
import logging
from pathlib import Path
from django.core.management.base import BaseCommand
from django.conf import settings
from django.utils import timezone
from apps.ai_agents.machine_health_agent import MachineHealthAgent

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Runs the Autonomous Machine Health Specialist AI Agent background worker."

    def add_arguments(self, parser):
        parser.add_argument(
            "--interval",
            type=float,
            default=3.0,
            help="Polling interval in seconds between investigation cycles (default: 3.0s).",
        )
        parser.add_argument(
            "--cycles",
            type=int,
            default=0,
            help="Number of cycles to run before exiting (0 for continuous loop).",
        )
        parser.add_argument(
            "--provider",
            type=str,
            default="",
            help="Override LLM provider ('gemini', 'openai', 'mock').",
        )

    def handle(self, *args, **options):
        interval = options["interval"]
        cycles_to_run = options["cycles"]
        provider_override = options["provider"]

        lock_file_path = Path(settings.BASE_DIR) / "machine_health_agent.lock"
        if not self._acquire_lock(lock_file_path):
            self.stderr.write(
                self.style.ERROR(
                    f"Another Machine Health Agent instance is already active (Lockfile: {lock_file_path}). Aborting."
                )
            )
            return

        self.stdout.write(self.style.SUCCESS("=" * 65))
        self.stdout.write(self.style.SUCCESS("TEXORA AI — AUTONOMOUS MACHINE HEALTH SPECIALIST AGENT"))
        self.stdout.write(self.style.SUCCESS(f"Started At: {timezone.now().isoformat()}"))
        self.stdout.write(self.style.SUCCESS(f"Poll Interval: {interval}s | Provider Override: {provider_override or 'ENV default'}"))
        self.stdout.write(self.style.SUCCESS("=" * 65))

        # Setup graceful shutdown
        shutdown_requested = False

        def signal_handler(signum, frame):
            nonlocal shutdown_requested
            shutdown_requested = True
            self.stdout.write(self.style.WARNING("\nShutdown signal received. Exiting gracefully..."))

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        agent = MachineHealthAgent()
        if provider_override:
            from apps.ai_agents.llm_client import get_llm_provider
            agent.provider = get_llm_provider(force_provider=provider_override)

        cycle_count = 0

        try:
            while not shutdown_requested:
                cycle_count += 1
                try:
                    res = agent.run_cycle()
                    if res.get("investigated_count", 0) > 0:
                        self.stdout.write(
                            self.style.SUCCESS(
                                f"[Cycle #{cycle_count}] Investigated {res['investigated_count']} incidents "
                                f"(Pending found: {res['pending_found']})"
                            )
                        )
                except Exception as exc:
                    logger.exception("Error in agent cycle #%d: %s", cycle_count, exc)
                    self.stderr.write(self.style.ERROR(f"Error in cycle #{cycle_count}: {exc}"))

                if cycles_to_run > 0 and cycle_count >= cycles_to_run:
                    self.stdout.write(self.style.SUCCESS(f"Completed target {cycles_to_run} cycles. Terminating."))
                    break

                time.sleep(interval)

        finally:
            self._release_lock(lock_file_path)
            self.stdout.write(self.style.SUCCESS("Machine Health Agent worker stopped cleanly."))

    def _acquire_lock(self, lock_file: Path) -> bool:
        """Simple PID file lock to prevent duplicate concurrent worker processes."""
        try:
            if lock_file.exists():
                try:
                    old_pid = int(lock_file.read_text().strip())
                    # Check if process is actually running (Windows-compatible check)
                    import ctypes
                    kernel32 = ctypes.windll.kernel32
                    PROCESS_QUERY_INFORMATION = 0x0400
                    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION, False, old_pid)
                    if handle != 0:
                        kernel32.CloseHandle(handle)
                        return False  # Process is actively running
                except (ValueError, OSError, AttributeError):
                    pass
                lock_file.unlink(missing_ok=True)

            lock_file.write_text(str(os.getpid()))
            return True
        except Exception as exc:
            logger.warning("Could not acquire lock: %s", exc)
            return True

    def _release_lock(self, lock_file: Path):
        """Removes the PID file lock."""
        try:
            if lock_file.exists():
                lock_file.unlink(missing_ok=True)
        except Exception:
            pass
