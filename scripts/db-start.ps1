$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root '.pgdata'
$logFile = Join-Path $dataDir 'server.log'
$pgBin = if ($env:PG_BIN) { $env:PG_BIN } else { 'C:\Program Files\PostgreSQL\18\bin' }
$pgCtl = Join-Path $pgBin 'pg_ctl.exe'

if (-not (Test-Path -LiteralPath $pgCtl)) {
    throw "pg_ctl.exe not found at '$pgCtl'. Set PG_BIN to your PostgreSQL bin folder."
}
if (-not (Test-Path -LiteralPath $dataDir)) {
    throw "Database cluster not found at '$dataDir'. Run scripts/db-init.ps1 first."
}

& $pgCtl -D $dataDir status *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Host 'PostgreSQL is already running on port 5433.'
    exit 0
}

& $pgCtl -D $dataDir -l $logFile -o '-p 5433' -w start
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL failed to start. Check $logFile"
}
Write-Host 'PostgreSQL started on port 5433.'
