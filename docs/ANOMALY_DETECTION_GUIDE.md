# TEXORA AI — AUTONOMOUS ANOMALY DETECTION ENGINE (PHASE 4)

## 1. Architectural Overview

The **Autonomous Anomaly Detection Engine** operates as an independent backend daemon (`run_anomaly_detector`) that continuously evaluates newly persisted industrial telemetry from 25 textile machines across 5 departments.

It detects physical operational abnormalities, aggregates multi-signal evidence, establishes deterministic hypotheses without fabrication, and creates or updates database-backed `FactoryIncident` records.

```
┌────────────────────────┐      ┌─────────────────────────────┐
│ Textile Machinery      │      │ Autonomous Anomaly Detector │
│ (25 Simulated Assets)  │      │ (Independent Daemon / Eval) │
└───────────┬────────────┘      └──────────────┬──────────────┘
            │ Telemetry Ticks                  │ Reads batch > checkpoint
            ▼                                  ▼
┌────────────────────────┐      ┌─────────────────────────────┐
│  MachineTelemetry      │ ──── │  Operating Limit Evaluation │
│  (Database Storage)    │      │  + Temporal Window Analysis │
└────────────────────────┘      └──────────────┬──────────────┘
                                               │
                                ┌──────────────▼──────────────┐
                                │ AnomalyDetection Record     │
                                └──────────────┬──────────────┘
                                               │ Correlate / Deduplicate
                                ┌──────────────▼──────────────┐
                                │ FactoryIncident Lifecycle   │
                                │ (OPEN -> MITIGATING ->      │
                                │  RESOLVED via Hysteresis)   │
                                └──────────────┬──────────────┘
                                               │
                                ┌──────────────▼──────────────┐
                                │ REST API & Flutter Web UI   │
                                │ /api/v1/incidents/summary/  │
                                └─────────────────────────────┘
```

---

## 2. Detection Rules & Machine Operating Limits

Each textile machine has an associated `MachineOperatingLimits` record calibrated to its physical dynamics.

| Metric | Rule Type | Warning Threshold | Critical Threshold | Severity / Impact |
|---|---|---|---|---|
| **Vibration** (`vibration_mms`) | Rolling Window / Upper Limit | $3.0 - 4.5\text{ mm/s}$ | $4.5 - 5.8\text{ mm/s}$ | `CRITICAL` / Mechanical wear, bearing failure |
| **Bearing Temperature** (`temperature_c`) | Upper Limit / Hysteresis | $65.0 - 75.0\text{ }^\circ\text{C}$ | $80.0 - 95.0\text{ }^\circ\text{C}$ | `HIGH` / Thermal runaway, lubrication degradation |
| **Operating Speed** (`speed_rpm`) | Under-Speed Throttling | $< \text{Min Rated RPM}$ | N/A | `MEDIUM` / Thread breakage, tension drop, sliver jam |
| **Active Power** (`power_kw`) | Over-Power Surge | $> \text{Rated Max kW}$ | N/A | `HIGH` / Mechanical load surge, electrical strain |

### Temporal Window & Anti-Spike Protection
- **Isolated Spike Suppression:** A single noisy sensor reading does not immediately trigger an unverified critical alarm. Warning-level signals require sustained deviation or rolling-mean threshold breach.
- **Micro-Noise Rejection:** Spindle speed deviations within $\pm 1.2\%$ of rated RPM are treated as normal operational variance.

---

## 3. Incident Lifecycle & Correlation Rules

```
                   [New Telemetry Exceeds Limits]
                                 │
                                 ▼
                     ┌───────────────────────┐
                     │ Status: OPEN (New)    │
                     └───────────┬───────────┘
                                 │
                 ┌───────────────┴───────────────┐
                 │                               │
       [Repeated Anomaly]              [Action / Inspection]
                 │                               │
                 ▼                               ▼
     ┌───────────────────────┐       ┌───────────────────────┐
     │ Updates Evidence      │       │ Status: INVESTIGATING │
     │ Deduplicates Incident │       │ or MITIGATING         │
     └───────────────────────┘       └───────────┬───────────┘
                                                 │
                                     [Sustained Normal (3 ticks)]
                                                 │
                                                 ▼
                                     ┌───────────────────────┐
                                     │ Status: RESOLVED      │
                                     │ Machine: OPERATIONAL  │
                                     └───────────────────────┘
```

### Deterministic Incident Deduplication
- When an anomaly is detected on machine $M$ for category $C$, the detector queries for an existing active incident (`status` $\in$ `['OPEN', 'INVESTIGATING', 'MITIGATING']`).
- If an active incident exists, the detector **updates** the incident severity (if escalating), updates the summary, and appends the new detection to `evidence_data['anomaly_history']`. **No duplicate active incidents are created.**

### Sustained Normal Recovery (Hysteresis)
- When a machine with an active incident records telemetry strictly within normal limits for **3 consecutive cycles**, the detector:
  1. Sets incident `status = 'RESOLVED'`.
  2. Records timestamp in `resolved_at`.
  3. Writes `resolution_summary` detailing verified temperature/vibration measurements.
  4. Restores `machine.status = 'OPERATIONAL'`.

---

## 4. Worker Management & Startup Commands

### Running Autonomous Detector Worker
```bash
# In backend directory with activated virtual environment
python manage.py run_anomaly_detector --interval 2.5 --batch-size 250
```

### Options:
- `--interval <seconds>`: Polling interval between detection cycles (default: 2.0s).
- `--batch-size <count>`: Maximum telemetry records evaluated per cycle (default: 200).
- `--cycles <n>`: Run $N$ cycles then exit (useful for CI/CD and batch jobs).

### Single-Instance Concurrency Protection
The management command acquires a filesystem lock at `backend/anomaly_detector.lock`. If another instance is running, the secondary worker aborts immediately with an explanatory error, avoiding race conditions.

---

## 5. REST API Reference

| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/incidents/summary/` | `GET` | Aggregated dashboard stats, active incidents list, and recent anomaly timeline. |
| `/api/v1/incidents/` | `GET` | List all incidents with machine and department filtering. |
| `/api/v1/incidents/<id>/` | `GET`, `PATCH` | Retrieve or update incident status, severity, and resolution notes. |
| `/api/v1/incidents/detector-status/` | `GET` | Status of the background detector worker, checkpoint progress, and processing metrics. |
| `/api/v1/incidents/run-eval/` | `POST` | Trigger an immediate manual/autonomous detection evaluation cycle. |
| `/api/v1/anomalies/` | `GET` | List raw anomaly detection records with metric values and confidence scores. |

---

## 6. How Phase 5 Autonomous AI Agents Will Consume Incidents

1. **Trigger on Unresolved Incidents:** The Phase 5 Multi-Agent Orchestrator will query `/api/v1/incidents/?status=OPEN` to pick up newly flagged operational problems.
2. **Deterministic Evidence Handover:** Agents will inspect `incident.evidence_data` (initial trigger reading, historical snapshots, observed thresholds) to formulate diagnostics.
3. **Cross-Domain Correlation:** The Root Cause Agent will correlate machine anomalies with inventory spare parts (`apps.inventory`), maintenance work orders (`apps.maintenance`), and production schedule delays (`apps.production`).
4. **Approval Gate Integration:** If an agent proposes a high-risk mitigation (e.g. machine speed throttling or line stoppage), it will generate an `ApprovalRequest` via `apps.approvals` awaiting operator confirmation.
