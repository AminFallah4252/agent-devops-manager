<#
.SYNOPSIS
    Manages SSH port-forwarding tunnels for accessing private server administrative UIs.
.DESCRIPTION
    Launches an encrypted SSH background session forwarding internal ports:
      - 8008 -> Dockhand (Container Manager UI)
      - 3000 -> Grafana (Monitoring Dashboards)
      - 19090 -> Prometheus (Scraper / Metrics Engine)
#>

[CmdletBinding()]
param (
    [string]$ProfileName = "",
    [string]$ConfigPath = "",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

if (-not $ConfigPath) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $ConfigPath = Join-Path (Split-Path -Parent $scriptDir) "config.json"
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    return
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
if (-not $ProfileName) {
    $ProfileName = $config.active_profile
}

$profile = $config.profiles.$ProfileName
if (-not $profile) {
    Write-Error "Profile '$ProfileName' not found in $ConfigPath"
    return
}

$tunnelAlias = $profile.observability.tunnel_alias
if (-not $tunnelAlias) {
    $tunnelAlias = "hephaest-tunnel"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DevOps Manager: Admin UI SSH Port-Forwarding Tunnel    " -ForegroundColor Cyan
Write-Host ("   Alias: {0}" -f $tunnelAlias) -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Check if port 8008 is currently listening locally
$activeConnection = Get-NetTCPConnection -LocalPort 8008 -ErrorAction SilentlyContinue

if ($activeConnection) {
    Write-Host "[OK] Tunnel appears to be ACTIVE. Port 8008 is currently bound." -ForegroundColor Green
    Write-Host "     - Dockhand UI:   http://localhost:8008" -ForegroundColor Cyan
    Write-Host "     - Grafana:       http://localhost:3000" -ForegroundColor Cyan
    Write-Host "     - Prometheus:    http://localhost:19090" -ForegroundColor Cyan
    return
}

if ($CheckOnly) {
    Write-Host "[INFO] Tunnel is NOT active. Port 8008 is not bound." -ForegroundColor Yellow
    return
}

Write-Host "`n[*] Starting background SSH tunnel via alias '$tunnelAlias'..." -ForegroundColor Yellow
Write-Host "    Command: Start-Process ssh -ArgumentList '-N', '$tunnelAlias' -NoNewWindow" -ForegroundColor DarkGray

try {
    Start-Process ssh -ArgumentList "-N", "$tunnelAlias" -NoNewWindow
    Start-Sleep -Seconds 2

    $verify = Get-NetTCPConnection -LocalPort 8008 -ErrorAction SilentlyContinue
    if ($verify) {
        Write-Host "[OK] Tunnel successfully established!" -ForegroundColor Green
        Write-Host "     - Dockhand UI:   http://localhost:8008" -ForegroundColor Cyan
        Write-Host "     - Grafana:       http://localhost:3000" -ForegroundColor Cyan
        Write-Host "     - Prometheus:    http://localhost:19090" -ForegroundColor Cyan
    } else {
        Write-Host "[INFO] Tunnel process launched. Please verify in browser: http://localhost:8008" -ForegroundColor Yellow
    }
} catch {
    Write-Host ("[-] Failed to launch tunnel: {0}" -f $_) -ForegroundColor Red
    exit 1
}
