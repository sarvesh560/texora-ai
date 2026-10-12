# TEXORA AI — AUTONOMOUS AI AGENT ARCHITECTURE (PHASE 5)

## 1. Architectural Overview

Phase 5 introduces the first genuine **Autonomous AI Agent**: the **Machine Health Specialist Agent**.

The agent operates as a specialized reliability engineer in an industrial closed loop:
1. Continuously monitors newly detected `FactoryIncident` records created by Phase 4.
2. Interrogates multi-domain database evidence using 7 validated read-only tools.
3. Invokes configured LLM providers (Google Gemini / OpenAI / Anthropic / Mock) with strict JSON schema constraints.
4. Generates structured engineering hypotheses, distinguishes verified sensor facts from speculative failure modes, and estimates downtime risk.
5. Proposes operational actions through an immutable **Human Approval Gate** (`apps.approvals.models.ApprovalRequest`).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       TEXORA AI AGENT REASONING PIPELINE                     │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                         [New Incident: Status=OPEN]
                                      │
                                      ▼
                   ┌──────────────────────────────────────┐
                   │ Machine Health Specialist Agent      │
                   │ (Independent Autonomous Daemon)      │
                   └──────────────────┬───────────────────┘
                                      │
                 ┌────────────────────┴────────────────────┐
                 │ 7 Validated Read-Only Tools (ORM)       │
                 │ 1. get_machine_details                  │
                 │ 2. get_recent_machine_telemetry         │
                 │ 3. get_machine_operating_limits         │
                 │ 4. get_machine_maintenance_history      │
                 │ 5. get_active_machine_incidents         │
                 │ 6. get_affected_production_orders       │
                 │ 7. get_relevant_spare_parts             │
                 └────────────────────┬────────────────────┘
                                      │ Structured Evidence Payload
                                      ▼
                   ┌──────────────────────────────────────┐
                   │ LLM Inference Layer                  │
                   │ (Gemini 2.5 Flash / GPT-4o / Mock)   │
                   └──────────────────┬───────────────────┘
                                      │ Validated JSON Schema Response
                                      ▼
                   ┌──────────────────────────────────────┐
                   │ Persistence Layer                    │
                   │ • AgentExecution (Tokens, Latency)   │
                   │ • AgentDecision (Root Cause, Score)  │
                   │ • FactoryIncident (Updated Evidence) │
                   └──────────────────┬───────────────────┘
                                      │
                                      ▼
                   ┌──────────────────────────────────────┐
                   │ Action Safety Gate                   │
                   │ • AgentAction: PENDING_APPROVAL      │
                   │ • ApprovalRequest: PENDING           │
                   └──────────────────┬───────────────────┘
                                      │
                              [Manager Decision]
                         ┌────────────┴────────────┐
                         │                         │
                    [Approved]                [Rejected]
                         │                         │
                         ▼                         ▼
         ┌──────────────────────────────┐  ┌───────────────┐
         │ Real MaintenanceTicket       │  │ Action        │
         │ Incident: MITIGATING         │  │ CANCELLED     │
         │ Immutable AuditLog Entry     │  │ Audit Logged  │
         └──────────────────────────────┘  └───────────────┘
