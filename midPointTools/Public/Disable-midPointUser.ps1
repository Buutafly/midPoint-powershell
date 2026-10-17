function Disable-midPointUser {
    <#
    .SYNOPSIS
    Disables a midPoint user.

    .DESCRIPTION
    Sets activation/administrativeStatus to disabled, optionally together with validFrom / validTo.
    What happens to the user's accounts depends on your midPoint configuration.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER ValidFrom
    Sets validFrom in the same change.

    .PARAMETER ValidTo
    Sets validTo in the same change.

    .PARAMETER PassThru
    Returns the activation after the change.

    .EXAMPLE
    Disable-midPointUser jack

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Disable-midPointUser
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.Activation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,

        [switch] $PassThru
    )

    process {
        $activationParams = Get-midPointActivationParameter -BoundParameters $PSBoundParameters
        $deltas = New-midPointActivationDelta -Prefix 'activation' -AdministrativeStatus Disabled @activationParams

        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $label = Get-midPointIdentityLabel $Identity
        if (-not $PSCmdlet.ShouldProcess("$label ($oid)", 'Disable midPoint user')) { return }

        Invoke-midPointModify -Type users -Oid $oid -ItemDelta $deltas
        if ($PassThru) { Get-midPointUserActivation -Identity $oid }
    }
}
