from django.urls import path
from .views import (
    DigitalTwinSnapshotView,
    DigitalTwinDepartmentsView,
    DigitalTwinMachineDetailView,
    FactoryDependencyGraphView,
    WhatIfScenarioListView,
    WhatIfScenarioDetailView,
    WhatIfSimulateView,
    WhatIfResultsView,
    WhatIfAIExplainView,
    WhatIfDemoScenariosView,
    WhatIfLoadDemoView,
)

app_name = "digital_twin"

urlpatterns = [
    # Factory Digital Twin APIs
    path("digital-twin/snapshot/", DigitalTwinSnapshotView.as_view(), name="digital-twin-snapshot"),
    path("digital-twin/departments/", DigitalTwinDepartmentsView.as_view(), name="digital-twin-departments"),
    path("digital-twin/machines/<str:machine_code>/", DigitalTwinMachineDetailView.as_view(), name="digital-twin-machine-detail"),
    path("digital-twin/dependency-graph/", FactoryDependencyGraphView.as_view(), name="digital-twin-dependency-graph"),

    # What-If Simulation APIs
    path("digital-twin/what-if/scenarios/", WhatIfScenarioListView.as_view(), name="what-if-scenario-list"),
    path("digital-twin/what-if/scenarios/<str:scenario_id>/", WhatIfScenarioDetailView.as_view(), name="what-if-scenario-detail"),
    path("digital-twin/what-if/scenarios/<str:scenario_id>/simulate/", WhatIfSimulateView.as_view(), name="what-if-simulate"),
    path("digital-twin/what-if/scenarios/<str:scenario_id>/results/", WhatIfResultsView.as_view(), name="what-if-results"),
    path("digital-twin/what-if/scenarios/<str:scenario_id>/ai-explain/", WhatIfAIExplainView.as_view(), name="what-if-ai-explain"),
    path("digital-twin/what-if/demo-scenarios/", WhatIfDemoScenariosView.as_view(), name="what-if-demo-scenarios"),
    path("digital-twin/what-if/demo-scenarios/<str:demo_code>/load/", WhatIfLoadDemoView.as_view(), name="what-if-load-demo"),
]
