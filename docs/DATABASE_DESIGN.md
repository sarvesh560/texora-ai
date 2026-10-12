# Texora AI — Database Design & Entity Architecture

## 1. Domain ERD & Entity Relationships

```text
+-----------------------------------------------------------------------------------+
|                                FACTORY & STRUCTURE                                |
+-----------------------------------------------------------------------------------+
  Factory (1) ──< Department (N) ──< ProductionLine (N) ──< Machine (N)
                                                                 │
                                                                 ├─- 1:1 MachineOperatingLimits
                                                                 ├─- 1:N MachineTelemetry
                                                                 ├─- 1:N MachineStateHistory
                                                                 ├─- 1:N EnergyReading
                                                                 └─- 1:N MaintenanceTicket

+-----------------------------------------------------------------------------------+
|                         PRODUCTION & QUALITY PIPELINE                             |
+-----------------------------------------------------------------------------------+
  ProductionOrder (1) ──< ProductionBatch (N) ──< ProductionOutput (N)
           │                        │
           ├──< ProductionSchedule  ├──< QualityInspection (1) ──< QualityDefect (N)
           └──< ProductionDelay     └──< InventoryTransaction (Spare parts / Dye issues)

+-----------------------------------------------------------------------------------+
|                       AUTONOMOUS AI & INCIDENT ENGINE                             |
+-----------------------------------------------------------------------------------+
  Machine / Sensor ──> AnomalyDetection ──> FactoryIncident (1)
                                                 │
                                                 ├──< AgentExecution (1) ──< AgentDecision (N)
                                                 │         │
                                                 │         └──< AgentAction (Idempotent)
                                                 │                     │
                                                 │                     └── 1:1 ApprovalRequest
                                                 │
                                                 └──< MaintenanceTicket (Auto-dispatched)

+-----------------------------------------------------------------------------------+
|                            ENTERPRISE AUDIT TRAIL                                 |
+-----------------------------------------------------------------------------------+
  AuditLog (Immutable: tracks all machine state transitions, AI decisions & human approvals)
```

---

## 2. Table Specifications by Domain

### A. Factory & Machinery
- **`factories_factory`**: Factory metadata, location, square footage, timezone.
- **`factories_department`**: Spinning, Weaving, Knitting, Dyeing, Finishing departments with supervisors & target efficiency.
- **`factories_productionline`**: Sub-lines within departments.
- **`machines_machinetype`**: Equipment catalog (Rieter Ring Frames, Picanol Air Jet Looms, Mayer & Cie Circular Knitter, Fongs Soft Flow Dyeing, Monforts Stenter).
- **`machines_machine`**: Assets with code, status, rated RPM, rated capacity, current health score (0-100).
- **`machines_machineoperatinglimits`**: Thermal, vibration, RPM, power, and utilization threshold baselines.
- **`machines_machinetelemetry`**: Time-series sensor logs (temperature, vibration, speed, power, utilization, output rate).
- **`machines_machinestatehistory`**: Audit log of operational state transitions.

### B. Production & Manufacturing
- **`production_productionorder`**: Customer orders with fabric/yarn specs, target vs completed quantities, deadlines.
- **`production_productionbatch`**: Work-in-progress runs mapped to assigned machinery.
- **`production_productionschedule`**: Machine assignments across 3 daily factory shifts.
- **`production_productionoutput`**: Periodic output telemetry recordings.
- **`production_productiondelay`**: Bottleneck event tracking with estimated impact minutes.

### C. Maintenance & Asset Health
- **`maintenance_maintenanceticket`**: Auto-generated or manual maintenance tickets with priority, root cause, parts cost, and incident correlation.
- **`maintenance_maintenanceactivity`**: Granular repair and diagnostic steps.
- **`maintenance_maintenancehistory`**: Historical service ledger with downtime calculations.

### D. Quality, Inventory & Energy
- **`quality_qualityinspection`**: Batch test results (sample size, pass/fail status, quality score).
- **`quality_qualitydefect`**: Textile defects (Yarn unevenness, neps, missing picks, barre effect, shade variation, dropped stitches).
- **`inventory_inventoryitem`**: Spare bearings, seals, needles, raw cotton bales, dyes, chemicals with reorder points.
- **`inventory_inventorytransaction`**: Stock movements, issues, receipts, and AI reservations.
- **`inventory_sparepartrequirement`**: Machine-to-part maintenance dependency matrix.
- **`energy_energyreading`**: Sub-metered active power (kW), energy (kWh), power factor, voltage, peak demand, and carbon footprint.

### E. Autonomous AI & Governance
- **`incidents_factoryincident`**: Operational issues flagged with severity, root cause hypothesis, and evidence JSON.
- **`incidents_anomalydetection`**: High-confidence anomaly scores from threshold or ML models.
- **`ai_agents_agentdefinition`**: Registered AI agents, model assignments, and whitelisted backend tool permissions.
- **`ai_agents_agentexecution`**: Execution run records with token count, latency, and context payloads.
- **`ai_agents_agentdecision`**: Structured agent verdicts, risk levels, and confidence scores.
- **`ai_agents_agentaction`**: Idempotent tool executions (`idempotency_key` prevents duplicates).
- **`approvals_approvalrequest`**: Human-in-the-loop approval gate for high-risk actions.
- **`audit_logs_auditlog`**: System-wide immutable audit trail.
