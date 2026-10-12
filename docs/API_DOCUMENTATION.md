# Texora AI — REST API Documentation (v1)

**Base URL:** `http://127.0.0.1:8000/api/v1/`

---

## 1. System Health Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/v1/health/` | General API health status |
| `GET` | `/api/v1/health/readiness/` | Database readiness & dependency health |

---

## 2. Factory & Machinery Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET`, `POST` | `/api/v1/factories/` | List & create factories |
| `GET`, `POST` | `/api/v1/departments/` | List & create departments (Spinning, Weaving, Knitting, Dyeing, Finishing) |
| `GET`, `POST` | `/api/v1/production-lines/` | List & create production lines |
| `GET`, `POST` | `/api/v1/machine-types/` | Machine catalog & types |
| `GET`, `POST` | `/api/v1/machines/` | List & create machine assets |
| `GET` | `/api/v1/machines/{id}/telemetry/` | Latest 100 telemetry sensor readings for a machine |
| `GET` | `/api/v1/machines/{id}/history/` | Machine state transition history |
| `GET`, `POST` | `/api/v1/operating-limits/` | Sensor warning & critical operating limits |
| `GET`, `POST` | `/api/v1/telemetry/` | Time-series telemetry readings |
| `GET` | `/api/v1/state-history/` | Machine state audit log |

---

## 3. Production & Manufacturing Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET`, `POST` | `/api/v1/orders/` | Production orders (fabric/yarn specs, deadlines, progress) |
| `GET`, `POST` | `/api/v1/batches/` | Manufacturing batches |
| `GET`, `POST` | `/api/v1/schedules/` | Machine shift assignments |
| `GET`, `POST` | `/api/v1/outputs/` | Periodic production output records |
| `GET`, `POST` | `/api/v1/delays/` | Bottleneck & delay incidents |

---

## 4. Maintenance & Asset Health Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET`, `POST` | `/api/v1/tickets/` | Maintenance tickets (priority, status, parts, technician) |
| `GET`, `POST` | `/api/v1/activities/` | Maintenance activity tasks |
| `GET` | `/api/v1/history/` | Historical service records & downtime |

---

## 5. Quality, Inventory & Energy Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET`, `POST` | `/api/v1/inspections/` | Laboratory & batch quality inspections |
| `GET`, `POST` | `/api/v1/defects/` | Textile quality defects |
| `GET`, `POST` | `/api/v1/items/` | Inventory spare parts, dyes & raw cotton items |
| `GET` | `/api/v1/items/low_stock/` | Items at or below reorder point |
| `GET`, `POST` | `/api/v1/transactions/` | Stock movement & AI reservations |
| `GET`, `POST` | `/api/v1/spare-part-requirements/` | Machine spare part requirements matrix |
| `GET`, `POST` | `/api/v1/readings/` | Sub-metered energy readings (kW, kWh, power factor) |

---

## 6. Autonomous AI & Governance Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET`, `POST` | `/api/v1/incidents/` | Factory operational incidents |
| `GET`, `POST` | `/api/v1/anomalies/` | Sensor anomalies & confidence scores |
| `GET`, `POST` | `/api/v1/agents/` | AI Agent definitions & permitted tool whitelists |
| `GET`, `POST` | `/api/v1/executions/` | AI Agent execution runs |
| `GET` | `/api/v1/decisions/` | AI Agent structured decisions & risk ratings |
| `GET` | `/api/v1/actions/` | Idempotent agent tool actions |
| `GET`, `POST` | `/api/v1/approvals/` | Manager approval requests |
| `POST` | `/api/v1/approvals/{id}/approve/` | Human approval action (updates linked agent action) |
| `POST` | `/api/v1/approvals/{id}/reject/` | Human rejection action |
| `GET` | `/api/v1/audit-logs/` | System-wide immutable audit trail |
