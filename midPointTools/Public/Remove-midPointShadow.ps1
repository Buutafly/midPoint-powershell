function Remove-midPointShadow {
    <#
    .SYNOPSIS
    Deletes an account on its resource (not only midPoint's shadow).

    .DESCRIPTION
    Deletes the shadow with DELETE /shadows/<oid>, like "delete projection" in the midPoint GUI: midPoint
    deletes the account on the resource (the connector's delete operation runs) and unlinks it from its owner.
    On a manual resource midPoint opens a case instead; the account is gone when the case is completed.

    Takes shadow objects from Get-midPointShadow or shadow OIDs. Other objects (e.g. a user piped by
    mistake) and names are refused before anything is sent, because a shadow name is only unique per resource.
    Before the delete the cmdlet reads the shadow without contacting the resource (noFetch) to check that the
    OID is a shadow and to show its name and resource in the confirmation.

    A shadow that no longer exists (HTTP 404) or is dead (the account was already deleted; midPoint keeps such
    shadows for a while) gives a warning, not an error, and nothing is sent: deleting a dead shadow again would
    open another case on a manual resource (run 18). midPoint refuses to delete an
    account that is still assigned when the resource enforces assignments (HTTP 409, "... violates an
    assignment policy"); that and every other error stops the cmdlet. Remove the assignment instead.
    Asks for confirmation; use -Confirm:$false in scripts.

    .PARAMETER Shadow
    The shadow: an object from Get-midPointShadow or a shadow OID.

    .EXAMPLE
    Get-midPointShadow jack -Resource 'Some Resource' -NoFetch | Remove-midPointShadow -Confirm:$false

    .EXAMPLE
    Remove-midPointShadow 33333333-3333-3333-3333-333333333333
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Oid')]
        [object] $Shadow
    )

    process {
        $oid = $null
        if ($Shadow -is [string]) {
            if ($Shadow -match $script:midPointOidPattern) { $oid = $Shadow }
        }
        elseif ($Shadow.PSObject.TypeNames -contains 'midPointTools.Shadow') {
            $oid = [string]$Shadow.Oid
        }
        if (-not $oid) {
            $what = if ($Shadow -is [string]) { "'$Shadow' is not an OID" } else { "a $(@($Shadow.PSObject.TypeNames)[0]) object is not a shadow" }
            $record = [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new("Remove-midPointShadow takes shadows from Get-midPointShadow or shadow OIDs; $what."),
                'midPointNotAShadow', [System.Management.Automation.ErrorCategory]::InvalidArgument, $Shadow)
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $path = 'shadows/{0}' -f [uri]::EscapeDataString($oid)
        try {
            $raw = Get-midPointObjectByOid -Type shadows -Oid $oid -Options 'noFetch', 'resolveNames'
        }
        catch {
            if ($_.Exception.Data['StatusCode'] -eq 404) {
                Write-Warning "Shadow $oid no longer exists (already deleted)."
                return
            }
            throw
        }
        $resourceRef = Get-midPointProperty $raw 'resourceRef'
        if (-not $resourceRef) {
            throw [System.ArgumentException]::new("Object $oid is not a shadow (no resourceRef).")
        }
        if (Get-midPointProperty $raw 'dead') {
            Write-Warning "Shadow $oid is dead: the account was already deleted."
            return
        }
        $name = ConvertFrom-midPointPolyString (Get-midPointProperty $raw 'name')
        $resource = ConvertFrom-midPointPolyString (Get-midPointProperty $resourceRef 'targetName')
        if (-not $resource) { $resource = [string](Get-midPointProperty $resourceRef 'oid') }
        if (-not $PSCmdlet.ShouldProcess("$name on $resource ($oid)", 'Delete the account on the resource')) { return }

        try {
            $null = Invoke-midPointRestMethod -Method DELETE -Path $path
        }
        catch {
            if ($_.Exception.Data['StatusCode'] -eq 404) {
                Write-Warning "Shadow $oid no longer exists (already deleted)."
                return
            }
            throw
        }
    }
}
