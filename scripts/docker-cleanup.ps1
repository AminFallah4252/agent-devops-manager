<#
.SYNOPSIS
    Safely prunes dangling Docker images and build caches on remote host without data loss.
.DESCRIPTION
    Runs 'docker image prune -f' and 'docker builder prune -f' remotely via SSH.
    Measures and reports disk space reclaimed before and after execution.
    Never removes running containers or persistent named volumes.
#>

[CmdletBinding()]
param (
    [string]$ProfileName = "",
    [string]$ConfigPath = ""
)

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

$sshTarget = if ($profile.ssh_alias) { $profile.ssh_alias } else { "$($profile.user)@$($profile.host)" }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DevOps Manager: Safe Docker Hygiene and Cleanup        " -ForegroundColor Cyan
Write-Host ("   Target: {0} ({1})" -f $profile.name, $sshTarget) -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Cleanup script executed remotely
$remoteCleanupScript = "echo ===PRE_DISK===; df -h / | tail -n 1; echo ===PRUNING===; docker image prune -f; docker builder prune -f; echo ===POST_DISK===; df -h / | tail -n 1"

try {
    Write-Host "`n[*] Running safe image and build cache pruning..." -ForegroundColor Yellow
    $output = & ssh $sshTarget $remoteCleanupScript 2>&1
    $rawText = $output -join "`n"

    if ($rawText -match "===PRE_DISK===\s*([^\r\n]+)") {
        Write-Host "`n[INFO] Disk state before cleanup:" -ForegroundColor DarkGray
        Write-Host ("       " + $matches[1].Trim()) -ForegroundColor DarkGray
    }

    Write-Host "`n[OK] Dangling images and builder cache successfully purged." -ForegroundColor Green

    if ($rawText -match "===POST_DISK===\s*([^\r\n]+)") {
        Write-Host "`n[OK] Disk state after cleanup:" -ForegroundColor Green
        Write-Host ("     " + $matches[1].Trim()) -ForegroundColor White
    }

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "   Hygiene Protocol Complete. Persistent Volumes Intact.  " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

} catch {
    Write-Host ("[-] Cleanup execution failed: {0}" -f $_) -ForegroundColor Red
    exit 1
}
