function Get-midPointUserActivation {
    <#
    .SYNOPSIS
    Shows the activation of a midPoint user: status, validity, disable reason and lockout.

    .DESCRIPTION
    AdministrativeStatus is what an admin set explicitly. EffectiveStatus and ValidityStatus are
    computed by midPoint. DisableReason (explicit, mapped, deprovision, ...) and the timestamps are
    set by midPoint and are read only.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .EXAMPLE
    Get-midPointUserActivation jack

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Get-midPointUserActivation
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.Activation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $user = Get-midPointObjectByOid -Type users -Oid $oid
        ConvertTo-midPointActivationObject -InputObject $user
    }
}
