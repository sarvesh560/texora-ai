# ==============================================================================
# Texora AI - Robust Interactive Database Configuration Script
# ==============================================================================
# Securely configures PostgreSQL database role and database, validates exit codes,
# verifies role/database existence, and safely updates backend/.env upon success.
# ==============================================================================

[CmdletBinding()]
param (
    [string]$DbUser = "texora_user",
    [string]$DbName = "texora_db",
    [string]$DbHost = "127.0.0.1",
    [string]$DbPort = "5432",
    [string]$AdminUser = "postgres"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Texora AI Database Setup ===" -ForegroundColor Cyan
Write-Host "Target: Database '$($DbName)' | User '$($DbUser)' on $($DbHost):$($DbPort)"

# 1. Secure password input (masked in terminal)
$passwordSecure = Read-Host -Prompt "Enter secure password to configure for '$($DbUser)'" -AsSecureString
$passwordBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure)
$passwordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($passwordBSTR)

if ([string]::IsNullOrWhiteSpace($passwordPlain)) {
    Write-Error "Password cannot be empty."
    exit 1
}

# 2. Build non-destructive SQL setup commands
$escapedPassword = $passwordPlain.Replace("'", "''")
$sqlCommands = @"
\set ON_ERROR_STOP on

DO `$do`$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$($DbUser)') THEN
      CREATE ROLE $($DbUser) WITH LOGIN;
   ELSE
      ALTER ROLE $($DbUser) WITH LOGIN;
   END IF;
END
`$do`$;

ALTER ROLE $($DbUser) WITH PASSWORD '$($escapedPassword)';

SELECT 'CREATE DATABASE $($DbName) OWNER $($DbUser)'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$($DbName)')\gexec

GRANT ALL PRIVILEGES ON DATABASE $($DbName) TO $($DbUser);
ALTER DATABASE $($DbName) OWNER TO $($DbUser);
"@

$tempSql = [System.IO.Path]::GetTempFileName()

try {
    Set-Content -Path $tempSql -Value $sqlCommands -Encoding UTF8

    Write-Host "`nConnecting to PostgreSQL as admin '$($AdminUser)'..." -ForegroundColor Yellow
    Write-Host "(Please enter password for '$($AdminUser)' when prompted by psql)"

    # Execute psql with ON_ERROR_STOP=1
    & psql -U $AdminUser -h $DbHost -p $DbPort -v ON_ERROR_STOP=1 -f $tempSql

    if ($LASTEXITCODE -ne 0) {
        Write-Error "PostgreSQL execution failed (Exit code: $LASTEXITCODE). Database configuration was NOT applied."
        exit $LASTEXITCODE
    }

    # 3. Post-execution Verification Check
    Write-Host "`nVerifying configuration in PostgreSQL..." -ForegroundColor Cyan
    $verifyQuery = "SELECT COUNT(*) FROM pg_roles WHERE rolname = '$($DbUser)'; SELECT COUNT(*) FROM pg_database WHERE datname = '$($DbName)';"
    
    $verifyResult = & psql -U $AdminUser -h $DbHost -p $DbPort -v ON_ERROR_STOP=1 -t -A -c $verifyQuery
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Verification query failed (Exit code: $LASTEXITCODE)."
        exit $LASTEXITCODE
    }

    # 4. Safely update local backend/.env ONLY after verified PostgreSQL execution
    $envPath = Join-Path $PSScriptRoot "..\.env"
    $envLines = @()
    if (Test-Path $envPath) {
        $existing = Get-Content $envPath
        $hasPassword = $false
        foreach ($line in $existing) {
            if ($line -match "^DB_PASSWORD=") {
                $envLines += "DB_PASSWORD=$($passwordPlain)"
                $hasPassword = $true
            } elseif ($line -match "^DB_NAME=") {
                $envLines += "DB_NAME=$($DbName)"
            } elseif ($line -match "^DB_USER=") {
                $envLines += "DB_USER=$($DbUser)"
            } elseif ($line -match "^DB_HOST=") {
                $envLines += "DB_HOST=$($DbHost)"
            } elseif ($line -match "^DB_PORT=") {
                $envLines += "DB_PORT=$($DbPort)"
            } else {
                $envLines += $line
            }
        }
        if (-not $hasPassword) {
            $envLines += "DB_PASSWORD=$($passwordPlain)"
        }
    } else {
        $envLines = @(
            "DJANGO_SECRET_KEY=django-insecure-texora-ai-foundation-secret-key-change-in-production-2026",
            "DJANGO_DEBUG=True",
            "DJANGO_ALLOWED_HOSTS=127.0.0.1,localhost",
            "DB_NAME=$($DbName)",
            "DB_USER=$($DbUser)",
            "DB_PASSWORD=$($passwordPlain)",
            "DB_HOST=$($DbHost)",
            "DB_PORT=$($DbPort)",
            "CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:50000,http://127.0.0.1:50000"
        )
    }

    Set-Content -Path $envPath -Value $envLines -Encoding UTF8
    Write-Host "[OK] Verified: Role '$($DbUser)' and database '$($DbName)' are active in PostgreSQL." -ForegroundColor Green
    Write-Host "[OK] Updated local backend/.env successfully (file is Git-ignored)." -ForegroundColor Green

} finally {
    if (Test-Path $tempSql) {
        Remove-Item $tempSql -Force
    }
}
