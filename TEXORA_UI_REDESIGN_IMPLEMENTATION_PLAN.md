# Texora AI — UI Redesign Implementation Plan & Migration Roadmap

**Reference Specification**: [reference_13_screens.png](file:///c:/Users/projects/texora-ai/reference_13_screens.png)  
**Date**: October 14, 2026  
**Auditor & Architect**: Principal Flutter Web Architect & Senior Django REST Framework Engineer  

---

## 1. Architectural Strategy & Safety Principles

1. **Zero Downtime / Zero Regressions**: The redesign must strictly preserve all existing automated test suites, widget test contracts, backend REST APIs, and autonomous simulation logic.
2. **Preserve Advanced Capabilities**: The 13 reference screens provide the primary visual specification, but Texora AI's existing advanced operational capabilities (Factory Digital Twin, Incident Intelligence, Approval Center, Audit Trail, Phase 15 Production Intelligence, Maintenance Execution Center, and Factory Copilot) must remain accessible and functional.
3. **Evidence-Based Staged Migration**: Migration is partitioned into 6 distinct stages (Stage A through Stage F). Each stage defines exact files to reuse, files to modify, new widgets, risks, test criteria, and verification steps.
4. **Approval Gate Before Execution**: No code changes will be committed until the user approves this implementation plan.

---

## 2. Target Navigation Architecture

The sidebar navigation will be structured into two clear tiers:
1. **MAIN OPERATIONS (The 9 Core Reference Screens)**
2. **ADVANCED OPERATIONS & GOVERNANCE (Existing Deep Enterprise Features)**
3. **GLOBAL AI COPILOT (Grounded Consultation)**

```mermaid
graph TD
    Root[Texora AI App Shell] --> TopHeader[Header: Search | Alerts | Factory Manager Profile]
    Root --> Sidebar[Sidebar: Dark Navy #0B132B]
    Root --> Workspace[Workspace Canvas: #F8FAFC]
    Root --> FloatingCopilot[Floating / Full-Screen AI Copilot]

    subgraph "Main Operations (Reference UI)"
        Sidebar --> Nav1[1. Dashboard]
        Sidebar --> Nav2[2. AI Agents]
        Sidebar --> Nav3[3. Machines]
        Sidebar --> Nav4[4. Production]
        Sidebar --> Nav5[5. Quality]
        Sidebar --> Nav6[6. Maintenance]
        Sidebar --> Nav7[7. Inventory]
        Sidebar --> Nav8[8. Energy]
        Sidebar --> Nav9[9. Reports]
    end

    subgraph "Advanced Operations (Preserved Capabilities)"
        Sidebar --> Adv1[Factory Digital Twin 3D]
        Sidebar --> Adv2[Incident Intelligence]
        Sidebar --> Adv3[Autonomous Recovery & What-If]
        Sidebar --> Adv4[Approval Center]
        Sidebar --> Adv5[Immutable Audit Trail]
        Sidebar --> Adv6[AI Agent Fleet Operations]
        Sidebar --> Adv7[System Diagnostics]
    end

    subgraph "Subviews & Drill-Downs"
        Nav3 --> Screen4[4. AI Incident Overview]
        Screen4 --> Screen5[5. AI Analysis]
        Nav4 --> Screen8[8. Production Impact & Recovery]
        Nav4 --> Phase15[Phase 15 Capacity Routing]
        Nav6 --> MntExec[Technician Execution Center]
        Nav9 --> Screen13[13. AI Automation Log]
    end
```

### Route & Index Mapping

| Index / Route | Nav Label | Target Screen View | Subviews / Drill-Downs Accessible |
|---|---|---|---|
| **0** | `Dashboard` | **Screen 1: Main Dashboard (Home)** | Factory Flow schematic, Live AI Activity feed, Expo trigger |
| **1** | `AI Agents` | **Screen 2: AI Agents** | 6 Agent Cards, 5-stage orchestration pipeline, LLM metrics dialog |
| **2** | `Machines` | **Screen 3: Live Machine Monitoring** | Drill-down row click -> **Screen 4: Incident Overview** -> **Screen 5: AI Analysis** |
| **3** | `Production` | **Screen 7: Production Overview** | **Screen 8: Production Impact & Recovery**, Phase 15 Capacity Routing, Progression Simulator |
| **4** | `Quality` | **Screen 10: Quality Monitoring** | Batch inspection records, defect breakdown, defect trend chart |
| **5** | `Maintenance` | **Screen 6: Maintenance Tickets** | Drill-down ticket click -> Technician Inspection, Parts Consumption, Telemetry Verification |
| **6** | `Inventory` | **Screen 9: Inventory (Auto Check)** | Spare parts stock table, safety stock levels, AI inventory check |
| **7** | `Energy` | **Screen 11: Energy Management** | Hourly consumption bar chart, peak hour tracking, AI energy insights |
| **8** | `Reports` | **Screen 12: Reports & Analytics** | **Screen 13: AI Automation Log**, domain report modals (Production, Machines, Maintenance, Quality, Energy) |
| **9** | `Factory Digital Twin` | **Advanced: Factory Digital Twin** | 3D factory layout nodes, machine coordinates, dependency graph |
| **10** | `Incident Intelligence` | **Advanced: Incident Intelligence** | Full incident investigation workspace, multi-agent traces |
| **11** | `Autonomous Recovery` | **Advanced: Factory Recovery** | Parametric What-If simulation, Strategy A/B/C generator |
| **12** | `Approval Center` | **Advanced: Approval Center** | Managerial human-in-the-loop review, approve/reject/revise |
| **13** | `Audit Trail` | **Advanced: Audit Trail** | Cryptographic compliance ledger, raw JSON inspector |
| **14** | `System Diagnostics` | **Advanced: Backend Status** | Worker daemons, Redis/Celery broker, latency probes |
| **Global** | `AI Copilot` | **Factory AI Copilot** | Grounded consultation, citation links, contextual suggestions |

---

## 3. Responsive Layout & Breakpoint Specifications

To prevent `RenderFlex` overflow errors across all devices and screen sizes:

| Breakpoint Range | Target Devices | Sidebar Mode | Layout Strategy |
|---|---|---|---|
| **≥ 1440px** | 4K / Large Desktop | Expanded (`240px`) | 4-column KPI cards, 70/30 split content cards, full data tables. |
| **1280px - 1439px** | Standard Desktop / Laptop | Expanded (`240px`) | 4-column KPI cards, flexible tables, 60/40 or stacked content cards. |
| **1024px - 1279px** | Small Laptop / iPad Pro | Collapsed (`72px`) | 2x2 KPI card grid, stacked layout cards, horizontal scroll on tables. |
| **768px - 1023px** | Tablet Portrait | Collapsed Rail / Drawer | 2x2 KPI card grid, single column content, compact table cells. |
| **480px - 767px** | Large Mobile Phone | Drawer Navigation | 1-column KPI cards, single column layout, card-based table cards. |
| **≤ 479px** | Compact Mobile | Drawer Navigation | Compact headers, truncated badges, vertical scrolling. |

---

## 4. Phased Development Roadmap

### STAGE A: Global Application Shell, Theme & Design Tokens

- **Objective**: Establish the foundation of the new design system without modifying screen contents yet.
- **Files to Modify**:
  - [app_colors.dart](file:///c:/Users/projects/texora-ai/frontend/lib/core/constants/app_colors.dart): Add `TexoraColors` palette while preserving backward-compatible legacy constants.
  - [app_theme.dart](file:///c:/Users/projects/texora-ai/frontend/lib/core/theme/app_theme.dart): Configure Light Theme with `#F8FAFC` scaffold background, `#FFFFFF` cards, and `#0B132B` sidebar.
  - [app_sidebar.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/widgets/app_sidebar.dart): Update sidebar to render the 9 main navigation items + collapsible Advanced Operations section with royal blue `#2563EB` active highlight.
  - [main_shell_screen.dart](file:///c:/Users/projects/texora-ai/frontend/lib/presentation/screens/main_shell_screen.dart): Update header banner (`60px` white bar with search icon, notification bell, user profile) and route index router.
- **New Widgets Required**:
  - `TexoraPageHeader`
  - `TexoraCard`
  - `TexoraKpiCard`
  - `TexoraStatusBadge`
- **Backend Dependencies**: None.
- **Risks**: Breaking existing widget tests that look for specific dark theme tokens or sidebar labels.
- **Mitigation**: Retain exact text tokens (`AUTONOMOUS FACTORY INTELLIGENCE`, `PHASE 15`, etc.) in the widget hierarchy.
- **Verification Criteria**:
  - `flutter analyze` passes with 0 errors.
  - All 95 existing flutter tests pass.

---

### STAGE B: Dashboard, AI Agents & Live Machine Monitoring (Screens 1, 2, 3)

- **Objective**: Redesign the top three reference screens.
- **Files to Modify / Create**:
  - Modify `executive_command_center_screen.dart` to render the clean white reference Dashboard (Screen 1): 4 KPI cards, 5-department schematic card on left, Live AI Activity timeline on right.
  - Modify `ai_agent_operations_screen.dart` to render the 6-agent white card grid + horizontal 5-stage orchestration pipeline (Screen 2), preserving the LLM detail modal.
  - Modify `machine_health_agent_screen.dart` to add the high-density Live Machine Monitoring table (Screen 3) with department filter tabs (`All (120)`, `Spinning (28)`, etc.) and sparklines.
- **New Widgets Required**:
  - `TexoraAgentCard`
  - `TexoraDataTable`
  - `TexoraActivityTimeline`
- **Backend Dependencies**: `/api/v1/digital-twin/snapshot/`, `/api/v1/agents/`, `/api/v1/machines/`.
- **Verification Criteria**:
  - Screens render with 100% data binding to live Django backend.
  - Clicking a machine in Screen 3 triggers navigation callback to Screen 4.

---

### STAGE C: Incident Overview, AI Analysis & Maintenance Tickets (Screens 4, 5, 6)

- **Objective**: Implement the machine incident drill-down and maintenance work order overview.
- **Files to Modify / Create**:
  - Reorganize `incident_intelligence_screen.dart` into a 5-tab detail screen:
    - Tab 1: **Screen 4: AI Incident Overview** (machine thumbnail, out-of-spec metrics, AI summary with 87% confidence, "View Full AI Analysis →" button).
    - Tab 2: **Screen 5: AI Analysis** (Root Cause Analysis checklist, AI Recommendation card, "Create Maintenance Ticket", "View Production Impact").
  - Modify `maintenance_execution_screen.dart` to provide the top-level **Screen 6: Maintenance Tickets** overview table with status tabs (`All (24)`, `Open (5)`, `In Progress (8)`, `Completed (11)`), with row click navigating into the existing technician execution & telemetry verification console.
- **New Widgets Required**:
  - `TexoraTabContainer`
  - `TexoraChecklistCard`
- **Backend Dependencies**: `/api/v1/incidents/`, `/api/v1/autonomous/incident-workflow/`, `/api/v1/maintenance/tickets/`.
- **Verification Criteria**:
  - Creating a maintenance ticket dispatches a real POST to `/api/v1/maintenance/tickets/`.
  - Technician lifecycle transitions and verification gates remain 100% functional.

---

### STAGE D: Production Overview, Production Recovery & Inventory (Screens 7, 8, 9)

- **Objective**: Redesign Production Intelligence and create the Inventory Auto Check screen.
- **Files to Modify / Create**:
  - Reorganize `production_intelligence_screen.dart` to render **Screen 7: Production Overview** (4 KPI cards, circular target gauge, hourly Production Trend chart, Current Orders card) with subtabs for Phase 15 Capacity Routing and Progression Simulation.
  - Implement **Screen 8: Production Impact & Recovery** inside the recovery workflow (Impact details, AI recovery plan with 85% confidence, "Approve & Apply Plan" button linked to Approval Center).
  - Create `inventory_screen.dart` implementing **Screen 9: Inventory (Auto Check)** (search bar, stock table with Cotton Yarn, Bearing 6205, V-Belt, Lubricating Oil, Dye Chemicals + AI Inventory Check checklist).
- **New Widgets Required**:
  - `TexoraHourlyTrendChart`
  - `TexoraCircularProgressGauge`
- **Backend Dependencies**: `/api/v1/production/overview/`, `/api/v1/production/orders/`, `/api/v1/inventory/items/`.
- **Verification Criteria**:
  - Phase 15 capacity simulation progression (`advance`, `breakdown`, `recover`) remains intact.
  - Low stock warning flags on Bearing (6205) and Dye Chemicals match real database stock values.

---

### STAGE E: Quality, Energy, Reports & AI Automation Log (Screens 10, 11, 12, 13)

- **Objective**: Build Quality, Energy, Reports, and the AI Automation Log.
- **Files to Modify / Create**:
  - Create `quality_monitoring_screen.dart` implementing **Screen 10: Quality Monitoring** (Overall Quality 98.2%, Total Batches 38, Defects 0.8%, Quality Trend chart, Top Defects progress bars).
  - Create `energy_management_screen.dart` implementing **Screen 11: Energy Management** (Total Consumption 18,200 kWh, Cost ₹18,200, Hourly Consumption green bar chart, AI Insights card).
  - Create `reports_analytics_screen.dart` implementing **Screen 12: Reports & Analytics** (Time filters `Today / This Week / This Month`, 5 report cards with "View" action).
  - Implement **Screen 13: AI Automation Log** as a dedicated subview in Reports (or linked to Audit Trail) with columns `Time` | `Agent` | `Action` | `Result`.
- **New Widgets Required**:
  - `TexoraBarChart`
  - `TexoraReportCard`
- **Backend Dependencies**: `/api/v1/inspections/`, `/api/v1/energy/readings/`, `/api/v1/audit-logs/`.
- **Verification Criteria**:
  - Data renders directly from live database tables.
  - Filter chips update chart and card values dynamically.

---

### STAGE F: Factory Copilot, Advanced Operations, Responsive Polish & Final Verification

- **Objective**: Harmonize all screens, verify responsive breakpoints, and perform end-to-end browser audits.
- **Files to Modify**:
  - Refine `floating_copilot_assistant.dart` and `factory_copilot_screen.dart` with matching pale blue-gray styling and citation badges.
  - Polish Advanced Operations screens (Digital Twin, Approval Center, Audit Trail, Diagnostics) to ensure seamless visual harmony.
  - Test all 8 responsive breakpoints (`1920px`, `1440px`, `1280px`, `1024px`, `800px`, `480px`, `360px`, `320px`).
- **Verification Criteria**:
  - `python manage.py check`: 0 issues.
  - `pytest backend/tests`: 152 passed.
  - `flutter analyze`: 0 issues.
  - `flutter test`: all tests passing.
  - Live browser recording validating all 13 screens.

---

## 5. Verification Checklist

```markdown
- [ ] 1. Django system check identifies zero issues.
- [ ] 2. All 152 backend pytest tests pass.
- [ ] 3. Flutter analyze reports zero warnings or errors.
- [ ] 4. All 95 existing Flutter unit and widget tests pass.
- [ ] 5. New widget tests added for Screens 9, 10, 11, 12.
- [ ] 6. Live API verification against running Django server on 127.0.0.1:8000.
- [ ] 7. Machine state mutations in Django reflect dynamically in the UI.
- [ ] 8. Copilot responses cite real database records.
- [ ] 9. Phase 15 capacity simulation progression functions without regressions.
- [ ] 10. Autonomous Expo Demo workflow executes from end to end.
- [ ] 11. Visual comparison confirms high fidelity with reference_13_screens.png.
```
