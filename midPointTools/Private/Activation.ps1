function Test-midPointEffectiveStatus {
    # After enabling: warn when the user (or assignment) is still not effectively enabled,
    # e.g. because validTo is in the past. midPoint computes effectiveStatus during the change.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Activation,
        [Parameter(Mandatory)] [string] $Label
    )

    $effective = Get-midPointProperty $Activation 'EffectiveStatus'
    if ($effective -and $effective -ne 'enabled') {
        $validity = Get-midPointProperty $Activation 'ValidityStatus'
        $detail = if ($validity) { " (validity: $validity, validFrom: $($Activation.ValidFrom), validTo: $($Activation.ValidTo))" } else { '' }
        Write-Warning "$Label is enabled, but its effective status is '$effective'$detail."
    }
}

function Get-midPointActivationParameter {
    # Copies the activation parameters a cmdlet was called with, for New-midPointActivationDelta.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $BoundParameters)

    $result = @{}
    foreach ($name in 'AdministrativeStatus', 'ValidFrom', 'ValidTo', 'ClearValidFrom', 'ClearValidTo') {
        if ($BoundParameters.Keys -contains $name) { $result[$name] = $BoundParameters[$name] }
    }
    $result
}
