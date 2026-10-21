function Move-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Moves a midPoint user from one org to another in one modification.

    .DESCRIPTION
    Deletes the user's assignments of the -From org (by their container id) and adds an assignment of the
    -To org in the same modification (one PATCH). midPoint therefore provisions once and the user is never
    without an org in between, as it would be with Remove-midPointOrgAssignment followed by
    Add-midPointOrgAssignment.
    Only assignments with the relation in -Relation are moved (default: the default relation, member).
    If the user has no such assignment of -From, the cmdlet stops with an error and changes nothing.
    If the user already has -To with that relation, only the assignments of -From are removed.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER From
    The org the user leaves: name, OID, or an object from Get-midPointOrg.

    .PARAMETER To
    The org the user joins: name, OID, or an object from Get-midPointOrg.

    .PARAMETER Relation
    The relation to move, e.g. manager. Without it the default relation (member) is moved.

    .PARAMETER PassThru
    Returns the user's assignments of the -To org.

    .EXAMPLE
    Move-midPointOrgAssignment jack -From 'Old Org' -To 'New Org'

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Move-midPointOrgAssignment -From 'Old Org' -To 'New Org' -Relation manager -PassThru
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.OrgAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [Parameter(Mandatory)]
        [object] $From,

        [Parameter(Mandatory)]
        [object] $To,

        [string] $Relation,

        [switch] $PassThru
    )

    process {
        Move-midPointAssignment -Kind Org -Cmdlet $PSCmdlet -Parameters $PSBoundParameters
    }
}
