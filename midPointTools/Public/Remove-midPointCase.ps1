function Remove-midPointCase {
    <#
    .SYNOPSIS
    Deletes a midPoint case.

    .DESCRIPTION
    Deletes the case with DELETE /cases/<oid>. Deleting an open case does not complete the requested
    change; complete it first with Complete-midPointCase if midPoint should treat it as done.
    Asks for confirmation; use -Confirm:$false in scripts.

    .PARAMETER Case
    The case: OID, or an object from Get-midPointCase.

    .EXAMPLE
    Get-midPointCase -Resource 'Manual Resource' -State Closed | Remove-midPointCase -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Case
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Case -Type cases
        if (-not $PSCmdlet.ShouldProcess("$(Get-midPointIdentityLabel $Case) ($oid)", 'Delete midPoint case')) { return }

        $null = Invoke-midPointRestMethod -Method DELETE -Path ('cases/{0}' -f [uri]::EscapeDataString($oid))
    }
}
