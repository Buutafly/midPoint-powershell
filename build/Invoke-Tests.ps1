<#
.SYNOPSIS
Runs PSScriptAnalyzer and the Pester unit tests, as CI does.

.DESCRIPTION
Needs Pester 5.5+ and PSScriptAnalyzer 1.21+. Missing modules are installed for the current user
from the PowerShell Gallery (with PSResourceGet when available, which needs no NuGet provider).

.EXAMPLE
./build/Invoke-Tests.ps1

.EXAMPLE
./build/Invoke-Tests.ps1 -Integration -SkipAnalyzer
#>
[CmdletBinding()]
param(
    # Also run the integration tests (needs the MIDPOINT_* environment variables).
    [switch] $Integration,

    # Skip PSScriptAnalyzer (CI always runs it).
    [switch] $SkipAnalyzer
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Install-TestDependency {
    param([string] $Name, [version] $MinimumVersion)

    if (Get-Module -ListAvailable -Name $Name | Where-Object Version -GE $MinimumVersion) { return }

    Write-Host "Installing $Name $MinimumVersion or later for the current user..."
    try {
        if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
            Install-PSResource -Name $Name -Version "[$MinimumVersion,)" -Scope CurrentUser -TrustRepository -Reinstall
        }
        else {
            Install-Module -Name $Name -MinimumVersion $MinimumVersion -Scope CurrentUser -Force -SkipPublisherCheck
        }
    }
    catch {
        throw @"
Could not install $Name ($($_.Exception.Message)).
Install it manually, then run this script again:
  Install-PSResource $Name -Scope CurrentUser -TrustRepository     # PowerShell 7.4+
  Install-Module $Name -MinimumVersion $MinimumVersion -Scope CurrentUser -Force -SkipPublisherCheck
If the PowerShell Gallery is not registered: Register-PSResourceRepository -PSGallery  (or Register-PSRepository -Default).
Behind a proxy, check Get-PSResourceRepository / Get-PSRepository and your proxy settings.
"@
    }
}

Install-TestDependency -Name Pester -MinimumVersion '5.5.0'
# Windows ships Pester 3.4; load the new one explicitly.
Import-Module Pester -MinimumVersion '5.5.0' -Force

if (-not $SkipAnalyzer) {
    Install-TestDependency -Name PSScriptAnalyzer -MinimumVersion '1.21.0'
    Write-Host 'PSScriptAnalyzer...'
    $findings = Invoke-ScriptAnalyzer -Path (Join-Path $root 'midPointTools') -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
    if ($findings) {
        $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
        throw "PSScriptAnalyzer found $(@($findings).Count) issue(s)."
    }
}

Write-Host 'Pester...'
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'Tests'
$config.Run.Exit = $false
$config.Run.Throw = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $root 'TestResults' 'pester.xml'
if (-not $Integration) { $config.Filter.ExcludeTag = 'Integration' }
Invoke-Pester -Configuration $config
