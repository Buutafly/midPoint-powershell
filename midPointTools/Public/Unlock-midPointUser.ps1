function Unlock-midPointUser {
    <#
    .SYNOPSIS
    Unlocks a midPoint user that is locked out after failed logins.

    .DESCRIPTION
    Sets activation/lockoutStatus to normal.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER PassThru
    Returns the activation after the change.

    .EXAMPLE
    Unlock-midPointUser jack
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.Activation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [switch] $PassThru
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        if (-not $PSCmdlet.ShouldProcess("$(Get-midPointIdentityLabel $Identity) ($oid)", 'Unlock midPoint user')) { return }

        Invoke-midPointModify -Type users -Oid $oid -ItemDelta @(
            New-midPointItemDelta -ModificationType replace -Path 'activation/lockoutStatus' -Value 'normal'
        )
        if ($PassThru) { Get-midPointUserActivation -Identity $oid }
    }
}
