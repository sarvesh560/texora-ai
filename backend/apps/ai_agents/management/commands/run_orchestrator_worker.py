import os
import time
import logging
import signal
import sys
from django.core.management.base import BaseCommand
from django.conf import settings
from apps.ai_agents.autonomous_orchestrator import AutonomousFactoryOrchestrator
from apps.incidents.models import WorkerHeartbeat


logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Runs the Texora AI Autonomous Factory Orchestrator background worker daemon."

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.running = True

    def handle(self, *args, **options):
        self.stdout.write(
            self.style.SUCCESS("=" * 70)
        )
        self.stdout.write(
            self.style.SUCCESS("[TEXORA AI] Starting Autonomous Factory Orchestrator Worker...")
        )
        self.stdout.write(
            self.style.SUCCESS("Autonomous loop: Incident -> Investigation -> Multi-Agent -> What-If -> Approval")
        )
        self.stdout.write(
            self.style.SUCCESS("=" * 70)
        )

        signal.signal(signal.SIGINT, self._handle_exit)
        signal.signal(signal.SIGTERM, self._handle_exit)

        pid = os.getpid()
        lock_file_path = settings.BASE_DIR / "orchestrator_worker.lock"
        try:
            with open(lock_file_path, "w") as f:
                f.write(str(pid))
        except Exception:
            pass

        WorkerHeartbeat.record_heartbeat(
            worker_name="AUTONOMOUS_ORCHESTRATOR",
            process_id=pid,
            status="RUNNING",
        )

        orchestrator = AutonomousFactoryOrchestrator()
        poll_interval = 3.0

        while self.running:
            last_err = ""
            proc_count = 0
            try:
                result = orchestrator.run_cycle()
                proc_count = result.get("processed_count", 0)
                if proc_count > 0:
                    self.stdout.write(
                        self.style.NOTICE(
                            f"[WORKER TICK] Processed {proc_count} active/pending incidents."
                        )
                    )
            except Exception as e:
                last_err = str(e)
                self.stderr.write(self.style.ERROR(f"[WORKER ERROR] Cycle failed: {last_err}"))
                logger.exception("Orchestrator cycle failure")

            WorkerHeartbeat.record_heartbeat(
                worker_name="AUTONOMOUS_ORCHESTRATOR",
                process_id=pid,
                status="DEGRADED" if last_err else "RUNNING",
                last_error=last_err,
                increment_count=proc_count,
            )

            # Sleep in 0.5s increments to respond promptly to shutdown signals
            for _ in range(int(poll_interval * 2)):
                if not self.running:
                    break
                time.sleep(0.5)

        WorkerHeartbeat.record_heartbeat(
            worker_name="AUTONOMOUS_ORCHESTRATOR",
            process_id=pid,
            status="STOPPED",
        )
        try:
            if lock_file_path.exists():
                lock_file_path.unlink()
        except Exception:
            pass

        self.stdout.write(self.style.WARNING("[TEXORA AI] Orchestrator Worker stopped gracefully."))

    def _handle_exit(self, signum, frame):
        self.stdout.write(self.style.WARNING("\nShutdown signal received. Finishing current cycle..."))
        self.running = False