```

---

## 2. Validated Read-Only Domain Tools (`apps/ai_agents/tools.py`)

All tools query actual Django ORM models and strictly disallow arbitrary SQL or Python code execution.

| Tool Name | Parameters | Data Returned | Source Model |
|---|---|---|---|
| `get_machine_details` | `machine_id_or_code` | Machine name, code, dept, rated RPM, health score, manufacturer, model | `apps.machines.models.Machine` |
| `get_recent_machine_telemetry` | `machine_id_or_code`, `limit=20` | High-frequency time-series (temp, vibration, RPM, kW, status) | `apps.machines.models.MachineTelemetry` |
| `get_machine_operating_limits` | `machine_id_or_code` | Warning and critical vibration, temperature, speed limits | `apps.machines.models.MachineOperatingLimits` |
| `get_machine_maintenance_history` | `machine_id_or_code`, `limit=10` | Past work orders, failure categories, technician notes | `apps.maintenance.models.MaintenanceTicket` |
| `get_active_machine_incidents` | `machine_id_or_code` | Active open incidents, severity, evidence data | `apps.incidents.models.FactoryIncident` |
| `get_affected_production_orders` | `machine_id_or_code` | Running/staged batches, client orders, fabric specs, due dates | `apps.production.models.ProductionBatch` |
| `get_relevant_spare_parts` | `machine_id_or_code` | Warehouse spare parts stock, reorder thresholds, shelf locations | `apps.inventory.models.InventoryItem` |

---

## 3. Structured Output & Semantic Distinction

The agent strictly structures its output to avoid hallucinations and maintain verifiable engineering rigor:

```json
{
  "incident_id": 18,
  "machine_code": "WEV-AJ-02",
  "observed_abnormal_conditions": [
    "Main drive shaft vibration elevated above critical limit (6.44 mm/s vs 5.8 mm/s threshold)"
  ],
  "verified_sensor_facts": [
    "Vibration amplitude: 6.44 mm/s RMS",
    "Operating speed: 850 RPM (Nominal)",
    "Active electrical power: 48.2 kW"
  ],
  "possible_root_causes": [
    {
      "hypothesis": "Drive shaft rolling element bearing cage deterioration or race flaking",
      "likelihood": "HIGH",
      "confidence_score": 92.5
    }
  ],
  "missing_information": [
    "Lubrication grease particulate analysis",
    "Ultrasonic bearing acoustic signature"
  ],
  "recommended_maintenance_checks": [
    "Inspect drive end bearing 6204-2RS for mechanical play and flaking",
    "Verify belt tension and pulley alignment"
  ],
  "production_impact_considerations": [
    "Active batch BATCH-WEV-DENIM-01 at risk of fabric streak defects",
    "Estimated repair downtime: 1.5 hours"
  ],
  "severity_assessment": "CRITICAL",
  "confidence_explanation": "Vibration levels are 1.82x critical threshold with sustained high RMS while motor current is stable, strongly pointing to mechanical bearing flaking.",
  "suggested_next_actions": [
    {
      "action_type": "CREATE_MAINTENANCE_DRAFT",
      "description": "Create priority maintenance ticket for Loom Drive Bearing inspection",
      "requires_human_approval": true,
      "payload": {
        "priority": "HIGH",
        "fault_category": "MECHANICAL_BEARING",
        "estimated_hours": 1.5
      }
    }
  ]
}
```

---

## 4. Action Safety & Human-in-the-Loop Approval Workflow

- **No Self-Execution:** Agents cannot execute write operations against machinery or approve their own proposals.
- **`ApprovalRequest` Generation:** When an agent proposes a maintenance ticket or spare parts reservation, an `ApprovalRequest` is created with status `PENDING`.
- **Authorized Execution:** When an operations manager approves the request via `POST /api/v1/approvals/<id>/approve/`:
  1. `ActionSafetyService` executes the underlying action (creates a real `MaintenanceTicket`).
  2. Updates `FactoryIncident.status = 'MITIGATING'`.
  3. Writes an immutable audit entry in `AuditLog`.

---

## 5. Management Commands & REST APIs

### Background Agent Daemon
```bash
python manage.py run_machine_health_agent --interval 3.0 --cycles 0
```

### REST API Endpoints
- `GET /api/v1/executions/summary/`: Overview of AI agent operations, provider configuration, pending incidents, and executions stream.
- `POST /api/v1/executions/investigate/<incident_id>/`: On-demand investigation trigger.
- `POST /api/v1/executions/run-cycle/`: Trigger evaluation cycle across all pending incidents.
- `GET /api/v1/executions/status/`: Provider model name, configuration status, and timestamp.
- `GET /api/v1/approvals/`: List pending human-in-the-loop approval requests.
- `POST /api/v1/approvals/<id>/approve/`: Approve request and execute real action.
- `POST /api/v1/approvals/<id>/reject/`: Reject request and cancel action.
