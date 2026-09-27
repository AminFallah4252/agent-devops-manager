<#
.SYNOPSIS
    Pester v5 unit and mock tests for server-ssh-tunnel.ps1.
#>

Import-Module Pester -RequiredVersion 5.5.0

Describe "ServerSshTunnel Script Tests" {
    BeforeAll {
        $rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $rootDir "scripts\server-ssh-tunnel.ps1"
        $fixtureConfig = Join-Path $rootDir "tests\fixtures\test-config.json"

        # Mockable function declarations
        function Start-Sleep { param([int]$Seconds) }
    }

    Context "Configuration Validation" {
        It "Throws terminating error when configuration file does not exist" {
            { & $scriptPath -ConfigPath "invalid-tunnel-config.json" } | Should -Throw "*Configuration file not found*"
        }

        It "Throws terminating error when profile is not found" {
            { & $scriptPath -ConfigPath $fixtureConfig -ProfileName "missing-tunnel-profile" } | Should -Throw "*Profile 'missing-tunnel-profile' not found*"
        }
    }

    Context "Port Detection and Tunnel Management" {
        It "Detects active port 8008 and skips process launch" {
            Mock Get-NetTCPConnection {
                return [PSCustomObject]@{ LocalPort = 8008; State = "Listen" }
            }
            Mock Start-Process { }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Tunnel appears to be ACTIVE"
            Assert-MockCalled Start-Process -Times 0
        }

        It "Reports inactive tunnel without starting process when CheckOnly is specified" {
            Mock Get-NetTCPConnection { return $null }
            Mock Start-Process { }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -CheckOnly 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Tunnel is NOT active. Port 8008 is not bound."
            Assert-MockCalled Start-Process -Times 0
        }

        It "Launches background SSH process when tunnel is inactive" {
            $checkCount = 0
            Mock Get-NetTCPConnection {
                $script:checkCount++
                if ($script:checkCount -eq 1) {
                    return $null
                } else {
                    return [PSCustomObject]@{ LocalPort = 8008; State = "Listen" }
                }
            }
            Mock Start-Process { }
            Mock Start-Sleep { }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Starting background SSH tunnel via alias 'mock-tunnel'"
            Assert-MockCalled Start-Process -Times 1 -ParameterFilter {
                $ArgumentList -contains "-N" -and $ArgumentList -contains "mock-tunnel"
            }
        }
    }
}
