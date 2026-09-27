<#
.SYNOPSIS
    Pester v5 unit and mock tests for docker-cleanup.ps1.
#>

Import-Module Pester -RequiredVersion 5.5.0

Describe "DockerCleanup Script Tests" {
    BeforeAll {
        $rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $rootDir "scripts\docker-cleanup.ps1"
        $fixtureConfig = Join-Path $rootDir "tests\fixtures\test-config.json"

        function ssh {
            param([Parameter(ValueFromRemainingArguments=$true)]$args)
            $global:LASTEXITCODE = 0
            return "mock-ssh-output"
        }
    }

    Context "Configuration Validation" {
        It "Fails gracefully when configuration file does not exist" {
            $err = & $scriptPath -ConfigPath "invalid-path.json" 2>&1
            ($err | Out-String) | Should -Match "Configuration file not found"
        }

        It "Fails gracefully when requested profile does not exist" {
            $err = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "missing-profile" 2>&1
            ($err | Out-String) | Should -Match "Profile 'missing-profile' not found"
        }
    }

    Context "Dry-Run and Contract Modes" {
        It "Outputs execution plan and skips remote execution in DryRun mode" {
            Mock ssh { throw "Should not be called in DryRun" }
            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DryRun 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Dry-run mode active"
            $outputStr | Should -Match "Hygiene Protocol Complete. Persistent Volumes Intact."
            Assert-MockCalled ssh -Times 0
        }

        It "Outputs valid JSON when Json flag is specified with DryRun" {
            $jsonStr = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DryRun -Json
            $parsed = $jsonStr | ConvertFrom-Json
            $parsed.action | Should -Be "docker-cleanup"
            $parsed.dry_run | Should -Be $true
            $parsed.volumes_preserved | Should -Be $true
        }
    }

    Context "Execution and Disk Parsing" {
        It "Parses pre and post disk states correctly and succeeds" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return @"
===PRE_DISK===
/dev/sda1        40G   35G  5.0G  88% /
===PRUNING===
Deleted Images:
untagged: image:latest
===POST_DISK===
/dev/sda1        40G   30G   10G  75% /
"@
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Disk state before cleanup:"
            $outputStr | Should -Match "Disk state after cleanup:"
            $outputStr | Should -Match "Hygiene Protocol Complete. Persistent Volumes Intact."
            Assert-MockCalled ssh -Times 1
        }

        It "Handles remote execution failure gracefully" {
            Mock ssh {
                $global:LASTEXITCODE = 255
                throw "Connection refused"
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Cleanup execution failed"
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "Invariant Verification: NEG-001 (Zero Destructive Pruning)" {
        It "Upholds NEG-001: Verifies remote command never calls system prune -a --volumes" {
            $capturedCommands = @()
            Mock ssh {
                param([Parameter(ValueFromRemainingArguments=$true)]$args)
                $global:capturedArgs = $args
                $global:LASTEXITCODE = 0
                return "===PRE_DISK===`n40G 5G`n===POST_DISK===`n40G 10G"
            }

            $null = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $commandStr = $global:capturedArgs -join " "
            $commandStr | Should -Not -Match "system prune -a"
            $commandStr | Should -Not -Match "--volumes"
            $commandStr | Should -Match "image prune -f"
            $commandStr | Should -Match "builder prune -f"
        }
    }
}
