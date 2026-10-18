BeforeDiscovery {
    $manifestPath = Join-Path $PSScriptRoot '..' 'midPointTools' 'midPointTools.psd1'
    $script:exportedCommands = (Import-PowerShellDataFile $manifestPath).FunctionsToExport
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Initialize-TestModule
    $script:manifest = Test-ModuleManifest -Path $script:ModuleManifest -ErrorAction Stop
    $script:moduleRoot = Split-Path $script:ModuleManifest -Parent
}

Describe 'Module manifest' {
    It 'requires PowerShell 7.2 or later (Core)' {
        $manifest.PowerShellVersion | Should -Be ([version]'7.2')
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'exports exactly the functions in Public/' {
        $public = (Get-ChildItem (Join-Path $moduleRoot 'Public') -Filter '*.ps1').BaseName | Sort-Object
        @($manifest.ExportedFunctions.Keys | Sort-Object) | Should -Be @($public)
        @((Get-Command -Module midPointTools).Name | Sort-Object) | Should -Be @($public)
    }

    It 'exports no cmdlets, variables or aliases' {
        $manifest.ExportedCmdlets.Count | Should -Be 0
        $manifest.ExportedVariables.Count | Should -Be 0
        $manifest.ExportedAliases.Count | Should -Be 0
    }

    It 'has a project and license URI for the PowerShell Gallery' {
        $manifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
        $manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
    }
}

Describe 'Help for <_>' -ForEach $exportedCommands {
    BeforeAll {
        $script:help = Get-Help -Name $_ -Full
        $script:command = Get-Command -Name $_
    }

    It 'has a synopsis' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match '^\s*\S+-midPoint\S*\s*$'  # not the auto-generated syntax line
    }

    It 'has at least one example' {
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'describes every parameter' {
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        foreach ($name in $command.Parameters.Keys | Where-Object { $_ -notin $common }) {
            $p = $help.Parameters.Parameter | Where-Object Name -EQ $name
            ($p.Description.Text -join '') | Should -Not -BeNullOrEmpty -Because "parameter -$name of $($command.Name) needs a .PARAMETER entry"
        }
    }
}

Describe 'Public repository hygiene' {
    It 'contains no URLs other than example and documentation hosts' {
        $allowed = 'example\.com|example\.org|evolveum\.com|github\.com/Buutafly|powershellgallery\.com|w3\.org|schemas\.microsoft\.com|prism\.evolveum|creativecommons\.org|opensource\.org|keepachangelog\.com|semver\.org|learn\.microsoft\.com|pester\.dev|localhost'
        $root = Join-Path $PSScriptRoot '..'
        # Local, git-ignored files (*.local.ps1 with real settings, test results) are not published.
        $files = Get-ChildItem $root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.ps1xml', '*.md', '*.yml', '*.xml' |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|TestResults)[\\/]' -and $_.Name -notlike '*.local.*' }
        $bad = foreach ($f in $files) {
            Select-String -Path $f.FullName -Pattern 'https?://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+[^\s"''<>)]*' -AllMatches |
                ForEach-Object { $_.Matches.Value } |
                Where-Object { $_ -notmatch $allowed } |
                ForEach-Object { "$($f.Name): $_" }
        }
        $bad | Should -BeNullOrEmpty
    }
}
