function Set-midPointUserActivation {
    <#
    .SYNOPSIS
    Sets the administrative status and the validity of a midPoint user.

    .DESCRIPTION
    Changes activation/administrativeStatus, activation/validFrom and activation/validTo in one PATCH.
    midPoint computes the effective status from these: an explicit administrative status wins,
    without one the validity dates decide.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER AdministrativeStatus
    Enabled, Disabled, Archived, or None. None removes the explicit status, so the validity dates decide again.

    .PARAMETER ValidFrom
    The user is active from this point in time.

    .PARAMETER ValidTo
    The user is active until this point in time.

    .PARAMETER ClearValidFrom
    Removes validFrom.

    .PARAMETER ClearValidTo
    Removes validTo.

    .PARAMETER PassThru
    Returns the activation after the change.

    .EXAMPLE
    Set-midPointUserActivation jack -ValidTo '2026-12-31 23:59'

    .EXAMPLE
    Set-midPointUserActivation jack -AdministrativeStatus None -ClearValidTo -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.Activation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [ValidateSet('Enabled', 'Disabled', 'Archived', 'None')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,
        [switch] $ClearValidFrom,
        [switch] $ClearValidTo,

        [switch] $PassThru
    )

    process {
        $activationParams = Get-midPointActivationParameter -BoundParameters $PSBoundParameters
        $deltas = New-midPointActivationDelta -Prefix 'activation' @activationParams
        if ($deltas.Count -eq 0) {
            throw [System.ArgumentException]::new('Nothing to change. Give -AdministrativeStatus, -ValidFrom, -ValidTo, -ClearValidFrom or -ClearValidTo.')
        }

        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $label = Get-midPointIdentityLabel $Identity
        if (-not $PSCmdlet.ShouldProcess("$label ($oid)", 'Change activation of midPoint user')) { return }

        Invoke-midPointModify -Type users -Oid $oid -ItemDelta $deltas
        if ($PassThru) { Get-midPointUserActivation -Identity $oid }
    }
}
