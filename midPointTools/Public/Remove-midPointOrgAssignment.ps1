function Remove-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Removes an org assignment (membership) from a midPoint user.

    .DESCRIPTION
    Deletes the user's assignments of the org by their container id. Without -AssignmentId all
    assignments of the org are removed (e.g. member and manager). midPoint then deprovisions what
    the org induced, according to your configuration.
    Several orgs in -Org are removed in one modification (one PATCH). Piped assignment objects
    (from Get-midPointOrgAssignment) are removed with one PATCH per object; to remove several in one
    modification, give them in -Org.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Org
    One or more orgs: name, OID, or an object from Get-midPointOrg.

    .PARAMETER AssignmentId
    Remove only the assignment with this container id (see Get-midPointOrgAssignment). Only with a single target.

    .EXAMPLE
    Remove-midPointOrgAssignment jack -Org 'Some Org'

    .EXAMPLE
    Remove-midPointOrgAssignment jack -Org 'Some Org', 'Other Org'

    Removes the assignments of both orgs in one modification.

    .EXAMPLE
    Get-midPointOrgAssignment jack | Where-Object Relation -eq 'manager' | Remove-midPointOrgAssignment
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('UserOid', 'Oid')]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [Alias('OrgOid')]
        [object[]] $Org,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Nullable[long]] $AssignmentId
    )

    process {
        Remove-midPointAssignment -Kind Org -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Org
    }
}
