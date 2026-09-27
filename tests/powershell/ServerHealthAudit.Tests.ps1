<#
.SYNOPSIS
    Pester v5 unit and mock tests for server-health-audit.ps1.
#>

Import-Module Pester -RequiredVersion 5.5.0

Describe "ServerHealthAudit Script Tests" {
    BeforeAll {
        $rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $rootDir "scripts\server-health-audit.ps1"
        $fixtureConfig = Join-Path $rootDir "tests\fixtures\test-config.json"

        function ssh {
            param([Parameter(ValueFromRemainingArguments=$true)]$args)
            $global:LASTEXITCODE = 0
            return "mock-ssh-output"
        }
    }

    Context "Configuration Validation" {
        It "Fails gracefully when configuration file does not exist" {
            { & $scriptPath -ConfigPath "invalid-config.json" } | Should -Throw "*Configuration file not found*"
        }

        It "Fails gracefully when requested profile does not exist" {
            { & $scriptPath -ConfigPath $fixtureConfig -ProfileName "unknown-profile" } | Should -Throw "*Profile 'unknown-profile' not found*"
        }
    }

    Context "Dry-Run and Contract Modes" {
        It "Simulates health check and skips remote SSH in DryRun mode" {
            Mock ssh { throw "Should not be called in DryRun" }
            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DryRun 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "System Uptime and Load \(simulation\):"
            $outputStr | Should -Match "Audit Complete: Ready for Operations"
            Assert-MockCalled ssh -Times 0
        }

        It "Outputs valid JSON when Json flag is specified with DryRun" {
            $jsonStr = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DryRun -Json
            $parsed = $jsonStr | ConvertFrom-Json
            $parsed.action | Should -Be "health-audit"
            $parsed.dry_run | Should -Be $true
            $parsed.status | Should -Be "healthy"
        }
    }

    Context "Healthy Server Audit" {
        It "Reports healthy status when all metrics are within safe thresholds" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return @"
===UPTIME===
 22:00:00 up 100 days,  2 users,  load average: 0.15, 0.20, 0.18
===MEMORY===
               total        used        free      shared  buff/cache   available
Mem:      8589934592  2147483648  4294967296   104857600  2147483648  6442450944
===DISK===
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/root       41943040  10485760  31457280  25% /
===DOCKER===
nginx-proxy:::Up 24 hours:::0.0.0.0:80->80/tcp
grafana:::Up 24 hours:::127.0.0.1:3000->3000/tcp
"@
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "System Uptime and Load:"
            $outputStr | Should -Match "RAM headroom is healthy."
            $outputStr | Should -Match "Disk headroom is within safe operating parameters."
            $outputStr | Should -Match "nginx-proxy"
            $outputStr | Should -Match "Audit Complete: Ready for Operations"
        }
    }

    Context "Threshold Violations & Degradation Alerts" {
        It "Emits warning when RAM usage exceeds threshold" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return @"
===UPTIME===
 22:00:00 up 5 days, load average: 3.50, 2.10, 1.80
===MEMORY===
               total        used        free      shared  buff/cache   available
Mem:      8589934592  7730941132   429496729   104857600   429496729   858993460
===DISK===
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/root       41943040  10485760  31457280  25% /
===DOCKER===
app:::Up 2 hours:::8080/tcp
"@
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "WARNING: RAM usage exceeds threshold"
        }

        It "Emits critical alert when disk space falls below safe minimum" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return @"
===UPTIME===
 22:00:00 up 10 days, load average: 0.10, 0.10, 0.10
===MEMORY===
               total        used        free      shared  buff/cache   available
Mem:      8589934592  2147483648  4294967296   104857600  2147483648  6442450944
===DISK===
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/root       41943040  40894464   1048576  98% /
===DOCKER===
app:::Up 2 hours:::8080/tcp
"@
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "CRITICAL: Free disk space .* is below safe minimum"
        }

        It "Handles host without Docker gracefully" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return @"
===UPTIME===
 22:00:00 up 1 day, load average: 0.01, 0.02, 0.00
===MEMORY===
               total        used        free      shared  buff/cache   available
Mem:      8589934592  2147483648  4294967296   104857600  2147483648  6442450944
===DISK===
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/root       41943040  10485760  31457280  25% /
===DOCKER===
NO_DOCKER
"@
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Docker is not installed or not in PATH."
        }
    }
}
