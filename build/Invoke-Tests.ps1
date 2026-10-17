<#
.SYNOPSIS
Runs PSScriptAnalyzer and the Pester unit tests, as CI does.

.EXAMPLE
./build/Invoke-Tests.ps1
#>
[CmdletBinding()]
param(
    # Also run the integration tests (needs the MIDPOINT_* environment variables).
    [switch] $Integration
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

foreach ($module in @(@{ Name = 'Pester'; MinimumVersion = '5.5.0' }, @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.21.0' })) {
    if (-not (Get-Module -ListAvailable -Name $module.Name | Where-Object Version -GE $module.MinimumVersion)) {
        Install-Module @module -Scope CurrentUser -Force -SkipPublisherCheck
    }
}

Write-Host 'PSScriptAnalyzer...'
$findings = Invoke-ScriptAnalyzer -Path (Join-Path $root 'midPointTools') -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
if ($findings) {
    $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    throw "PSScriptAnalyzer found $(@($findings).Count) issue(s)."
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
