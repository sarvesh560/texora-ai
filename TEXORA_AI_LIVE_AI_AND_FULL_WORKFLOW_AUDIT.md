# TEXORA AI — COMPLETE LIVE AI, GEMINI & END-TO-END WORKFLOW AUDIT REPORT

**Date of Audit:** October 12, 2026  
**Audited Location:** `C:\Users\projects\texora-ai`  
**Target Machine Under Audit:** `WEV-AJ-02` (Picanol OmniPlus-i Airjet Loom #2, Weaving Department)  
**System Status:** Fully Operational with Bounded LLM Fallback & Autonomous Daemons  

---

## 1. Executive Summary & Verification Scorecard

| Area | Component / Subsystem | Status | Verification Summary & Evidence |
| :--- | :--- | :---: | :--- |
| **A** | **Repository & Runtime Audit** | **PASS** | Django 5.x settings loaded, `.env` secured, all 13 core apps registered. System check reported 0 errors. |
| **B** | **Gemini API Connectivity** | **PARTIAL** | API key is valid and configured (HTTP 200 on `v1beta/models`). Outbound requests hit Google Free Tier quota (`RESOURCE_EXHAUSTED` / HTTP 429) & HTTP 503 spikes. Deterministic fallback seamlessly activated. |
| **C** | **4-Agent Pipeline Execution** | **PASS** | Machine Health, Maintenance Coordinator, Inventory Coordinator, and Production Impact agents all execute, log UUIDs/IDs, and save decisions & actions into the database. |
| **D** | **Autonomous Worker Daemons** | **PASS** | `ANOMALY_DETECTOR` (PID 488) and `AUTONOMOUS_ORCHESTRATOR` (PID 11716) actively record fresh heartbeats (<2.0s age). Incidents are detected and processed without manual script calls. |
| **E** | **Digital Twin & What-If Studio** | **PASS** | Strategies A, B, and C evaluated with reproducible cost ranking (A: ₹6,921, C: ₹10,521, B: ₹11,292). Financial figures explicitly labeled as simulation estimates. |
| **F** | **Approval & Authorization Safety** | **PARTIAL** | Agent actions safely pause in `PENDING_APPROVAL`. Self-approval by AI identities strictly blocked. Role validation exists in service layer, but REST API view currently has `AllowAny` permissions. |
| **G** | **Maintenance & Recovery Verification** | **PASS** | Successful repair path completed with authorized sign-off. Failed path verified: high post-repair vibration (6.88 mm/s) transitions ticket to `VERIFICATION_FAILED` and blocks closure. Double-deduction prevented. |
| **H** | **Flutter Web Integration** | **PASS** | Port 50000 active, HTTP 200 returned. All 32 Flutter screen/model unit & widget tests passed. `flutter analyze` reported 0 issues. |
| **I** | **Automated Test Suites** | **PASS** | Backend Pytest: 84/84 passed (125.99s). Flutter Test: 32/32 passed (19s). Django check: 0 issues. |

---

## 2. Gemini API Connectivity & Provenance Audit

- **Configuration:** Configured in `backend/.env` as `GEMINI_API_KEY` (masked, length: 53 chars).
- **Configured Model:** `gemini-3.5-flash` (`LLM_PROVIDER=gemini`).
- **Models Endpoint Discovery:** Outbound call to `https://generativelanguage.googleapis.com/v1beta/models?key=***` returned **HTTP 200 OK** in **899 ms**, discovering models including `gemini-2.5-flash`, `gemini-2.5-pro`, `gemini-flash-latest`, and `gemini-2.5-flash-lite`.
- **Inference Request Attempt:** Attempted live outbound structured generation using `GeminiProvider`.
- **Live Response Outcome:**
  - **HTTP Status:** **429 Too Many Requests** / `RESOURCE_EXHAUSTED` and **503 Service Unavailable** (High Demand Spikes).
  - **Google Generative Language API Error Message:**
    ```
    Gemini (gemini-3.5-flash) HTTP 429: You exceeded your current quota, please check your plan and billing details.
    * Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20, model: gemini-3.6-flash.
    Please retry in 17h12m11s.
    ```
  - **Latency:** 779 ms.
- **Failover Provenance:** `[GeminiProvider] Quota/Rate limit exceeded (HTTP 429). Fast-failover to deterministic fallback.`
- **Result:** Gemini did not generate the live response because the free-tier daily quota limit of 20 requests was exhausted. The application transparently tagged the database execution summary with `[GEMINI_FAILED]` and used deterministic industrial reasoning, avoiding uncaught crashes or hung processes.

---

## 3. Four Specialist AI Agents — Execution & Provenance

When incident `#56` occurred on `WEV-AJ-02`, all 4 specialist agents executed autonomously in strict sequence:

| Agent Name | Agent Type | Engine / Model | Exec ID | Status | Latency | Actions Proposed & Database State |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **Machine Health Specialist** | `MACHINE_HEALTH` | `gemini-3.5-flash` (Failover: Deterministic Mock) | `#184` | `COMPLETED` | 26.76s | Proposed bearing replacement & parts reservation. Both actions queued into `PENDING_APPROVAL`. |
| **Maintenance Coordinator** | `MAINTENANCE` | Deterministic Rules (`deterministic-maintenance-v1`) | `#185` | `COMPLETED` | 5.1 ms | Evaluated active work orders; prevented duplicate work order creation for open ticket `MNT-20261012062206-A861`. |
| **Inventory Coordinator** | `INVENTORY` | Deterministic Rules (`deterministic-inventory-v1`) | `#186` | `COMPLETED` | 13.2 ms | Verified stock for `SPR-BRG-6309` (1 in-stock, 0 shortages). Proposed reservation action in `PENDING_APPROVAL`. |
| **Production Impact Agent** | `PRODUCTION_IMPACT` | Deterministic Rules (`deterministic-production-v1`) | `#187` | `COMPLETED` | 12.9 ms | Evaluated active weaving batches; calculated 1.5h downtime loss (~142.5 units); evaluated alternate looms for rerouting. |

### Provenance Distinction:
- **LLM-Integrated Agent:** Only `MachineHealthAgent` uses Google Gemini LLM API (with bounded fallback).
- **Deterministic Domain Solvers:** `MaintenanceCoordinatorAgent`, `InventoryCoordinatorAgent`, and `ProductionImpactAgent` are deterministic domain engines that calculate math, check warehouse ledger stock, and evaluate manufacturing schedules without calling external LLM APIs.

---

## 4. Background Worker Daemon Autonomy

- **Worker 1 (`ANOMALY_DETECTOR`):**
  - Process ID: `488`
  - Heartbeat status: `RUNNING`
  - Heartbeat Age: `1.5s` (Live, freshness threshold < 15s)
  - Processing: Continuously compares machine telemetry against `MachineOperatingLimits` and automatically creates `FactoryIncident` records.
- **Worker 2 (`AUTONOMOUS_ORCHESTRATOR`):**
  - Process ID: `11716`
  - Heartbeat status: `RUNNING`
  - Heartbeat Age: `2.0s` (Live, freshness threshold < 15s)
  - Autonomy Proof: Processed Incident `#56` automatically during its polling cycle, executed the 4 agents, ran the Digital Twin What-If simulation, created `RecoveryCase REC-20261012-FD7A`, and queued approval requests **without any user interaction or test script invocation**.

---

## 5. Digital Twin & What-If Simulation Engine

- **Active Scenario:** `SCN-AUTO-20261012081022-5FCB` (*Autonomous Recovery Simulation on WEV-AJ-02*)
- **Simulation Run ID:** `98` (Status: `COMPLETED`, Duration: 18 ms)
- **Strategy Evaluation & Reproducibility:**
  - **Strategy A (Direct In-Place Repair):**
    - **Rank 1 (Recommended)**
    - Estimated Cost: **₹6,921.00**
    - Formula: `(1 Tech * 1.5h * ₹750/h) + (1 Part Kit * ₹4,500) + (72.0 units * ₹18/unit penalty) = ₹6,921`
    - Downtime: 1.5 hours | Feasible: `True` | Volume Protected: 72.0 m
  - **Strategy C (Parallel Repair + Retooling):**
    - **Rank 2**
    - Estimated Cost: **₹10,521.00**
    - Formula: `(1 Tech * 1.5h * ₹750/h) + (1 Part Kit * ₹4,500) + (3 Alt * ₹1,200) + (72 units * ₹18) = ₹10,521`
    - Downtime: 1.5 hours | Feasible: `True`
  - **Strategy B (Reroute Production Only):**
    - **Rank 3**
    - Estimated Cost: **₹11,292.00**
    - Formula: `(3 Alt * ₹2,000 Setup) + (3 * 3.0h * ₹300/h Overtime) + (144 units * ₹18 penalty) = ₹11,292`
    - Downtime: 3.0 hours | Feasible: `True` | Volume Protected: 0.0 m
- **Safety Note:** Figures are explicitly tagged as mathematical simulation models and labeled with input assumptions (`hourly_technician_rate_inr`, `spare_part_kit_cost_inr`, `production_penalty_per_unit_inr`).

---

## 6. Approval Gates & Role-Based Authorization

- **Safe Defaults:** AI agents propose operational mutations as `PENDING_APPROVAL`. No agent can execute operational changes directly.
- **AI Self-Approval Rejection:** Rejects any approval where `approved_by` matches forbidden AI identities (`ai_agent`, `gemini`, `machine_health_agent`, `system_daemon`). Verified via `test_ai_agent_self_approval_rejection` (PASSED).
- **Identified Security Finding:**
  - In `apps/approvals/views.py`: `ApprovalRequestViewSet` has `permission_classes = [permissions.AllowAny]`.
  - The endpoint parses `approved_by = request.data.get("approved_by")` from the unauthenticated JSON request payload.
  - While role string matching occurs in `ActionSafetyService.validate_authorization`, full Django session/token authentication is not currently enforced on the REST endpoint.

---

## 7. Maintenance Execution & Dual-Path Recovery Verification

Executed end-to-end via `scripts/verify_phase12_maintenance_lifecycle.py` on `WEV-AJ-02`:

### Path 1: Successful Return-to-Service
1. Work Order `MNT-P12-081416` created for Incident `INC-P12-081416`.
2. Technician `R. Sharma` accepted assignment and initiated guided inspection.
3. Sensor inspection checklist confirmed defect: Vibration `6.85 mm/s` (Limit: 4.0 mm/s), Temp `76.4 °C` (Limit: 68.0 °C).
4. Physical repair documented: Bearing replacement (Duration: 45 min).
5. Spare part `SPR-BRG-6204` deducted (Stock: 44.00 -> 43.00 PCS).
6. Double-deduction guard prevented repeated stock deductions.
7. Post-repair telemetry generated: 6 successive readings (Peak Vib: `2.55 mm/s` < 4.0 mm/s; Peak Temp: `57.7 °C` < 68.0 °C).
8. Verification engine evaluated outcome: `AWAITING_AUTHORIZED_SIGNOFF`.
9. Premature incident closure blocked by system guard.
10. Authorized sign-off completed by `V. Ramanathan` (Plant Operations Manager).
11. Machine status restored to `OPERATIONAL` (Health Score: 96.50). Incident safely closed.

### Path 2: Unresolved Fault & Negative Verification
1. Work Order `MNT-NEG-081416` created for residual vibration imbalance.
2. Incomplete repair recorded.
3. Post-repair telemetry exhibited persistent anomalies (Peak Vib: `6.88 mm/s` > 4.0 mm/s; Peak Temp: `82.5 °C` > 68.0 °C).
4. Recovery verification engine evaluated outcome: `FAILED`.
5. Work order transitioned to `VERIFICATION_FAILED`.
6. Incident closure safely blocked.

---

## 8. Flutter Web Integration & Frontend Diagnostics

- **Frontend Server:** Active at `http://localhost:50000` (HTTP 200 OK).
- **Backend API:** Active at `http://127.0.0.1:8000` (All 10 audited endpoints return HTTP 200).
- **Static Analysis:** `flutter analyze` completed in 4.3s with **0 issues found**.
- **Widget & Model Tests:** 32 tests executed in 19s:
  - Executive Command Center, AI Operations Center, Incident Intelligence, Digital Twin, What-If Simulation, Approval Center, Maintenance Execution, and Audit Trail screens all render and handle data parsing correctly.

---

## 9. Automated Test Suites Summary

- **Backend (`pytest`):** `84 passed in 125.99s (0:02:05)`
  - Includes: `test_ai_agents.py`, `test_anomaly_detection.py`, `test_autonomous_orchestrator.py`, `test_digital_twin_and_what_if.py`, `test_domain_apis.py`, `test_domain_models.py`, `test_health.py`, `test_phase10_5_reliability_and_safety.py`, `test_phase11_commercial_showcase.py`, `test_phase12_maintenance_and_verification.py`, `test_recovery_coordination.py`, `test_simulation.py`.
- **Frontend (`flutter test`):** `32 passed in 19s`
- **Django System Check (`python manage.py check`):** `System check identified no issues (0 silenced)`

---

## 10. Answers to Mandatory Verification Questions

### 1. Is the Gemini API key valid and is Gemini generating live responses?
- **Key Validity:** **YES.** The API key in `.env` is valid and authenticates successfully against Google Generative Language API (HTTP 200 on `v1beta/models`).
- **Live Response Generation:** **NO.** Outbound inference currently fails with **HTTP 429** (`RESOURCE_EXHAUSTED: Quota exceeded for metric generate_content_free_tier_requests, limit: 20`) and temporary **HTTP 503** demand spikes. The system automatically and safely falls back to deterministic machine health diagnostics.

### 2. Which AI agents use Gemini and which use deterministic logic?
- **Gemini-Powered:** Only the **Machine Health Specialist Agent (`MachineHealthAgent`)** invokes the Gemini LLM.
- **Deterministic Domain Solvers:**
  - **Maintenance Coordinator Agent (`MaintenanceCoordinatorAgent`)**: Deterministic industrial work order planner.
  - **Inventory Coordinator Agent (`InventoryCoordinatorAgent`)**: Deterministic warehouse stock and safety threshold evaluator.
  - **Production Impact Agent (`ProductionImpactAgent`)**: Deterministic production scheduling and capacity loss engine.

### 3. Are the autonomous background workers running correctly?
- **YES.** Both `ANOMALY_DETECTOR` (PID 488) and `AUTONOMOUS_ORCHESTRATOR` (PID 11716) are actively executing in the background, logging heartbeats every 1.5–2.0 seconds with fresh database timestamps.

### 4. Does the complete workflow execute successfully without manual service invocation?
- **YES.** When machine telemetry crosses critical thresholds, `ANOMALY_DETECTOR` creates an incident. The `AUTONOMOUS_ORCHESTRATOR` daemon automatically polls, detects the incident, runs the 4 specialist agents, executes the Digital Twin simulation, and creates an approval request in the manager inbox without requiring any manual trigger.

### 5. What issues must be fixed before the PSG Expo?
1. **Gemini API Billing / Quota for Live Expo Inference:** The current API key is on Google AI Studio Free Tier (capped at 20 requests/day). For live demonstrations at the expo, a paid tier key with higher RPM/RPD must be configured in `backend/.env` to avoid HTTP 429 quota exhaustion.
2. **Approval API Authentication & RBAC Enforcement:** `ApprovalRequestViewSet` currently uses `AllowAny`. DRF Token Authentication (`IsAuthenticated`) must be enforced so approval actions cannot be spoofed by unauthenticated requests.
3. **PowerShell Daemon Startup Script:** Ensure `start_texora.ps1` reliably launches `manage.py run_orchestrator_worker` alongside `run_anomaly_detector` and `runserver` so all background workers start in a single command on expo demo laptops.
4. **Windows Terminal Character Encoding:** When running CLI scripts on Windows PowerShell, avoid emitting raw unicode rupee symbols (`₹`) to prevent `UnicodeEncodeError` in cp1252 terminal streams.
