# Materialise the real IP schema from Bitwarden Secrets Manager into the
# git-ignored file schema/ip-schema.yaml. Windows PowerShell / pwsh variant.
# Linux/macOS/WSL variant: scripts/fetch-ip-schema.sh
#
# Requires: `bws` on PATH and $env:BWS_ACCESS_TOKEN set in this session
# (the iac-deploy machine account token). The secret IP_SCHEMA_B64 holds the
# base64-encoded schema. The content is never printed.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'schema/ip-schema.yaml'
$tmp  = "$out.tmp"

if (-not (Get-Command bws -ErrorAction SilentlyContinue)) { throw 'bws not found on PATH' }
if (-not $env:BWS_ACCESS_TOKEN) { throw 'BWS_ACCESS_TOKEN is not set' }

$env:BWS_OUT = $tmp
try {
    bws run -- '[IO.File]::WriteAllBytes($env:BWS_OUT,[Convert]::FromBase64String($env:IP_SCHEMA_B64))'
    if ($LASTEXITCODE -ne 0) { throw 'bws run failed (check token, project access and secret name IP_SCHEMA_B64)' }
    if (-not (Test-Path $tmp) -or -not (Select-String -Path $tmp -Pattern '^schema_version:' -Quiet)) {
        throw 'decoded file does not look like an IP schema (no schema_version)'
    }
    Move-Item -Force $tmp $out
    Write-Host 'ok: wrote schema/ip-schema.yaml (git-ignored)'
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp
    Remove-Item Env:BWS_OUT -ErrorAction SilentlyContinue
}
