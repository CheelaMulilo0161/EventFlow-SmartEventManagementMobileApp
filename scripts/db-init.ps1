$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $root '.pgdata'
$pgBin = if ($env:PG_BIN) { $env:PG_BIN } else { 'C:\Program Files\PostgreSQL\18\bin' }

$initdb = Join-Path $pgBin 'initdb.exe'
$createdb = Join-Path $pgBin 'createdb.exe'

if (-not (Test-Path -LiteralPath $initdb)) {
    throw "initdb.exe not found at '$initdb'. Set PG_BIN to your PostgreSQL bin folder."
}
if (Test-Path -LiteralPath $dataDir) {
    Write-Host "Cluster already exists at '$dataDir'. Nothing to do."
    exit 0
}

Write-Host 'Creating local development database cluster...'
& $initdb -D $dataDir -U postgres -A trust --encoding=UTF8 --no-locale
if ($LASTEXITCODE -ne 0) {
    throw 'initdb failed.'
}

& (Join-Path $PSScriptRoot 'db-start.ps1')

& $createdb -h localhost -p 5433 -U postgres eventflow
& $createdb -h localhost -p 5433 -U postgres eventflow_test
Write-Host 'Created databases eventflow and eventflow_test.'
Write-Host 'Next: copy api/.env.example to api/.env, then run npm run setup in api.'
