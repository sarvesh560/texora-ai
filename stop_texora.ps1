<#
.SYNOPSIS
    Texora AI — Graceful Process Shutdown Script
.DESCRIPTION
    Safely terminates Texora AI background workers, Django development server, and Flutter Web processes.
#>

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "    TEXORA AI — SHUTDOWN OPERATIONAL PROCESSES                        " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$WorkspaceRoot = $PSScriptRoot
$BackendDir = Join-Path $WorkspaceRoot "backend"
$PythonExe = Join-Path $BackendDir ".venv\Scripts\python.exe"
if (-not (Test-Path $PythonExe)) { $PythonExe = "python" }

# 1. Update Worker Heartbeat records to STOPPED in DB
try {
    Set-Location $BackendDir
    & $PythonExe manage.py shell -c "from apps.incidents.models import WorkerHeartbeat; WorkerHeartbeat.objects.all().update(status='STOPPED'); print('Updated worker status in database.')"
} catch {
    Write-Host "Warning: Could not update worker heartbeat status in database." -ForegroundColor Yellow
}

# 2. Terminate Lockfiles
$lockFiles = @("anomaly_detector.lock", "orchestrator_worker.lock")
foreach ($lf in $lockFiles) {
    $p = Join-Path $BackendDir $lf
    if (Test-Path $p) {
        Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
    }
}

# 3. Stop Python processes related to Texora
$pyProcs = Get-Process -Name "python" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*runserver*" -or
    $_.CommandLine -like "*run_anomaly_detector*" -or
    $_.CommandLine -like "*run_orchestrator_worker*"
}

if ($pyProcs) {
    Write-Host "Terminating background Python worker processes..." -ForegroundColor Yellow
    foreach ($p in $pyProcs) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Write-Host "  -> Stopped Process PID $($p.Id)" -ForegroundColor Gray
    }
} else {
    Write-Host "No active Texora Python worker processes detected." -ForegroundColor Green
}

# 4. Stop Flutter/Dart processes if any
$flutterProcs = Get-Process -Name "dart" -ErrorAction SilentlyContinue
if ($flutterProcs) {
    Write-Host "Stopping Flutter development server processes..." -ForegroundColor Yellow
    foreach ($p in $flutterProcs) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}

Set-Location $WorkspaceRoot
Write-Host "`n[OK] Texora AI operational services stopped gracefully." -ForegroundColor Green
