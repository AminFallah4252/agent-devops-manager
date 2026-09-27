<#
.SYNOPSIS
    Pester v5 unit and mock tests for backup-service.ps1.
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
}
