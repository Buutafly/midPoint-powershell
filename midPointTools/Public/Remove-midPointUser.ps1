function Remove-midPointUser {
    <#
    .SYNOPSIS
    Deletes a midPoint user.

    .DESCRIPTION
    Deletes the user with DELETE /users/<oid>. What happens to the user's accounts on the
    resources depends on your midPoint configuration (they may be deleted or disabled).
    Asks for confirmation; use -Confirm:$false in scripts.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .EXAMPLE
    Remove-midPointUser jack

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Remove-midPointUser -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        if (-not $PSCmdlet.ShouldProcess("$(Get-midPointIdentityLabel $Identity) ($oid)", 'Delete midPoint user')) { return }

        $null = Invoke-midPointRestMethod -Method DELETE -Path ('users/{0}' -f [uri]::EscapeDataString($oid))
    }
}
