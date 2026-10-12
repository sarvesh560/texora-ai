from django.urls import path
from .views import (
    SimulationStatusView,
    SimulationStartView,
    SimulationPauseView,
    SimulationResumeView,
    SimulationStopView,
    SimulationTickView,
    SimulationInjectScenarioView,
    SimulationClearScenariosView,
    SimulationSummaryView,
)

app_name = "simulation"

urlpatterns = [
    path("simulation/status/", SimulationStatusView.as_view(), name="simulation-status"),
    path("simulation/start/", SimulationStartView.as_view(), name="simulation-start"),
    path("simulation/pause/", SimulationPauseView.as_view(), name="simulation-pause"),
    path("simulation/resume/", SimulationResumeView.as_view(), name="simulation-resume"),
    path("simulation/stop/", SimulationStopView.as_view(), name="simulation-stop"),
    path("simulation/tick/", SimulationTickView.as_view(), name="simulation-tick"),
    path("simulation/inject-scenario/", SimulationInjectScenarioView.as_view(), name="simulation-inject-scenario"),
    path("simulation/clear-scenarios/", SimulationClearScenariosView.as_view(), name="simulation-clear-scenarios"),
    path("simulation/summary/", SimulationSummaryView.as_view(), name="simulation-summary"),
]
