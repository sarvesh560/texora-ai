# Texora AI — 13-Screen Reference UI Comparison & Gap Analysis

**Reference Specification**: [reference_13_screens.png](file:///c:/Users/projects/texora-ai/reference_13_screens.png)  
**Date**: October 14, 2026  
**Auditor**: Principal Flutter Web Architect & Industrial AI Systems Architect  

---

## 1. Executive Summary of Comparison

A screen-by-screen architectural comparison was conducted between the attached 13-screen reference design and the existing Texora AI codebase. 

The audit reveals that **the vast majority of core backend data models, business logic engines, and simulation workflows already exist in Django**, but their visual presentation in Flutter differs significantly from the reference image. The existing Flutter application is styled as a dark industrial command console with dense monospace readouts, whereas the 13-screen reference features a clean, high-contrast, modern interface with white cards (`#FFFFFF`), a pale blue-gray workspace (`#F8FAFC`), an enterprise dark navy sidebar (`#0B132B`), and royal blue accents (`#2563EB`).

---

## 2. Granular Comparison: Reference Screens 1 to 13

---

### Screen 1: Main Dashboard (Home)

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [executive_command_center_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/executive_command_center_screen.dart)
- Subwidgets: [metric_card.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/widgets/metric_card.dart), [factory_flow_view.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/widgets/factory_flow_view.dart), [ai_activity_center_widget.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/widgets/ai_activity_center_widget.dart).

#### B. Existing Functionality
- Executive dashboard displaying factory overview, operational health, active alerts, live telemetry aggregations, department flow view, and the Autonomous Expo Demo launcher.

#### C. Fully Implemented Functionality
- Polling live digital twin snapshots (`/api/v1/digital-twin/snapshot/latest/`).
- Multi-department machine counts and running percentages (Spinning, Weaving, Knitting, Dyeing, Finishing).
- Live AI activity feed displaying recent agent events with color-coded status dots.
- Triggering autonomous expo demo orchestrating multi-agent resolution.

#### D. Partially Implemented Functionality
- KPI Cards: The current screen has cards for Overall Health Score, Active Incidents, and Active Machines, but lacks the specific 4-card arrangement shown in the reference:
  1. `Total Machines`: "120" (↑ 98% Running)
  2. `Production Today`: "12,450 kg" (↑ +8% vs yesterday)
  3. `Quality`: "98.2%" (↑ +1.2%)
  4. `Energy Usage`: "18,200 kWh" (↓ -6%)
- Department Flow: Existing `FactoryFlowView` renders a 5-step horizontal flow with machines, but the reference layout organizes departments as visually clean connected white cards on a light canvas.

#### E. Missing Functionality
- Top header `● AI Running` status pill indicator.
- Exact reference card dimensions, white surface styling, and soft typography.

#### F. Django API Endpoints Used
- `GET /api/v1/digital-twin/snapshot/latest/`
- `GET /api/v1/production/overview/`
- `GET /api/v1/energy/readings/`
- `GET /api/v1/inspections/`
- `GET /api/v1/alerts/`
- `POST /api/v1/autonomous/expo-demo/`

#### G. Database Models Involved
- `apps.machines.models.Machine`
- `apps.production.models.ProductionProgress`
- `apps.quality.models.QualityInspection`
- `apps.energy.models.EnergyReading`
- `apps.ai_agents.models.AgentExecution`

#### H. AI Agent Integrations
- `AutonomousOrchestrator`: Dispatches multi-agent cycles; feeds live activity into the timeline.

#### I. Data Source Classification
- **Database-backed simulated data**: Total machines, department counts, activity events, energy readings, and quality scores.

#### J. Existing Test Coverage
- [executive_command_center_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/executive_command_center_screen_test.dart)
- [factory_flow_view_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/factory_flow_view_test.dart)

#### K. Current UI Differences Compared with Reference
- Current: Deep navy `#0A0F1D` background, dark `#0F172A` cards, monospace industrial badges, multiple dense action rows.
- Reference: Pale blue-gray `#F8FAFC` background, 4 clean white KPI cards in top row, department schematic card on the left, "Live AI Activity" card on the right, header with profile and search.

#### L. Required UI Improvements
- Restyle the dashboard with white cards, 8px corner radius, subtle borders (`#E2E8F0`).
- Implement the 4 top KPI cards with green percentage badges.
- Render the 5-department schematic card on the left (Spinning 28, Weaving 24, Knitting 16, Dyeing 12, Finishing 18).
- Streamline the Live AI Activity timeline on the right with timestamps (10:24, 10:25, etc.) and colored status dots.

#### M. Required Backend Improvements
- Add an aggregated dashboard summary endpoint or combine existing endpoints efficiently in a lightweight repository/service method.

#### N. Recommendation
- **Extend & Reorganize**: Reuse existing data controllers and polling logic from `executive_command_center_screen.dart`, while adopting the clean white reference layout.

---

### Screen 2: AI Agents

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [ai_agent_operations_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/ai_agent_operations_screen.dart)
- Subwidgets: [agent_execution_detail_dialog.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/widgets/agent_execution_detail_dialog.dart).

#### B. Existing Functionality
- Fleet operations dashboard for AI agents showing active definitions, LLM execution latency, token counts, multi-provider Groq/Gemini metrics, and detailed reasoning logs.

#### C. Fully Implemented Functionality
- 6 Specialist Agent definitions in backend:
  1. `Machine Health Agent` (`apps.ai_agents.models.AgentType.MACHINE_HEALTH`)
  2. `Production Agent` (`apps.ai_agents.models.AgentType.PRODUCTION_IMPACT`)
  3. `Maintenance Agent` (`apps.ai_agents.models.AgentType.MAINTENANCE`)
  4. `Quality Agent` (`apps.ai_agents.models.AgentType.QUALITY_CONTROL`)
  5. `Inventory Agent` (`apps.ai_agents.models.AgentType.INVENTORY`)
  6. `Energy Agent` (`apps.ai_agents.models.AgentType.ENERGY`)
- Full execution history and tool invocation audit details.
- 5-stage orchestration pipeline: Detect -> Analyze -> Decide -> Act -> Verify.

#### D. Partially Implemented Functionality
- The existing UI presents agents in dense technical status cards with latency graphs and provider toggles, rather than the clean 6-card grid with custom icons and the horizontal 5-stage orchestration pipeline card shown in the reference.

#### E. Missing Functionality
- The exact visual card style: 6 white agent cards with green "Active" pill badges, clear icons (shield, bar chart, wrench, magnifying glass, package, lightning bolt), and the horizontal pipeline flow card labeled "Agent Orchestration" (1 Detect, 2 Analyze, 3 Decide, 4 Act, 5 Verify).

#### F. Django API Endpoints Used
- `GET /api/v1/agents/`
- `GET /api/v1/ai-agents/operations-overview/`
- `GET /api/v1/executions/`

#### G. Database Models Involved
- `apps.ai_agents.models.AgentDefinition`
- `apps.ai_agents.models.AgentExecution`
- `apps.ai_agents.models.AutonomousWorkflowRun`

#### H. AI Agent Integrations
- All 6 agents running under `AutonomousOrchestrator` using Groq / Gemini LLMs with deterministic safety fallbacks.

#### I. Data Source Classification
- **Database-backed simulated data**: Live agent definitions and execution logs stored in SQLite.

#### J. Existing Test Coverage
- [ai_agent_operations_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/ai_agent_operations_screen_test.dart)
- `backend/tests/test_phase12_5_multi_agent_activation.py`

#### K. Current UI Differences Compared with Reference
- Current: Dark technical console with LLM provider breakdown and token latency charts.
- Reference: Clean 2x3 grid of white agent cards + bottom horizontal "Agent Orchestration" pipeline card.

#### L. Required UI Improvements
- Create clean `TexoraAgentCard` widget matching the reference styling.
- Create the horizontal "Agent Orchestration" pipeline component (1 Detect -> 2 Analyze -> 3 Decide -> 4 Act -> 5 Verify).
- Retain deep technical audit details via drill-down dialog or secondary tab.

#### M. Required Backend Improvements
- None required. All 6 agent types and pipeline stages exist in `apps/ai_agents/models.py`.

#### N. Recommendation
- **Extend & Reorganize**: Wrap existing live agent data into the clean 6-card reference layout and preserve the advanced LLM audit modal.

---

### Screen 3: Live Machine Monitoring

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [machine_health_agent_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/machine_health_agent_screen.dart)
- Secondary: [digital_twin_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/digital_twin_screen.dart).

#### B. Existing Functionality
- Machine health dashboard with list of machines, telemetry charts (vibration, temperature, power), health scores, and anomaly warnings.

#### C. Fully Implemented Functionality
- Backend models for 120 simulated textile machines across Spinning, Weaving, Knitting, Dyeing, and Finishing.
- Live telemetry time-series: vibration (mm/s), temperature (°C), speed (RPM), efficiency (%).
- Dynamic status flags: `OPERATIONAL`, `WARNING`, `CRITICAL`, `MAINTENANCE`.

#### D. Partially Implemented Functionality
- Existing UI uses cards with expandable panels rather than the compact reference data table.
- Filter chips for departments currently exist in some views, but need to be aligned with the reference tabs: `All (120)`, `Spinning (28)`, `Weaving (24)`, `Knitting (16)`, `Dyeing (12)`, `Finishing (18)`.

#### E. Missing Functionality
- Clean compact table layout matching columns:
  `Machine` | `Status` | `Vibration (mm/s)` | `Temperature (°C)` | `Speed (RPM)` | `Efficiency` | `Trend`
- Inline trend sparklines inside the table row.
- Row click navigation directly to Screen 4 (AI Incident Overview for TX-102).

#### F. Django API Endpoints Used
- `GET /api/v1/machines/`
- `GET /api/v1/telemetry/`
- `GET /api/v1/digital-twin/snapshot/latest/`

#### G. Database Models Involved
- `apps.machines.models.Machine`
- `apps.machines.models.MachineTelemetry`
- `apps.factories.models.Department`

#### H. AI Agent Integrations
- `MachineHealthAgent`: Evaluates telemetry against limits and flags anomalies.

#### I. Data Source Classification
- **Database-backed simulated data**: Database records seeded by `seed_factory.py` with continuous telemetry generation.

#### J. Existing Test Coverage
- [machine_health_agent_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/machine_health_agent_screen_test.dart)
- `backend/tests/test_phase10_5_reliability_and_safety.py`

#### K. Current UI Differences Compared with Reference
- Current: Card-based grid with large gauge indicators and multi-line telemetry charts.
- Reference: Clean, high-density data table with department filter tabs and sparklines.

#### L. Required UI Improvements
- Implement `TexoraDataTable` for machines with sorting, department filter tabs, and inline status badges.
- Add mini sparkline widget for the `Trend` column.
- Support click-to-open drill-down to Screen 4.

#### M. Required Backend Improvements
- Ensure `/api/v1/machines/` returns latest telemetry values and sparkline points in serializer payload to minimize multiple HTTP round-trips.

#### N. Recommendation
- **Extend**: Create the reference table view as the primary machine monitoring interface, allowing users to drill down into the existing deep telemetry charts.

---

### Screen 4: AI Incident Overview (TX-102 — Abnormal Vibration Detected)

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [incident_intelligence_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/incident_intelligence_screen.dart)

#### B. Existing Functionality
- Incident workspace showing active machine anomalies, sensor readings vs thresholds, AI specialist findings, and resolution action links.

#### C. Fully Implemented Functionality
- Machine overview with ID, department, and operating hours.
- Telemetry gauge indicators: Vibration (8.2 mm/s vs >4.0 threshold), Temperature (86°C vs normal <70°C), Speed (11,000 RPM).
- Status badge: `Critical` and `AI Detected`.
- AI Summary narrative with confidence percentage (87%).
- Tab bar navigation: `[Overview, AI Analysis, Maintenance, Production Impact, History]`.

#### D. Partially Implemented Functionality
- Navigation breadcrumb `< Back to Machines`.
- Specific thumbnail machine photo placeholder/asset.
- Primary button `View Full AI Analysis →` switching directly to Tab 2 (Screen 5).

#### E. Missing Functionality
- Exact reference card styling: White container with 2-column split (Left: machine photo + telemetry metrics; Right: AI Summary card with green 87% confidence badge).

#### F. Django API Endpoints Used
- `GET /api/v1/incidents/`
- `GET /api/v1/incidents/{id}/`
- `GET /api/v1/machines/{code}/`
- `GET /api/v1/autonomous/incident-workflow/{id}/`

#### G. Database Models Involved
- `apps.incidents.models.FactoryIncident`
- `apps.machines.models.Machine`
- `apps.machines.models.MachineTelemetry`
- `apps.ai_agents.models.AgentExecution`

#### H. AI Agent Integrations
- `MachineHealthAgent` and `AutonomousOrchestrator`.

#### I. Data Source Classification
- **Database-backed simulated data**: Incident record `INC-...` and machine telemetry in SQLite.

#### J. Existing Test Coverage
- [incident_intelligence_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/incident_intelligence_screen_test.dart)

#### K. Current UI Differences Compared with Reference
- Current: Deep navy card layout with terminal-style telemetry displays.
- Reference: Clean white cards with light red warning tiles for out-of-spec vibration/temperature, industrial machine image, and confidence pill.

#### L. Required UI Improvements
- Redesign incident detail header with `< Back to Machines`, severity pill (`Critical`), department label, timestamp, and `● AI Detected` badge.
- Build the 5-tab bar matching the reference.
- Style the Overview tab with the 2-column layout and "View Full AI Analysis →" button.

#### M. Required Backend Improvements
- None required.

#### N. Recommendation
- **Reorganize & Extend**: Restyle `incident_intelligence_screen.dart` into the 5-tab reference structure, mapping Tab 1 to Screen 4 and Tab 2 to Screen 5.

---

### Screen 5: AI Analysis (TX-102 — AI Analysis)

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [incident_intelligence_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/incident_intelligence_screen.dart) (AI Investigation Section).

#### B. Existing Functionality
- Root-cause reasoning, evidence checklist, AI recommendations, and links to maintenance dispatch and production impact.

#### C. Fully Implemented Functionality
- Backend LLM reasoning produces suspected causes, historical fault correlations, and operational recommendations.
- Confidence score calculation (87% confidence).
- Actions: Create Maintenance Ticket, View Production Impact.

#### D. Partially Implemented Functionality
- Currently displayed in an expandable accordion inside the dark incident workspace rather than as Tab 2 of the machine incident view.

#### E. Missing Functionality
- Exact layout:
  - Card 1: "Root Cause Analysis" with green checkmarks:
    - ✔ Vibration level is 2x higher than normal
    - ✔ Pattern indicates bearing wear
    - ✔ Similar issue occurred on 12 Oct 2026
    - ✔ No recent maintenance in last 400 hours
  - Card 2: "AI Recommendation" with amber icon:
    - 1. Schedule maintenance within 2 hours
    - 2. Inspect bearing and lubricate
    - 3. Estimated production loss if not addressed: ~1,450 kg
  - Action buttons: `Create Maintenance Ticket` (dark button), `View Production Impact` (outline button).

#### F. Django API Endpoints Used
- `GET /api/v1/autonomous/incident-workflow/{id}/`
- `POST /api/v1/ai-agents/diagnose/`
- `POST /api/v1/maintenance/tickets/`

#### G. Database Models Involved
- `apps.ai_agents.models.AgentDecision`
- `apps.ai_agents.models.AgentExecution`
- `apps.incidents.models.FactoryIncident`

#### H. AI Agent Integrations
- `MachineHealthAgent` (Gemini / Groq LLM client).

#### I. Data Source Classification
- **Database-backed simulated data**: Grounded on SQLite incident and telemetry history.

#### J. Existing Test Coverage
- [incident_intelligence_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/incident_intelligence_screen_test.dart)

#### K. Current UI Differences Compared with Reference
- Current: Dark background, monospace text boxes for LLM thoughts.
- Reference: Clean white cards with structured checklists, clear visual hierarchy, and prominent CTA buttons.

#### L. Required UI Improvements
- Implement Tab 2 ("AI Analysis") inside the machine incident screen matching the reference layout.

#### M. Required Backend Improvements
- Ensure root-cause evidence items and recommendations are returned as clean structured lists in the incident workflow serializer.

#### N. Recommendation
- **Extend**: Render this as Tab 2 of the machine detail screen, binding directly to existing AI decision payloads.

---

### Screen 6: Maintenance Tickets

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [maintenance_execution_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/maintenance_execution_screen.dart)

#### B. Existing Functionality
- Work order management, lifecycle transitions, guided inspection checklists, parts consumption, and recovery verification.

#### C. Fully Implemented Functionality
- Full ticket records (`MaintenanceTicket` model) with ticket number, machine, issue/title, priority (`High`, `Medium`, `Low`), status (`Open`, `In Progress`, `Completed`), created time, and assigned technician.
- Filter tabs: `All (24)`, `Open (5)`, `In Progress (8)`, `Completed (11)`.
- Backend support for `+ New Ticket` creation.

#### D. Partially Implemented Functionality
- The existing screen is focused on technician execution (checklist, telemetry before/after, parts replacement), rather than the clean overview table shown in Screen 6.

#### E. Missing Functionality
- The high-level overview table matching the reference:
  `Ticket` | `Machine` | `Issue` | `Priority` | `Status` | `Created` | `Assigned To`
  with sample rows MT-458, MT-457, MT-456, MT-455, RX-454.
- Button `+ New Ticket` opening a ticket creation modal.

#### F. Django API Endpoints Used
- `GET /api/v1/maintenance/tickets/`
- `POST /api/v1/maintenance/tickets/`

#### G. Database Models Involved
- `apps.maintenance.models.MaintenanceTicket`
- `apps.machines.models.Machine`

#### H. AI Agent Integrations
- `MaintenanceCoordinator`: Automatically drafts maintenance tickets upon incident confirmation.

#### I. Data Source Classification
- **Database-backed simulated data**: Tickets stored in SQLite database.

#### J. Existing Test Coverage
- [maintenance_execution_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/maintenance_execution_test.dart)
- `backend/tests/test_phase12_maintenance_and_verification.py`

#### K. Current UI Differences Compared with Reference
- Current: Deep execution screen with sensor graph verification and sign-off forms.
- Reference: Clean overview data table with filter tabs and "+ New Ticket" button.

#### L. Required UI Improvements
- Add the reference overview table as the top-level view under "Maintenance", with row clicks navigating into the existing rich execution and verification console.

#### M. Required Backend Improvements
- None required.

#### N. Recommendation
- **Reorganize & Extend**: Present the reference tickets table as the primary screen, preserving the existing deep execution center as the drill-down detail view.

---

### Screen 7: Production Overview

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [production_intelligence_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/production_intelligence_screen.dart)

#### B. Existing Functionality
- Phase 15 Production Intelligence: department capacity routing, job orders table, delivery delay risk calculation, bottleneck alerts, and progression simulation.

#### C. Fully Implemented Functionality
- Total production vs target calculation.
- Active orders table: Order Number (`PO-1026`), Fabric/Yarn Spec, Target/Completed Quantity, Status (`In Progress`, `Delayed`).
- Delay risk estimation and bottleneck detection.

#### D. Partially Implemented Functionality
- The existing screen features 5 large department capacity cards (Spinning, Weaving, Dyeing, Finishing, Garmenting).
- The reference screen features:
  - Top 4 KPI cards:
    1. `Total Production`: "12,450 kg" (↑ 6% vs yesterday)
    2. `Target`: "14,000 kg" (Circular progress 89%, Remaining 1,550 kg)
    3. `Active Orders`: "5"
    4. `On Schedule`: "4" (↑ 80%), `Delayed`: "1" (↓ 20%)
  - Left card: `Production Trend` (Actual vs Target) hourly chart (06AM - 10PM).
  - Right card: `Current Orders` table (PO-1026, PO-1027, PO-1028, PO-1029).

#### E. Missing Functionality
- Clean hourly Production Trend dual-line chart (Actual vs Target).
- Compact Current Orders table styled as a white card.

#### F. Django API Endpoints Used
- `GET /api/v1/production/overview/`
- `GET /api/v1/production/orders/`
- `GET /api/v1/production/timeline/`

#### G. Database Models Involved
- `apps.production.models.ProductionOrder`
- `apps.production.models.ProductionBatch`
- `apps.production.models.ProductionProgress`

#### H. AI Agent Integrations
- `ProductionImpactAgent`: Computes capacity utilization and bottleneck alerts.

#### I. Data Source Classification
- **Database-backed simulated data**: Database records from SQLite.

#### J. Existing Test Coverage
- [production_intelligence_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/production_intelligence_screen_test.dart)
- [data_contract_and_simulation_integration_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/data_contract_and_simulation_integration_test.dart)

#### K. Current UI Differences Compared with Reference
- Current: Dark navy screen with large department cards and progression simulation modal.
- Reference: White dashboard cards, circular target indicator, hourly trend chart, and current orders table.

#### L. Required UI Improvements
- Restyle the Production screen with the reference KPI cards, trend chart, and current orders card.
- Retain the Phase 15 capacity routing and simulation progression controls accessible via tab or action button.

#### M. Required Backend Improvements
- None required. All necessary models and endpoints are present.

#### N. Recommendation
- **Extend**: Adopt the reference layout for the primary Production tab while retaining Phase 15 multi-department capacity routing in a dedicated sub-view.

---

### Screen 8: Production Impact & Recovery (AI)

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [what_if_simulation_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/what_if_simulation_screen.dart)
- Secondary: [factory_recovery_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/factory_recovery_screen.dart).

#### B. Existing Functionality
- What-If simulation engine calculating affected orders, downtime hours, output loss, alternate machines, and AI recovery strategy recommendations.

#### C. Fully Implemented Functionality
- Subtabs: `[Impact Analysis, Recovery Plan, Alternative Machines]`.
- Warning banner: "⚠ If not addressed, estimated loss: ~1,450 kg (12% of today's target)".
- Left Card: `Impact Details` (Affected Order: PO-1026, Expected Delay: 6 hours, Estimated Loss: 1,450 kg, Confidence: 85%).
- Right Card: `AI Recovery Plan` (Shift 60% load to TX-105, adjust batch schedule, estimated loss reduced to <2%, no impact on delivery dates).
- Actions: `Approve & Apply Plan` and `Modify Plan`.

#### D. Partially Implemented Functionality
- Currently implemented across two separate screens (`WhatIfSimulationScreen` and `FactoryRecoveryScreen`) with technical parameter sliders and strategy cards (Strategy A, B, C).

#### E. Missing Functionality
- Clean 2-column white card visual presentation matching Screen 8.

#### F. Django API Endpoints Used
- `GET /api/v1/digital-twin/what-if/scenarios/{id}/results/`
- `POST /api/v1/digital-twin/what-if/simulate/`
- `POST /api/v1/approvals/`

#### G. Database Models Involved
- `apps.digital_twin.models.WhatIfScenario`
- `apps.production.models.ProductionImpactAssessment`
- `apps.ai_agents.models.RecoveryCase`

#### H. AI Agent Integrations
- `RecoveryOrchestrator` and `ProductionImpactAgent`.

#### I. Data Source Classification
- **Database-backed simulated data**: Live simulation results computed by `apps.digital_twin.simulation_engine`.

#### J. Existing Test Coverage
- [what_if_simulation_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/what_if_simulation_screen_test.dart)
- [factory_recovery_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/factory_recovery_screen_test.dart)

#### K. Current UI Differences Compared with Reference
- Current: Parameter input sliders and complex comparison charts on dark navy backgrounds.
- Reference: Clean summary cards with clear impact metrics, structured recovery steps, and high-contrast action buttons.

#### L. Required UI Improvements
- Build the exact Screen 8 layout as a tab or drill-down under Production/Machines, with "Approve & Apply Plan" dispatching to the existing Approval Center.

#### M. Required Backend Improvements
- None required.

#### N. Recommendation
- **Reorganize & Extend**: Present the clean reference view as the primary recovery presentation, backed by existing simulation results.

---

### Screen 9: Inventory (Auto Check)

#### A. Existing Corresponding Flutter Screen or Widget
- Existing: Backend models and APIs exist in [apps/inventory/](file:///c:/Users/projects/texora-ai/backend/apps/inventory/); currently accessed via `ApiService.fetchInventoryItems()`.
- Missing in Frontend: Dedicated visual screen in `MainShellScreen`.

#### B. Existing Functionality
- Warehouse stock tracking, reorder points, low-stock alerts, automated reservation by AI agents, and spare part mapping for textile machines.

#### C. Fully Implemented Functionality (Backend)
- Models `InventoryItem`, `InventoryTransaction`, `SparePartRequirement` in Django.
- Endpoints:
  - `GET /api/v1/inventory/items/`
  - `GET /api/v1/inventory/items/low_stock/`
  - `GET /api/v1/inventory/transactions/`
- Data seeded with Cotton Yarn, Bearing 6205, V-Belt, Lubricating Oil, Dye Chemicals.

#### D. Partially Implemented Functionality
- `ApiService` has helper calls for parts, but no full frontend screen is currently mounted in the navigation sidebar.

#### E. Missing Functionality (Frontend)
- Dedicated `InventoryScreen` matching Screen 9:
  - Header: "Spare Parts Inventory" with search bar "Search material...".
  - Left Card: Data table with columns `Material` | `Stock` | `Status` | `Reorder Level`.
    - Cotton Yarn: 2,450 kg (In Stock - green)
    - Bearing (6205): 12 pcs (Low Stock - red)
    - V-Belt: 32 pcs (In Stock - green)
    - Lubricating Oil: 850 L (In Stock - green)
    - Dye Chemicals: 120 kg (Low Stock - red)
  - Right Card: "AI Inventory Check" checklist:
    - ✔ Required bearing available (12 pcs)
    - ✔ No shortage for immediate maintenance
    - ✔ Sufficient cotton yarn stock
    - ✔ No critical shortages detected

#### F. Django API Endpoints Used
- `GET /api/v1/inventory/items/`
- `GET /api/v1/inventory/items/low_stock/`

#### G. Database Models Involved
- `apps.inventory.models.InventoryItem`
- `apps.inventory.models.SparePartRequirement`

#### H. AI Agent Integrations
- `InventoryCoordinator`: Performs automated inventory checks and flags spare part shortages.

#### I. Data Source Classification
- **Database-backed simulated data**: Real database records in SQLite.

#### J. Existing Test Coverage
- Backend tests exist in `backend/tests/test_phase10_5_reliability_and_safety.py`. Need new Flutter widget test.

#### K. Current UI Differences Compared with Reference
- Current: No dedicated screen in Flutter sidebar.
- Reference: Full top-level screen with search, stock table, and AI inventory check card.

#### L. Required UI Improvements
- Create new `InventoryScreen` implementing the exact Screen 9 layout.

#### M. Required Backend Improvements
- None required. Django endpoints are fully functional.

#### N. Recommendation
- **Newly Created (Frontend)**: Build `inventory_screen.dart` using existing live Django inventory APIs.

---

### Screen 10: Quality Monitoring

#### A. Existing Corresponding Flutter Screen or Widget
- Existing: Backend models and APIs exist in [apps/quality/](file:///c:/Users/projects/texora-ai/backend/apps/quality/).
- Missing in Frontend: Dedicated visual screen in `MainShellScreen`.

#### B. Existing Functionality
- Textile quality tracking: fabric defects, defect taxonomy (Yarn Unevenness, Barre Effect, Shade Variation), inspection batches, and quality scores.

#### C. Fully Implemented Functionality (Backend)
- Models `QualityInspection` and `QualityDefect` in Django.
- Endpoints:
  - `GET /api/v1/inspections/`
  - `GET /api/v1/defects/`
- Seeded with inspection records, defect distributions, and overall quality scores (98.2%).

#### D. Partially Implemented Functionality
- Backend endpoints return quality data, but no dedicated screen currently exists in `main_shell_screen.dart`.

#### E. Missing Functionality (Frontend)
- Dedicated `QualityMonitoringScreen` matching Screen 10:
  - Top 3 KPI cards:
    1. `Overall Quality`: "98.2%" (↑ +1.2%)
    2. `Total Batches`: "38"
    3. `Defects`: "0.8%" (↓ -0.3%)
  - Left Card: `Quality Trend` chart (Quality % vs Target across time).
  - Right Card: `Top Defects` progress list:
    - Yarn Strength: 0.3%
    - Thickness Variation: 0.2%
    - Contamination: 0.1%
    - Color Variation: 0.1%
    - Others: 0.1%

#### F. Django API Endpoints Used
- `GET /api/v1/inspections/`
- `GET /api/v1/defects/`

#### G. Database Models Involved
- `apps.quality.models.QualityInspection`
- `apps.quality.models.QualityDefect`

#### H. AI Agent Integrations
- `QualityControlAgent`: Assesses defect rates and alerts on threshold violations.

#### I. Data Source Classification
- **Database-backed simulated data**: Stored in SQLite database.

#### J. Existing Test Coverage
- Backend model tests. Need new Flutter widget test.

#### K. Current UI Differences Compared with Reference
- Current: No dedicated screen in Flutter sidebar.
- Reference: Top-level screen with KPIs, trend chart, and top defects breakdown.

#### L. Required UI Improvements
- Create new `QualityMonitoringScreen` implementing the exact Screen 10 layout.

#### M. Required Backend Improvements
- Add an aggregated summary endpoint `/api/v1/quality/summary/` or serializer method to return defect breakdown percentages directly.

#### N. Recommendation
- **Newly Created (Frontend)**: Build `quality_monitoring_screen.dart` connected to Django quality endpoints.

---

### Screen 11: Energy Management

#### A. Existing Corresponding Flutter Screen or Widget
- Existing: Backend models and APIs exist in [apps/energy/](file:///c:/Users/projects/texora-ai/backend/apps/energy/).
- Missing in Frontend: Dedicated visual screen in `MainShellScreen`.

#### B. Existing Functionality
- Factory energy monitoring: sub-metered active power (kW), cumulative consumption (kWh), power factor, voltage, and peak hour detection.

#### C. Fully Implemented Functionality (Backend)
- Model `EnergyReading` in Django.
- Endpoint: `GET /api/v1/energy/readings/`.
- Seeded with hourly readings across departments.

#### D. Partially Implemented Functionality
- Energy power load was integrated into `ExecutiveCommandCenterScreen`'s energy card, but no dedicated top-level screen exists.

#### E. Missing Functionality (Frontend)
- Dedicated `EnergyManagementScreen` matching Screen 11:
  - Top 2 KPI cards:
    1. `Total Consumption`: "18,200 kWh" (↓ -6% vs yesterday)
    2. `Cost Today`: "₹18,200" (↓ -6%)
  - Left Card: `Hourly Consumption` vertical green bar chart (06AM - 10PM) with peak/off-peak indicators.
  - Right Card: `AI Insights` checklist:
    - ✔ Consumption 8% lower than average
    - ✔ No unusual spikes detected
    - ✔ Dyeing unit optimization opportunity: ~12% savings
    - ✔ Recommend adjusting compressor schedule

#### F. Django API Endpoints Used
- `GET /api/v1/energy/readings/`

#### G. Database Models Involved
- `apps.energy.models.EnergyReading`

#### H. AI Agent Integrations
- `EnergyAgent`: Evaluates peak demand and optimization opportunities.

#### I. Data Source Classification
- **Database-backed simulated data**: Stored in SQLite database.

#### J. Existing Test Coverage
- Backend tests exist. Need new Flutter widget test.

#### K. Current UI Differences Compared with Reference
- Current: No dedicated screen in Flutter sidebar.
- Reference: Top-level screen with KPIs, hourly consumption bar chart, and AI insights card.

#### L. Required UI Improvements
- Create new `EnergyManagementScreen` implementing the exact Screen 11 layout.

#### M. Required Backend Improvements
- Add an hourly aggregation action or endpoint `/api/v1/energy/hourly-summary/` to return the 12-hour bar chart buckets directly.

#### N. Recommendation
- **Newly Created (Frontend)**: Build `energy_management_screen.dart` connected to Django energy endpoints.

---

### Screen 12: Reports & Analytics

#### A. Existing Corresponding Flutter Screen or Widget
- Existing: No dedicated reports screen in Flutter frontend.

#### B. Existing Functionality
- Factory data across production, machines, maintenance, quality, and energy is available in Django, but currently viewed through operational screens.

#### C. Fully Implemented Functionality (Backend)
- Rich historical records exist across all 5 operational domains.

#### D. Partially Implemented Functionality
- Reporting metadata exists across individual models, but no unified reports catalog view is mounted.

#### E. Missing Functionality (Frontend)
- Dedicated `ReportsAnalyticsScreen` matching Screen 12:
  - Header: "Reports & Analytics" with filter pills `[Today, This Week, This Month]`.
  - 5 Report cards list:
    1. `Production Report` — "Output, Orders, Downtime" — Button: `View`
    2. `Machine Health Report` — "Vibration, Temperature, Trends" — Button: `View`
    3. `Maintenance Report` — "Tickets, MTTR, Costs" — Button: `View`
    4. `Quality Report` — "Defects, Batches, Trends" — Button: `View`
    5. `Energy Report` — "Consumption, Savings" — Button: `View`

#### F. Django API Endpoints Used
- `GET /api/v1/production/overview/`
- `GET /api/v1/machines/`
- `GET /api/v1/maintenance/tickets/`
- `GET /api/v1/inspections/`
- `GET /api/v1/energy/readings/`

#### G. Database Models Involved
- Models across all 5 operational apps.

#### H. AI Agent Integrations
- Aggregated summaries generated across the multi-agent fleet.

#### I. Data Source Classification
- **Database-backed simulated data**: Historical database records in SQLite.

#### J. Existing Test Coverage
- Needs new Flutter widget test.

#### K. Current UI Differences Compared with Reference
- Current: No dedicated reports catalog.
- Reference: Clean card list with time filters and direct "View" actions.

#### L. Required UI Improvements
- Create new `ReportsAnalyticsScreen` implementing the exact Screen 12 layout, with "View" buttons navigating directly to the corresponding domain screen or opening an analytical report modal.

#### M. Required Backend Improvements
- None required.

#### N. Recommendation
- **Newly Created (Frontend)**: Build `reports_analytics_screen.dart` acting as the reporting hub.

---

### Screen 13: AI Automation Log

#### A. Existing Corresponding Flutter Screen or Widget
- Primary: [audit_trail_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/audit_trail_screen.dart)
- Secondary: [ai_agent_operations_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/ai_agent_operations_screen.dart) (Execution History).

#### B. Existing Functionality
- Immutable audit trail tracking system events, agent tool invocations, approval sign-offs, and machine state transitions.

#### C. Fully Implemented Functionality
- Backend logs every autonomous event with timestamp, agent type, action name, idempotency key, and status (`SUCCESS`, `PENDING_APPROVAL`, `FAILED`).
- Existing `AuditTrailScreen` fetches from `/api/v1/audit-logs/`.

#### D. Partially Implemented Functionality
- Existing `AuditTrailScreen` renders dense cryptographic JSON blocks and complex filter trees, rather than the clean, readable 4-column table shown in Screen 13.

#### E. Missing Functionality
- Clean, compact table layout matching Screen 13:
  - Header: "AI Automation Log" with dropdown `All Events ▼`.
  - Columns: `Time` | `Agent` | `Action` | `Result`
  - Sample rows:
    - 10:24 | Machine Health | Detected vibration anomaly | Success (green)
    - 10:25 | Orchestrator | Created incident #458 | Success (green)
    - 10:25 | Maintenance | Created ticket MT-458 | Success (green)
    - 10:26 | Production | Calculated production impact | Success (green)
    - 10:26 | Inventory | Checked bearing stock | Success (green)
    - 10:27 | Orchestrator | Requested schedule approval | Pending (amber)
    - 10:28 | Machine Health | Re-checked vibration (improved) | Success (green)

#### F. Django API Endpoints Used
- `GET /api/v1/executions/`
- `GET /api/v1/audit-logs/`

#### G. Database Models Involved
- `apps.ai_agents.models.AgentAction`
- `apps.ai_agents.models.AgentExecution`
- `apps.audit_logs.models.AuditLog`

#### H. AI Agent Integrations
- All agent actions logged automatically by `apps.ai_agents.autonomous_orchestrator`.

#### I. Data Source Classification
- **Database-backed simulated data**: Live event records in SQLite.

#### J. Existing Test Coverage
- [audit_trail_screen_test.dart](file:///c:/Users/projects/texora-ai/frontend/test/audit_trail_screen_test.dart)

#### K. Current UI Differences Compared with Reference
- Current: Dark navy screen with JSON payload inspector.
- Reference: Clean white card table with colored success/pending badges.

#### L. Required UI Improvements
- Restyle or create a focused `AIAutomationLogView` matching Screen 13, keeping the full cryptographic inspector accessible via row drill-down.

#### M. Required Backend Improvements
- None required.

#### N. Recommendation
- **Extend & Reorganize**: Present the clean reference table as the default view, preserving the cryptographic audit inspector for deep compliance audits.

---

## 3. Summary Comparison Matrix

| Ref # | Reference Screen Name | Existing Flutter Screen / Widget | Backend App / API | Status | Recommendation |
|---|---|---|---|---|---|
| **1** | Main Dashboard | `executive_command_center_screen.dart` | `digital_twin`, `production`, `energy`, `quality` | Existing, dark console | **Extend & Reorganize** |
| **2** | AI Agents | `ai_agent_operations_screen.dart` | `ai_agents` (`/api/v1/agents/`) | Existing, technical view | **Extend & Reorganize** |
| **3** | Live Machine Monitoring | `machine_health_agent_screen.dart` | `machines` (`/api/v1/machines/`) | Existing, card/gauge view | **Extend** to Table View |
| **4** | AI Incident Overview | `incident_intelligence_screen.dart` | `incidents`, `machines` | Existing, dark view | **Reorganize & Extend** |
| **5** | AI Analysis | `incident_intelligence_screen.dart` | `ai_agents`, `incidents` | Partially existing | **Extend** as Tab 2 |
| **6** | Maintenance Tickets | `maintenance_execution_screen.dart` | `maintenance` (`/api/v1/maintenance/tickets/`) | Existing, execution view | **Extend** with Table View |
| **7** | Production Overview | `production_intelligence_screen.dart` | `production` (`/api/v1/production/overview/`) | Existing, capacity view | **Extend** with Trend & Orders |
| **8** | Production Impact & Recovery | `what_if_simulation_screen.dart` | `digital_twin`, `production` | Existing, parametric view | **Reorganize & Extend** |
| **9** | Inventory (Auto Check) | Backend ready, no dedicated screen | `inventory` (`/api/v1/inventory/items/`) | Backend complete, UI missing | **Newly Created (Frontend)** |
| **10** | Quality Monitoring | Backend ready, no dedicated screen | `quality` (`/api/v1/inspections/`) | Backend complete, UI missing | **Newly Created (Frontend)** |
| **11** | Energy Management | Backend ready, no dedicated screen | `energy` (`/api/v1/energy/readings/`) | Backend complete, UI missing | **Newly Created (Frontend)** |
| **12** | Reports & Analytics | Backend data ready, no dedicated screen | Cross-app endpoints | Backend complete, UI missing | **Newly Created (Frontend)** |
| **13** | AI Automation Log | `audit_trail_screen.dart` | `audit_logs`, `ai_agents` | Existing, raw JSON view | **Extend & Reorganize** |
