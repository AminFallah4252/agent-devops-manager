<#
.SYNOPSIS
    Pester v5 unit and mock tests for backup-service.ps1.
    Invariants: [INV-003] Backup & Disaster Recovery | [NEG-001] Zero Destructive Pruning | [NEG-003] Zero Hardcoded Secrets
#>

Import-Module Pester -RequiredVersion 5.5.0

Describe "BackupService Script Tests" {
    BeforeAll {
        $rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $rootDir "scripts\backup-service.ps1"
        $fixtureConfig = Join-Path $rootDir "tests\fixtures\test-config.json"

        function ssh {
            param([Parameter(ValueFromRemainingArguments=$true)]$args)
            $global:LASTEXITCODE = 0
            return "mock-ssh-output"
        }
    }

    Context "Configuration Validation" {
        It "Fails gracefully when configuration file does not exist" {
            $err = & $scriptPath -ConfigPath "invalid-backup-config.json" 2>&1
            ($err | Out-String) | Should -Match "Configuration file not found"
        }

        It "Fails gracefully when requested profile does not exist" {
            $err = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "missing-backup-profile" 2>&1
            ($err | Out-String) | Should -Match "Profile 'missing-backup-profile' not found"
        }
    }

    Context "Dry-Run and Contract Modes" {
        It "Outputs execution plan and skips remote execution in DryRun mode" {
            Mock ssh { }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -ServiceName "nginx-proxy" -DryRun 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Dry-run / Test-only mode enabled"
            $outputStr | Should -Match "alpine tar czf /backup/nginx-proxy_"
            Assert-MockCalled ssh -Times 0
        }

        It "Outputs valid JSON when Json flag is specified with DryRun" {
            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -ServiceName "database" -DryRun -Json
            $jsonObj = $output | ConvertFrom-Json
            $jsonObj.action | Should -Be "backup"
            $jsonObj.service | Should -Be "database"
            $jsonObj.dry_run | Should -Be $true
        }
    }

    Context "Execution and Invariants" {
        It "Executes ephemeral Alpine backup and retention purge successfully" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return "backup-ok"
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -ServiceName "webapp" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Backup completed successfully without volume interference"
            Assert-MockCalled ssh -Times 1
        }

        It "Upholds NEG-001: Verifies backup execution never executes docker system prune" {
            $capturedArgs = @()
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedBackupCmd = $args -join " "
                $global:LASTEXITCODE = 0
                return "ok"
            }

            $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -ServiceName "webapp" 6>&1
            $global:capturedBackupCmd | Should -Not -Match "system prune -a"
            $global:capturedBackupCmd | Should -Not -Match "--volumes"
            $global:capturedBackupCmd | Should -Match "docker run --rm"
            $global:capturedBackupCmd | Should -Match "alpine tar czf"
        }
    }

    Context "Named Docker Volume Hot Backup [INV-003]" {
        It "Mounts volume read-only (:ro) and creates compressed tarball from /source root" {
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedVolCmd = $args -join " "
                $global:LASTEXITCODE = 0
                return "ok"
            }

            $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -VolumeName "pg_data" -BackupDir "/srv/backups" 6>&1
            $global:capturedVolCmd | Should -Match "-v 'pg_data:/source:ro'"
            $global:capturedVolCmd | Should -Match "-v '/srv/backups:/backup'"
            $global:capturedVolCmd | Should -Match "alpine tar czf '/backup/pg_data_"
            $global:capturedVolCmd | Should -Match "-C /source \."
        }
    }

    Context "Database Dump Streaming Orchestration [INV-003]" {
        It "Executes streaming pg_dump via docker exec for PostgreSQL" {
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedPgCmd = $args -join " "
                $global:LASTEXITCODE = 0
                return "ok"
            }

            $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DbType "postgres" -DbContainer "prod-postgres" -DbUser "pguser" -DbName "proddb" 6>&1
            $global:capturedPgCmd | Should -Match "docker exec -i prod-postgres pg_dump -U pguser proddb \| gzip >"
        }

        It "Executes streaming mysqldump via docker exec for MySQL" {
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedMyCmd = $args -join " "
                $global:LASTEXITCODE = 0
                return "ok"
            }

            $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DbType "mysql" -DbContainer "prod-mysql" -DbUser "root" -DbName "shopdb" -DbPass "secret_pass" 6>&1
            $global:capturedMyCmd | Should -Match "docker exec -i prod-mysql mysqldump -u root -p'secret_pass' shopdb \| gzip >"
        }
    }

    Context "Retention Policy and Secret Hygiene [INV-003, NEG-003]" {
        It "Applies daily and weekly retention purge limits" {
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedRetCmd = $args -join " "
                $global:LASTEXITCODE = 0
                return "ok"
            }

            $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -ServiceName "orders" -RetentionDaily 7 -RetentionWeekly 4 6>&1
            $global:capturedRetCmd | Should -Match "-mtime \+28 -delete"
            $global:capturedRetCmd | Should -Match "-mtime \+7"
            $global:capturedRetCmd | Should -Match "orders_\*\.tar\.gz"
        }

        It "Upholds NEG-003: Dynamically reads DB credentials from environment variables" {
            $env:POSTGRES_USER = "env_pguser"
            $env:POSTGRES_DB = "env_pgdb"
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedEnvCmd = $args -join " "
                $global:LASTEXITCODE = 0
                return "ok"
            }

            try {
                $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DbType "postgres" -DbContainer "env-container" 6>&1
                $global:capturedEnvCmd | Should -Match "docker exec -i env-container pg_dump -U env_pguser env_pgdb"
            } finally {
                Remove-Item Env:\POSTGRES_USER -ErrorAction SilentlyContinue
                Remove-Item Env:\POSTGRES_DB -ErrorAction SilentlyContinue
            }
        }
    }
}
