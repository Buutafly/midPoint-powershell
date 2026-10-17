function Enable-midPointUser {
    <#
    .SYNOPSIS
    Enables a midPoint user.

    .DESCRIPTION
    Sets activation/administrativeStatus to enabled, optionally together with validFrom / validTo.
    Writes a warning when the user is still not effectively enabled afterwards.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER ValidFrom
    The user is active from this point in time.

    .PARAMETER ValidTo
    The user is active until this point in time.

    .PARAMETER PassThru
    Returns the activation after the change.

    .EXAMPLE
    Enable-midPointUser jack

    .EXAMPLE
    Enable-midPointUser jack -ValidTo (Get-Date).AddMonths(3)
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
        $deltas = New-midPointActivationDelta -Prefix 'activation' -AdministrativeStatus Enabled @activationParams

        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $label = Get-midPointIdentityLabel $Identity
        if (-not $PSCmdlet.ShouldProcess("$label ($oid)", 'Enable midPoint user')) { return }

        Invoke-midPointModify -Type users -Oid $oid -ItemDelta $deltas
        $activation = Get-midPointUserActivation -Identity $oid
        Test-midPointEffectiveStatus -Activation $activation -Label "User '$label'"
        if ($PassThru) { $activation }
    }
}
