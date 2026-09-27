<#
.SYNOPSIS
    DevOps Manager: Safe Non-Destructive Backup & Recovery Engine (PowerShell)
.DESCRIPTION
    Performs safe, non-destructive Docker volume and database backups on remote host.
    - Zero-downtime hot backup of named Docker volumes using ephemeral Alpine container mounted read-only (:ro).
    - Database Dump Orchestration: Zero-downtime streaming pg_dump (PostgreSQL) and mysqldump (MySQL).
    - Retention Policy: Daily (keep last 7) and Weekly (keep last 4) rotation.
    - Invariants: Upholds [INV-003], [NEG-001] (zero destructive volume pruning), [NEG-003] (zero hardcoded secrets).
#>

[CmdletBinding()]
param (
    [string]$ProfileName = "",
    [string]$ConfigPath = "",
    [string]$ServiceName = "all",
    [string]$VolumeName = "",
    [string]$BackupDir = "/var/backups",
    [int]$RetentionDays = 7,
    [int]$RetentionDaily = 7,
    [int]$RetentionWeekly = 4,
    [string]$DbType = "",
    [string]$DbContainer = "",
    [string]$DbUser = "",
    [string]$DbName = "",
    [string]$DbPass = "",
    [switch]$Weekly,
    [switch]$DryRun,
    [switch]$TestOnly,
    [switch]$Json
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
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Target resolution
if (-not $VolumeName -and -not $DbType) {
    $VolumeName = $ServiceName
}
$volumeBackup = ($VolumeName -or -not $DbType)

# Credential resolution from environment if not passed [NEG-003]
if (-not $DbUser) {
    $DbUser = if ($env:DB_USER) { $env:DB_USER } elseif ($env:POSTGRES_USER) { $env:POSTGRES_USER } elseif ($env:MYSQL_USER) { $env:MYSQL_USER } else { "" }
}
if (-not $DbName) {
    $DbName = if ($env:DB_NAME) { $env:DB_NAME } elseif ($env:POSTGRES_DB) { $env:POSTGRES_DB } elseif ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { "" }
}
if (-not $DbPass) {
    $DbPass = if ($env:DB_PASS) { $env:DB_PASS } elseif ($env:PGPASSWORD) { $env:PGPASSWORD } elseif ($env:MYSQL_PWD) { $env:MYSQL_PWD } elseif ($env:MYSQL_ROOT_PASSWORD) { $env:MYSQL_ROOT_PASSWORD } else { "" }
}

if ($DbType) {
    if (-not $DbContainer) {
        $DbContainer = $ServiceName
    }
    if ($DbType -eq "postgres") {
        if (-not $DbUser) { $DbUser = "postgres" }
        if (-not $DbName) { $DbName = if ($DbContainer) { $DbContainer } else { "postgres" } }
    } elseif ($DbType -eq "mysql") {
        if (-not $DbUser) { $DbUser = "root" }
        if (-not $DbName) { $DbName = if ($DbContainer) { $DbContainer } else { "" } }
    }
}

$dbDest = if ($DbName -and ($DbName -ne $DbContainer)) { "${DbContainer}_${DbName}" } else { $DbContainer }
if (-not $dbDest) { $dbDest = "db" }

$tarPattern = if (-not $VolumeName -or ($VolumeName -eq "all")) { "*.tar.gz" } else { "${VolumeName}_*.tar.gz" }
$sqlPattern = if (-not $DbType) { "*.sql.gz" } else { "${dbDest}_*.sql.gz" }

if ($Json) {
    $plan = [ordered]@{
        action = "backup"
        profile = $profile.name
        ssh_target = $sshTarget
        service = $ServiceName
        volume = $VolumeName
        volume_backup = [bool]$volumeBackup
        db_type = $DbType
        db_container = $DbContainer
        db_name = $DbName
        backup_dir = $BackupDir
        retention_days = $RetentionDays
        retention_daily = $RetentionDaily
        retention_weekly = $RetentionWeekly
        dry_run = [bool]($DryRun -or $TestOnly)
        timestamp = $timestamp
        status = "success"
    }
    $plan | ConvertTo-Json
    if ($DryRun -or $TestOnly) { return }
} else {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   DevOps Manager: Non-Destructive Backup & Recovery      " -ForegroundColor Cyan
    Write-Host ("   Target: {0} ({1})" -f $profile.name, $sshTarget) -ForegroundColor Cyan
    Write-Host ("   Service: {0} | Retention: {1} days (Daily: {2}, Weekly: {3})" -f $ServiceName, $RetentionDays, $RetentionDaily, $RetentionWeekly) -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
}

if ($DryRun -or $TestOnly) {
    Write-Host "`n[INFO] Dry-run / Test-only mode enabled. No remote changes executed." -ForegroundColor Yellow
    Write-Host ("       Target Directory: {0}" -f $BackupDir) -ForegroundColor DarkGray
    if ($volumeBackup) {
        Write-Host ("       Ephemeral Strategy: alpine tar czf /backup/{0}_{1}.tar.gz" -f $VolumeName, $timestamp) -ForegroundColor DarkGray
    }
    if ($DbType) {
        if ($DbType -eq "postgres") {
            Write-Host ("       Postgres Strategy: docker exec -i {0} pg_dump -U {1} {2} | gzip > {3}/{4}_{5}.sql.gz" -f $DbContainer, $DbUser, $DbName, $BackupDir, $dbDest, $timestamp) -ForegroundColor DarkGray
        } elseif ($DbType -eq "mysql") {
            Write-Host ("       MySQL Strategy: docker exec -i {0} mysqldump -u {1} -p[REDACTED] {2} | gzip > {3}/{4}_{5}.sql.gz" -f $DbContainer, $DbUser, $DbName, $BackupDir, $dbDest, $timestamp) -ForegroundColor DarkGray
        }
    }
    Write-Host ("       Retention Sweep: find {0} -name '*.tar.gz' -mtime +{1} -delete (daily: {2}d, weekly: {3}w)" -f $BackupDir, $RetentionDays, $RetentionDaily, $RetentionWeekly) -ForegroundColor DarkGray
    return
}

$cmdParts = @("mkdir -p '$BackupDir'")

if ($volumeBackup) {
    $cmdParts += "docker run --rm -v '${VolumeName}:/source:ro' -v '${BackupDir}:/backup' alpine tar czf '/backup/${VolumeName}_${timestamp}.tar.gz' -C /source ."
    if ($Weekly) {
        $cmdParts += "(cp -l '${BackupDir}/${VolumeName}_${timestamp}.tar.gz' '${BackupDir}/${VolumeName}_${timestamp}_weekly.tar.gz' 2>/dev/null || true)"
    }
}

if ($DbType) {
    if ($DbType -eq "postgres") {
        if ($DbPass) {
            $cmdParts += "PGPASSWORD='$DbPass' docker exec -i $DbContainer pg_dump -U $DbUser $DbName | gzip > '${BackupDir}/${dbDest}_${timestamp}.sql.gz'"
        } else {
            $cmdParts += "docker exec -i $DbContainer pg_dump -U $DbUser $DbName | gzip > '${BackupDir}/${dbDest}_${timestamp}.sql.gz'"
        }
    } elseif ($DbType -eq "mysql") {
        if ($DbPass) {
            $cmdParts += "docker exec -i $DbContainer mysqldump -u $DbUser -p'$DbPass' $DbName | gzip > '${BackupDir}/${dbDest}_${timestamp}.sql.gz'"
        } else {
            $cmdParts += "docker exec -i $DbContainer mysqldump -u $DbUser $DbName | gzip > '${BackupDir}/${dbDest}_${timestamp}.sql.gz'"
        }
    }
    if ($Weekly) {
        $cmdParts += "(cp -l '${BackupDir}/${dbDest}_${timestamp}.sql.gz' '${BackupDir}/${dbDest}_${timestamp}_weekly.sql.gz' 2>/dev/null || true)"
    }
}

# Retention rotation sweep: safely prunes older archives without deleting active volumes [NEG-001]
if ($volumeBackup) {
    $maxRetentionDays = $RetentionWeekly * 7
    $cmdParts += "find '$BackupDir' -maxdepth 1 -name '$tarPattern' -type f -mtime +$maxRetentionDays -delete"
    $cmdParts += "for f in `$(find '$BackupDir' -maxdepth 1 -name '$tarPattern' -type f -mtime +$RetentionDaily 2>/dev/null); do fdate=`$(basename `"`$f`" | grep -oE '[0-9]{8}_[0-9]{6}' | cut -d_ -f1 || echo ''); if [ -n `"`$fdate`" ]; then dow=`$(date -d `"`$fdate`" +%u 2>/dev/null || echo '1'); if [ `"`$dow`" -ne 7 ] && [[ `"`$f`" != *'_weekly_'* ]]; then rm -f `"`$f`"; fi; fi; done"
}

if ($DbType) {
    $maxRetentionDays = $RetentionWeekly * 7
    $cmdParts += "find '$BackupDir' -maxdepth 1 -name '$sqlPattern' -type f -mtime +$maxRetentionDays -delete"
    $cmdParts += "for f in `$(find '$BackupDir' -maxdepth 1 -name '$sqlPattern' -type f -mtime +$RetentionDaily 2>/dev/null); do fdate=`$(basename `"`$f`" | grep -oE '[0-9]{8}_[0-9]{6}' | cut -d_ -f1 || echo ''); if [ -n `"`$fdate`" ]; then dow=`$(date -d `"`$fdate`" +%u 2>/dev/null || echo '1'); if [ `"`$dow`" -ne 7 ] && [[ `"`$f`" != *'_weekly_'* ]]; then rm -f `"`$f`"; fi; fi; done"
}

$remoteBackupScript = $cmdParts -join " && "

try {
    Write-Host "`n[*] Executing ephemeral Alpine backup stream..." -ForegroundColor Yellow
    $output = & ssh $sshTarget $remoteBackupScript 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "`n[OK] Backup completed successfully without volume interference." -ForegroundColor Green
        if ($volumeBackup) {
            Write-Host ("     Archive saved to: {0}/{1}_{2}.tar.gz" -f $BackupDir, $VolumeName, $timestamp) -ForegroundColor White
        }
        if ($DbType) {
            Write-Host ("     Database dump saved to: {0}/{1}_{2}.sql.gz" -f $BackupDir, $dbDest, $timestamp) -ForegroundColor White
        }
    } else {
        Write-Host ("[FAIL] Backup operation failed: " + ($output -join "`n")) -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host ("[-] Backup execution error: {0}" -f $_) -ForegroundColor Red
    exit 1
}
