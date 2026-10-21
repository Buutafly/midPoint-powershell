function Invoke-midPointRecompute {
    <#
    .SYNOPSIS
    Recomputes a midPoint user (mappings, assignments and provisioning), with reconciliation.

    .DESCRIPTION
    Sends an empty modification with the reconcile option (PATCH users/<oid>?options=reconcile), as the
    recompute task does for one user: midPoint evaluates the object template, the assignments and the
    outbound mappings, compares the accounts on the resources with what they should be and fixes them
    (e.g. creates an account that was deleted on the resource or in midPoint).
    midPoint answers when the operation is done. Provisioning errors stop the cmdlet with an error
    (HTTP 500, the status code is in $_.Exception.Data['StatusCode']); a partial error (HTTP 250) is a warning.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER PassThru
    Returns the user after the recompute.

    .EXAMPLE
    Invoke-midPointRecompute jack

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Invoke-midPointRecompute -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.User')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [switch] $PassThru
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        if (-not $PSCmdlet.ShouldProcess("$(Get-midPointIdentityLabel $Identity) ($oid)", 'Recompute midPoint user (reconcile)')) { return }

        Invoke-midPointModify -Type users -Oid $oid -Options 'reconcile'
        if ($PassThru) { Get-midPointUser -Oid $oid }
    }
}
