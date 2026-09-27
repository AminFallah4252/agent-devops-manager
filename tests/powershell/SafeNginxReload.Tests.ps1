<#
.SYNOPSIS
    Pester v5 unit and mock tests for safe-nginx-reload.ps1.
#>

Import-Module Pester -RequiredVersion 5.5.0

Describe "SafeNginxReload Script Tests" {
    BeforeAll {
        $rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $rootDir "scripts\safe-nginx-reload.ps1"
        $fixtureConfig = Join-Path $rootDir "tests\fixtures\test-config.json"

        # Predefine mockable function for external ssh
        function ssh {
            param([Parameter(ValueFromRemainingArguments=$true)]$args)
            $global:LASTEXITCODE = 0
            return "mock-ssh-output"
        }
    }

    Context "Configuration Validation" {
        It "Fails gracefully when configuration file does not exist" {
            $err = & $scriptPath -ConfigPath "invalid-non-existent-path.json" 2>&1
            ($err | Out-String) | Should -Match "Configuration file not found"
        }

        It "Fails gracefully when requested profile does not exist" {
            $err = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "non-existent-profile" 2>&1
            ($err | Out-String) | Should -Match "Profile 'non-existent-profile' not found"
        }
    }

    Context "Dry-Run and Contract Modes" {
        It "Simulates syntax check and reload in DryRun mode" {
            Mock ssh { throw "Should not be called in DryRun" }
            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DryRun 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Dry-run mode active"
            $outputStr | Should -Match "Nginx successfully reloaded"
            Assert-MockCalled ssh -Times 0
        }

        It "Outputs valid JSON when Json flag is specified with DryRun" {
            $jsonStr = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -DryRun -Json
            $parsed = $jsonStr | ConvertFrom-Json
            $parsed.action | Should -Be "nginx-reload"
            $parsed.dry_run | Should -Be $true
            $parsed.status | Should -Be "syntax_ok"
        }
    }

    Context "Syntax Validation and Reload Execution" {
        It "Executes syntax check and stops when TestOnly is specified" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return "nginx: the configuration file /etc/nginx/nginx.conf syntax is ok`nnginx: configuration file /etc/nginx/nginx.conf test is successful"
            } -Verifiable

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" -TestOnly 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Nginx configuration syntax is valid"
            $outputStr | Should -Match "Test-only mode requested"
            Assert-VerifiableMock
        }

        It "Performs graceful reload when syntax check passes without TestOnly" {
            Mock ssh {
                $global:LASTEXITCODE = 0
                return "nginx: syntax is ok`nreloaded successfully"
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Nginx successfully reloaded with zero downtime"
            Assert-MockCalled ssh -Times 2
        }

        It "Aborts reload when syntax validation fails" {
            Mock ssh {
                $global:LASTEXITCODE = 1
                return "nginx: [emerg] unknown directive 'invalid_token' in /etc/nginx/conf.d/test.conf:5`nnginx: configuration file /etc/nginx/nginx.conf test failed"
            }

            $output = & $scriptPath -ConfigPath $fixtureConfig -ProfileName "mock-profile" 6>&1
            $outputStr = $output | Out-String
            $outputStr | Should -Match "Reload ABORTED to protect active web traffic"
            $LASTEXITCODE | Should -Be 1
        }
    }
}
