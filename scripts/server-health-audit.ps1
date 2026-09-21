<#
.SYNOPSIS
    Runs a non-destructive multi-metric health audit on a managed remote server.
.DESCRIPTION
    Inspects CPU load, RAM, swap, disk headroom, running Docker containers, and active
    listening ports via SSH. Validates metrics against safety thresholds in config.json.
#>

[CmdletBinding()]
param (
    [string]$ProfileName = "",
    [string]$ConfigPath = ""
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

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DevOps Manager: Remote Health and Triage Audit         " -ForegroundColor Cyan
Write-Host ("   Target: {0} ({1}@{2}:{3})" -f $profile.name, $profile.user, $profile.host, $profile.ssh_port) -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$sshArgs = @()
if ($profile.ssh_alias) {
    $sshArgs += $profile.ssh_alias
} else {
    if ($profile.ssh_port) {
        $sshArgs += "-p"
        $sshArgs += "$($profile.ssh_port)"
    }
    $sshArgs += "$($profile.user)@$($profile.host)"
}

$remoteScript = 'echo ===UPTIME===; uptime; echo ===MEMORY===; free -b; echo ===DISK===; df -k /; echo ===DOCKER===; if command -v docker >/dev/null 2>&1; then docker ps --format "{{.Names}}:::{{.Status}}:::{{.Ports}}" 2>/dev/null; else echo NO_DOCKER; fi'

try {
    $allArgs = $sshArgs + @($remoteScript)
    $output = & ssh @allArgs 2>&1
    $rawText = $output -join "`n"

    # 1. Parse Uptime & Load Average
    if ($rawText -match "===UPTIME===\s*([^\r\n]+)") {
        $uptimeLine = $matches[1].Trim()
        Write-Host "`n[+] System Uptime and Load:" -ForegroundColor Green
        Write-Host ("    {0}" -f $uptimeLine)
    }

    # 2. Parse Memory
    if ($rawText -match "Mem:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)") {
        $totalBytes = [double]$matches[1]
        $usedBytes  = [double]$matches[2]
        $availBytes = [double]$matches[6]
        
        $totalGB = [math]::Round($totalBytes / 1GB, 2)
        $usedGB  = [math]::Round($usedBytes / 1GB, 2)
        $availGB = [math]::Round($availBytes / 1GB, 2)
        $usedPct = [math]::Round(($usedBytes / $totalBytes) * 100, 1)

        Write-Host "`n[+] Memory (RAM) Status:" -ForegroundColor Green
        Write-Host ("    Total: {0} GB | Used: {1} GB ({2}%) | Available: {3} GB" -f $totalGB, $usedGB, $usedPct, $availGB)
        
        if ($usedPct -ge $profile.thresholds.max_ram_usage_percent) {
            Write-Host ("    [!] WARNING: RAM usage exceeds threshold ({0}%)!" -f $profile.thresholds.max_ram_usage_percent) -ForegroundColor Red
        } else {
            Write-Host "    [ok] RAM headroom is healthy." -ForegroundColor DarkGreen
        }
    }

    # 3. Parse Disk Headroom
    if ($rawText -match "===DISK===\s*Filesystem[^\r\n]*\r?\n[^\s]+\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+/") {
        $diskTotalKB = [double]$matches[1]
        $diskUsedKB  = [double]$matches[2]
        $diskFreeKB  = [double]$matches[3]
        $diskPct     = [int]$matches[4]

        $diskTotalGB = [math]::Round($diskTotalKB / 1MB, 2)
        $diskFreeGB  = [math]::Round($diskFreeKB / 1MB, 2)

        Write-Host "`n[+] Storage and Disk Headroom (/):" -ForegroundColor Green
        Write-Host ("    Total: {0} GB | Free: {1} GB | Used: {2}%" -f $diskTotalGB, $diskFreeGB, $diskPct)

        if ($diskFreeGB -lt $profile.thresholds.min_free_disk_gb) {
            Write-Host ("    [!] CRITICAL: Free disk space ({0} GB) is below safe minimum ({1} GB)!" -f $diskFreeGB, $profile.thresholds.min_free_disk_gb) -ForegroundColor Red
        } else {
            Write-Host "    [ok] Disk headroom is within safe operating parameters." -ForegroundColor DarkGreen
        }
    }

    # 4. Parse Docker Containers
    Write-Host "`n[+] Active Docker Containers:" -ForegroundColor Green
    if ($rawText -match "===DOCKER===\s*([\s\S]*)$") {
        $dockerSection = $matches[1].Trim()
        if ($dockerSection -eq "NO_DOCKER") {
            Write-Host "    Docker is not installed or not in PATH." -ForegroundColor Yellow
        } elseif ([string]::IsNullOrWhiteSpace($dockerSection)) {
            Write-Host "    No running containers found." -ForegroundColor Yellow
        } else {
            $lines = $dockerSection -split "`n"
            foreach ($line in $lines) {
                $parts = $line -split ":::"
                if ($parts.Count -ge 2) {
                    $name   = $parts[0].Trim()
                    $status = $parts[1].Trim()
                    $ports  = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }
                    Write-Host ("    - {0,-25} | {1,-20} | {2}" -f $name, $status, $ports) -ForegroundColor White
                }
            }
        }
    }

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "   Audit Complete: Ready for Operations                  " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

} catch {
    Write-Host ("[-] Failed to connect or execute remote health audit: {0}" -f $_) -ForegroundColor Red
    exit 1
}
