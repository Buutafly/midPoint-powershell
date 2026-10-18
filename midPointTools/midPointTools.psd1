@{
    RootModule           = 'midPointTools.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '7aeaa914-f9e4-48a0-b34a-a6529d56b67d'
    Author               = 'Buutafly'
    CompanyName          = 'Community'
    Copyright            = '(c) 2026 Buutafly. MIT License.'
    Description          = 'PowerShell cmdlets for the Evolveum midPoint REST API: users, activation, role assignments, account checks and cases for admin tasks and test scripts.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FormatsToProcess     = @('midPointTools.Format.ps1xml')
    FunctionsToExport    = @(
        'Connect-midPoint'
        'Disconnect-midPoint'
        'Get-midPointSession'
        'Get-midPointUser'
        'New-midPointUser'
        'Set-midPointUser'
        'Remove-midPointUser'
        'Enable-midPointUser'
        'Disable-midPointUser'
        'Unlock-midPointUser'
        'Get-midPointUserActivation'
        'Set-midPointUserActivation'
        'Get-midPointRole'
        'Get-midPointRoleAssignment'
        'Add-midPointRoleAssignment'
        'Set-midPointRoleAssignment'
        'Remove-midPointRoleAssignment'
        'Get-midPointShadow'
        'Test-midPointShadow'
        'Wait-midPointShadow'
        'Get-midPointCase'
        'Complete-midPointCase'
        'Remove-midPointCase'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags         = @('midPoint', 'Evolveum', 'IAM', 'IdentityManagement', 'IGA', 'REST', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri   = 'https://github.com/Buutafly/midPoint-powershell/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/Buutafly/midPoint-powershell'
            ReleaseNotes = 'See CHANGELOG.md in the project repository.'
        }
    }
}
