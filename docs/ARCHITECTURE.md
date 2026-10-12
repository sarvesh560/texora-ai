# Texora AI — System Architecture & Design

## 1. High-Level Architecture

```text
+-------------------------------------------------------------------------+
|                         Flutter Web Frontend                            |
|             (Material 3, Navy Sidebar, Real-time Visualizer)            |
+-------------------------------------------------------------------------+
                                    │
                                    │ HTTP / REST (CORS Controlled)
                                    ▼
+-------------------------------------------------------------------------+
|                  Django REST Framework (DRF) Core                       |
|           /api/v1/health/, /api/v1/machines/, /api/v1/agents/           |
+-------------------------------------------------------------------------+
          │                                              │
          │ Database ORM                                 │ Dispatcher
          ▼                                              ▼
+-------------------+                          +--------------------------+
| PostgreSQL /      |                          | Autonomous AI Agents     |
| SQLite Storage    |                          | - Machine Health Agent   |
| - Telemetry data  |                          | - Maintenance Agent      |
| - Audit logs      |                          | - Quality & Production   |
| - Approvals       |                          | - Energy & Inventory     |
+-------------------+                          +--------------------------+
```

---

## 2. Phased Architecture Road Map

| Phase | Milestone | Scope |
| :--- | :--- | :--- |
| **Phase 0** | Environment Audit | Tools, dependencies, and environment verification. |
| **Phase 1** | Project Foundation | Modular Django, DRF, SQLite/PostgreSQL, Flutter Web shell, health APIs. |
| **Phase 2** | Database Architecture | Factory, department, machine, and operational models. |
| **Phase 3** | Factory Simulation | Realistic textile telemetry generator (Spinning, Weaving, Knitting, Dyeing, Finishing). |
| **Phase 4** | Autonomous Monitoring | Background telemetry evaluation and anomaly detection engine. |
| **Phase 5** | First AI Agent | Machine Health Agent with structured tool-calling & root cause analysis. |
| **Phase 6** | Automated Maintenance | Authorized maintenance ticket creation and execution logs. |
| **Phase 7** | Multi-Agent Coordination| Production impact analysis, recovery planning, inventory allocation. |
| **Phase 8** | Approvals and Audit | Manager approval workflows and complete historical audit trail. |
| **Phase 9** | Flutter Web Interface | Complete command center dashboards and real-time visualization. |
| **Phase 10**| Live Expo Readiness | Integration testing, scenario drills, live presentation showcase. |
