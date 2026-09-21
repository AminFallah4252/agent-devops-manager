<#
.SYNOPSIS
    Safely tests and reloads containerized Nginx reverse proxy with zero downtime.
.DESCRIPTION
    Executes 'nginx -t' syntax validation inside the nginx-proxy container before
    issuing 'nginx -s reload'. Aborts immediately without modifying runtime state if
    configuration syntax errors are detected.
#>

[CmdletBinding()]
param (
    [string]$ProfileName = "",
    [string]$ConfigPath = "",
    [switch]$TestOnly
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
$containerName = $profile.web_gateway.container_name

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   DevOps Manager: Safe Nginx Reverse Proxy Reload        " -ForegroundColor Cyan
Write-Host ("   Target: {0} | Container: {1}" -f $profile.name, $containerName) -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Step 1: Pre-flight syntax validation
Write-Host "`n[*] Executing pre-flight Nginx configuration syntax check..." -ForegroundColor Yellow

$testCmd = "docker exec $containerName nginx -t"

try {
    # Nginx outputs test results to stderr by design. Temporarily allow stderr without throwing.
    $origEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $testOutput = & ssh $sshTarget $testCmd 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $origEAP

    $testResult = $testOutput -join "`n"

    if ($exitCode -eq 0 -and $testResult -match "syntax is ok") {
        Write-Host "[OK] Nginx configuration syntax is valid!" -ForegroundColor Green
        foreach ($line in $testOutput) {
            $s = $line.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($s)) {
                Write-Host ("     " + $s) -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "[FAIL] Nginx configuration syntax check FAILED:" -ForegroundColor Red
        Write-Host $testResult -ForegroundColor Red
        Write-Host "`n[ALERT] Reload ABORTED to protect active web traffic." -ForegroundColor Red
        exit 1
    }

    if ($TestOnly) {
        Write-Host "`n[INFO] Test-only mode requested. Skipping reload." -ForegroundColor Cyan
        return
    }

    # Step 2: Graceful zero-downtime reload
    Write-Host "`n[*] Performing graceful zero-downtime Nginx reload..." -ForegroundColor Yellow
    $reloadCmd = "docker exec $containerName nginx -s reload"
    
    $ErrorActionPreference = "Continue"
    $reloadOutput = & ssh $sshTarget $reloadCmd 2>&1
    $reloadExit = $LASTEXITCODE
    $ErrorActionPreference = $origEAP

    if ($reloadExit -eq 0) {
        Write-Host "[OK] Nginx successfully reloaded with zero downtime!" -ForegroundColor Green
    } else {
        Write-Host ("[FAIL] Nginx reload failed: " + ($reloadOutput -join "`n")) -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host ("[-] Execution error: {0}" -f $_) -ForegroundColor Red
    exit 1
}
