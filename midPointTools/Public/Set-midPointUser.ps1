function Set-midPointUser {
    <#
    .SYNOPSIS
    Changes properties of a midPoint user.

    .DESCRIPTION
    Sends one PATCH with all changes. The named parameters replace the value; an empty string clears it.
    -Replace, -Add and -Remove take path = value pairs for any other item, like Set-ADUser.
    Use Set-midPointUserActivation for status and validity, and the *-midPointRoleAssignment cmdlets for roles.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER GivenName
    The given name.

    .PARAMETER FamilyName
    The family name.

    .PARAMETER FullName
    The full name. midPoint's object template often computes it from given and family name.

    .PARAMETER EmailAddress
    The e-mail address.

    .PARAMETER Description
    A free-text description.

    .PARAMETER Replace
    Items to replace, e.g. @{ telephoneNumber = '+41 00 000 00 00'; 'extension/costCenter' = '4711' }.

    .PARAMETER Add
    Values to add to multi-valued items, e.g. @{ organizationalUnit = 'Sales' }.

    .PARAMETER Remove
    Values to remove from multi-valued items.

    .PARAMETER PassThru
    Returns the changed user.

    .EXAMPLE
    Set-midPointUser jack -EmailAddress jack.sparrow@example.com

    .EXAMPLE
    Get-midPointUser jack | Set-midPointUser -Replace @{ telephoneNumber = '+41 00 000 00 00' } -Description ''
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.User')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [AllowEmptyString()] [string] $GivenName,
        [AllowEmptyString()] [string] $FamilyName,
        [AllowEmptyString()] [string] $FullName,
        [AllowEmptyString()] [string] $EmailAddress,
        [AllowEmptyString()] [string] $Description,

        [hashtable] $Replace,
        [hashtable] $Add,
        [hashtable] $Remove,

        [switch] $PassThru
    )

    process {
        $deltas = [System.Collections.Generic.List[object]]::new()
        foreach ($pair in @(
                @('GivenName', 'givenName'), @('FamilyName', 'familyName'), @('FullName', 'fullName'),
                @('EmailAddress', 'emailAddress'), @('Description', 'description'))) {
            if ($PSBoundParameters.ContainsKey($pair[0])) {
                $deltas.Add((New-midPointItemDelta -ModificationType replace -Path $pair[1] -Value $PSBoundParameters[$pair[0]]))
            }
        }
        foreach ($set in @(@('replace', $Replace), @('add', $Add), @('delete', $Remove))) {
            if (-not $set[1]) { continue }
            foreach ($key in $set[1].Keys) {
                $deltas.Add((New-midPointItemDelta -ModificationType $set[0] -Path $key -Value $set[1][$key]))
            }
        }
        if ($deltas.Count -eq 0) {
            throw [System.ArgumentException]::new('Nothing to change. Give at least one property, -Replace, -Add or -Remove.')
        }

        $oid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        if (-not $PSCmdlet.ShouldProcess("$(Get-midPointIdentityLabel $Identity) ($oid)", 'Modify midPoint user')) { return }

        Invoke-midPointModify -Type users -Oid $oid -ItemDelta $deltas.ToArray()
        if ($PassThru) { Get-midPointUser -Oid $oid }
    }
}
