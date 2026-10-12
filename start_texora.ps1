<#
.SYNOPSIS
    Texora AI — Enterprise One-Command Local Startup Script
.DESCRIPTION
    Launches Texora AI services:
    1. Django REST Framework Backend API (Port 8000)
    2. Autonomous Anomaly Detection Engine Daemon
    3. Autonomous Factory Recovery Orchestrator Worker
    4. Flutter Web Executive Client (Port 50000)
    5. Continuous Telemetry Simulator (ONLY when -EnableSimulation / -Sandbox switch is provided)
.PARAMETER EnableSimulation
    Starts continuous physical telemetry simulation in sandbox mode.
.PARAMETER SkipFlutter
    Skips launching the Flutter Web frontend development server.
#>

param (
    [switch]$EnableSimulation,
    [switch]$SkipFlutter,
    [int]$BackendPort = 8000,
    [int]$FrontendPort = 50000
)

$ErrorActionPreference = "Stop"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "    TEXORA AI — AUTONOMOUS TEXTILE FACTORY INTELLIGENCE PLATFORM      " -ForegroundColor Cyan
Write-Host "    Operational Pipeline Startup & Health Initializer                 " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$WorkspaceRoot = $PSScriptRoot
$BackendDir = Join-Path $WorkspaceRoot "backend"
$FrontendDir = Join-Path $WorkspaceRoot "frontend"
$LogsDir = Join-Path $WorkspaceRoot "logs"
$PythonExe = Join-Path $BackendDir ".venv\Scripts\python.exe"

# Create logs directory
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

# 1. Environment Verification
if (Test-Path $PythonExe) {
    Write-Host "[1/5] Virtual Environment: $PythonExe" -ForegroundColor Green
} else {
    $PythonExe = "python"
    Write-Host "[1/5] Warning: Virtualenv not found. Using system python." -ForegroundColor Yellow
}

# 2. Port Conflict Verification Helper
function Test-PortOccupied ([int]$port) {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
    return [bool]$conn
}

Write-Host "[2/5] Verifying Service Ports..." -ForegroundColor Yellow

$backendOccupied = Test-PortOccupied $BackendPort
if ($backendOccupied) {
    Write-Host "  -> Port $BackendPort is already in use. Checking existing Django instance..." -ForegroundColor Yellow
} else {
    Write-Host "  -> Port $BackendPort is available." -ForegroundColor Green
}

# 3. Database Migration Verification
Write-Host "[3/5] Verifying Database Schema & Migrations..." -ForegroundColor Yellow
Set-Location $BackendDir
try {
    & $PythonExe manage.py migrate --no-input
    Write-Host "  -> Database schema up to date." -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Database migration failed: $_" -ForegroundColor Red
    exit 1
}

# 4. Process Launching with Log Redirection
Write-Host "[4/5] Starting Background Workers & Services..." -ForegroundColor Yellow

# A. Django API Server
if (-not $backendOccupied) {
    Write-Host "  -> Launching Django API on http://127.0.0.1:$BackendPort ..." -ForegroundColor Cyan
    $djangoLog = Join-Path $LogsDir "django_api.log"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", "cd '$BackendDir'; & '$PythonExe' manage.py runserver 127.0.0.1:$BackendPort *>&1 | Tee-Object -FilePath '$djangoLog'" -WindowStyle Minimized
} else {
    Write-Host "  -> Django server already running on port $BackendPort" -ForegroundColor Green
}

# B. Anomaly Detector Daemon
$detectorLog = Join-Path $LogsDir "anomaly_detector.log"
$detectorRunning = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*run_anomaly_detector*" }
if (-not $detectorRunning) {
    Write-Host "  -> Starting Autonomous Anomaly Detector Daemon..." -ForegroundColor Cyan
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", "cd '$BackendDir'; & '$PythonExe' manage.py run_anomaly_detector *>&1 | Tee-Object -FilePath '$detectorLog'" -WindowStyle Minimized
} else {
    Write-Host "  -> Anomaly Detector is already active." -ForegroundColor Green
}

# C. Orchestrator Worker Daemon
$orchLog = Join-Path $LogsDir "orchestrator_worker.log"
$orchRunning = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*run_orchestrator_worker*" }
if (-not $orchRunning) {
    Write-Host "  -> Starting Autonomous Factory Orchestrator Worker..." -ForegroundColor Cyan
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", "cd '$BackendDir'; & '$PythonExe' manage.py run_orchestrator_worker *>&1 | Tee-Object -FilePath '$orchLog'" -WindowStyle Minimized
} else {
    Write-Host "  -> Orchestrator Worker is already active." -ForegroundColor Green
}

# D. Continuous Telemetry Simulator (Sandbox Only)
if ($EnableSimulation) {
    Write-Host "  -> [SANDBOX MODE] Starting Continuous Telemetry Simulator..." -ForegroundColor Magenta
    & $PythonExe manage.py shell -c "from apps.simulation.engine import SimulationEngine; SimulationEngine.get_instance().start(speed_multiplier=1.0)"
    Write-Host "  -> Telemetry simulation engine started." -ForegroundColor Green
} else {
    Write-Host "  -> Production mode active (Simulated telemetry generator is OFF by default)." -ForegroundColor Gray
}

# 5. Flutter Web Frontend
if (-not $SkipFlutter) {
    Set-Location $FrontendDir
    $frontendOccupied = Test-PortOccupied $FrontendPort
    if (-not $frontendOccupied) {
        Write-Host "[5/5] Launching Flutter Web on http://localhost:$FrontendPort ..." -ForegroundColor Yellow
        $flutterLog = Join-Path $LogsDir "flutter_web.log"
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit", "-Command", "cd '$FrontendDir'; flutter run -d chrome --web-port $FrontendPort *>&1 | Tee-Object -FilePath '$flutterLog'" -WindowStyle Minimized
    } else {
        Write-Host "[5/5] Flutter Web already accessible on http://localhost:$FrontendPort" -ForegroundColor Green
    }
}

Set-Location $WorkspaceRoot

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host " [STATUS: READY] Texora AI Autonomous Operations Active" -ForegroundColor Green
Write-Host "  * Frontend UI:           http://localhost:$FrontendPort" -ForegroundColor White
Write-Host "  * API Health Endpoint:   http://127.0.0.1:$BackendPort/api/v1/health/workers/" -ForegroundColor White
Write-Host "  * Live Logs Directory:   $LogsDir" -ForegroundColor White
Write-Host "  * Graceful Shutdown:     .\stop_texora.ps1" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan
