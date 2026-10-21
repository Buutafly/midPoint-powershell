function Invoke-midPointRecompute {
    <#
    .SYNOPSIS
    Recomputes a midPoint user (mappings, assignments and provisioning), by default with reconciliation.

    .DESCRIPTION
    Sends an empty modification with the reconcile option (PATCH users/<oid>?options=reconcile), as the
    recompute task does for one user: midPoint evaluates the object template, the assignments and the
    outbound mappings, reads the accounts on the resources, compares them with what they should be and
    fixes them.
    With -NoReconcile the empty modification is sent without the option: midPoint still evaluates the
    template, the assignments and the mappings and provisions what changed (e.g. an assignment whose
    validFrom has passed), but does not read the accounts to find differences made on the resource.
    midPoint answers when the operation is done. Provisioning errors stop the cmdlet with an error
    (HTTP 500, the status code is in $_.Exception.Data['StatusCode']); a partial error (HTTP 250) is a warning.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER NoReconcile
    Recompute without reconciliation: faster, and the resources are not read.

    .PARAMETER PassThru
    Returns the user after the recompute.

    .EXAMPLE
    Invoke-midPointRecompute jack

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Invoke-midPointRecompute -PassThru

    .EXAMPLE
    Invoke-midPointRecompute jack -NoReconcile

    Applies changes such as an assignment that has just become valid, without reading the resources.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.User')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [switch] $NoReconcile,

        [switch] $PassThru
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $mode = if ($NoReconcile) { 'without reconcile' } else { 'reconcile' }
        if (-not $PSCmdlet.ShouldProcess("$(Get-midPointIdentityLabel $Identity) ($oid)", "Recompute midPoint user ($mode)")) { return }

        $options = if ($NoReconcile) { @() } else { @('reconcile') }
        Invoke-midPointModify -Type users -Oid $oid -Options $options
        if ($PassThru) { Get-midPointUser -Oid $oid }
    }
}
