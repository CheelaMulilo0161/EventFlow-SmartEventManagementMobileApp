$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root '.pgdata'
$pgBin = if ($env:PG_BIN) { $env:PG_BIN } else { 'C:\Program Files\PostgreSQL\18\bin' }
$pgCtl = Join-Path $pgBin 'pg_ctl.exe'

if (-not (Test-Path -LiteralPath $pgCtl)) {
    throw "pg_ctl.exe not found at '$pgCtl'. Set PG_BIN to your PostgreSQL bin folder."
}
if (-not (Test-Path -LiteralPath $dataDir)) {
    throw "Database cluster not found at '$dataDir'."
}

& $pgCtl -D $dataDir status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'PostgreSQL is not running.'
    exit 0
}

& $pgCtl -D $dataDir -m fast -w stop
if ($LASTEXITCODE -ne 0) {
    throw 'PostgreSQL failed to stop.'
}
Write-Host 'PostgreSQL stopped.'
