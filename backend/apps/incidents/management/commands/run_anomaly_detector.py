import os
import sys
import time
import signal
import logging
from django.core.management.base import BaseCommand
from django.conf import settings
from django.utils import timezone

from apps.incidents.detector import AnomalyDetector
from apps.incidents.models import DetectionCheckpoint, FactoryIncident, AnomalyDetection

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Runs the Texora AI Autonomous Anomaly Detection Engine in background/foreground."

    def add_arguments(self, parser):
        parser.add_argument(
            "--cycles",
            type=int,
            default=0,
            help="Number of detection cycles to execute (0 for continuous monitoring).",
        )
        parser.add_argument(
            "--interval",
            type=float,
            default=2.0,
            help="Interval in seconds between evaluation cycles (default: 2.0s).",
        )
        parser.add_argument(
            "--batch-size",
            type=int,
            default=100,
            help="Maximum number of new telemetry records to evaluate per cycle.",
        )

    def handle(self, *args, **options):
        cycles_limit = options["cycles"]
        interval = options["interval"]
        batch_size = options["batch_size"]

        self.stdout.write(self.style.SUCCESS("=" * 75))
        self.stdout.write(self.style.SUCCESS("  TEXORA AI — AUTONOMOUS ANOMALY DETECTION ENGINE"))
        self.stdout.write(self.style.SUCCESS("=" * 75))
        self.stdout.write(f"  * Mode:             {'Finite (' + str(cycles_limit) + ' cycles)' if cycles_limit > 0 else 'Continuous Background Monitoring'}")
        self.stdout.write(f"  * Check Interval:   {interval}s")
        self.stdout.write(f"  * Batch Size:       {batch_size} records/cycle")

        checkpoint = DetectionCheckpoint.get_checkpoint()
        self.stdout.write(f"  * Checkpoint ID:    #{checkpoint.last_processed_telemetry_id}")
        self.stdout.write(f"  * Active Incidents: {FactoryIncident.objects.filter(status__in=['OPEN', 'INVESTIGATING']).count()}")
        self.stdout.write(self.style.SUCCESS("-" * 75))

        detector = AnomalyDetector()

        if cycles_limit > 0:
            # Discrete finite execution mode
            self.stdout.write(self.style.HTTP_INFO(f"Executing {cycles_limit} discrete detection cycles..."))
            for i in range(1, cycles_limit + 1):
                res = detector.run_cycle(batch_size=batch_size)
                self.stdout.write(
                    f"  [CYCLE #{i:03d}] Evaluated: {res['evaluated_records']} records | Anomalies: {res['anomalies_detected']} | Incidents Created: {res['incidents_created']} | Updated: {res['incidents_updated']} | Resolved: {res['incidents_resolved']} | Last ID: #{res['checkpoint_last_id']}"
                )
                if i < cycles_limit:
                    time.sleep(interval)
            self.stdout.write(self.style.SUCCESS(f"\n[OK] Completed {cycles_limit} detection cycles successfully."))
            return

        # Continuous background loop mode with PID lock protection
        lock_file_path = settings.BASE_DIR / "anomaly_detector.lock"
        if lock_file_path.exists():
            try:
                with open(lock_file_path, "r") as f:
                    existing_pid = int(f.read().strip())
                import ctypes
                kernel32 = ctypes.windll.kernel32
                handle = kernel32.OpenProcess(0x1000, False, existing_pid)
                if handle:
                    kernel32.CloseHandle(handle)
                    self.stdout.write(self.style.ERROR(f"Error: Anomaly detector is already running under PID {existing_pid}."))
                    return
            except Exception:
                pass

        try:
            with open(lock_file_path, "w") as f:
                f.write(str(os.getpid()))
        except Exception:
            pass

        detector.start(poll_interval=interval)
        self.stdout.write(self.style.SUCCESS("Anomaly Detection worker running. Press Ctrl+C to stop.\n"))

        from apps.incidents.models import WorkerHeartbeat

        WorkerHeartbeat.record_heartbeat(
            worker_name="ANOMALY_DETECTOR",
            process_id=os.getpid(),
            status="RUNNING",
        )

        def handle_exit(signum, frame):
            self.stdout.write(self.style.WARNING("\nStopping anomaly detection engine gracefully..."))
            detector.stop()
            try:
                WorkerHeartbeat.record_heartbeat(
                    worker_name="ANOMALY_DETECTOR",
                    process_id=os.getpid(),
                    status="STOPPED",
                )
                if lock_file_path.exists():
                    lock_file_path.unlink()
            except Exception:
                pass
            self.stdout.write(self.style.SUCCESS("[OK] Anomaly Detection Engine stopped."))
            sys.exit(0)

        signal.signal(signal.SIGINT, handle_exit)
        signal.signal(signal.SIGTERM, handle_exit)

        try:
            while True:
                cp = DetectionCheckpoint.get_checkpoint()
                active_inc_count = FactoryIncident.objects.filter(status__in=["OPEN", "INVESTIGATING"]).count()
                WorkerHeartbeat.record_heartbeat(
                    worker_name="ANOMALY_DETECTOR",
                    process_id=os.getpid(),
                    status="RUNNING",
                    metrics={
                        "total_telemetry_processed": cp.total_telemetry_processed,
                        "total_anomalies_detected": cp.total_anomalies_detected,
                        "last_telemetry_id": cp.last_processed_telemetry_id,
                        "active_incidents": active_inc_count,
                    },
                )
                self.stdout.write(
                    f"\r  [MONITORING] Telemetry Evaluated: {cp.total_telemetry_processed} | Anomalies: {cp.total_anomalies_detected} | Active Incidents: {active_inc_count} | Last ID: #{cp.last_processed_telemetry_id}  ",
                    ending="",
                )
                self.stdout.flush()
                time.sleep(2.0)
        except KeyboardInterrupt:
            handle_exit(None, None)
