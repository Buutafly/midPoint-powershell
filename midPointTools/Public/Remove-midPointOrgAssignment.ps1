function Remove-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Removes an org assignment (membership) from a midPoint user.

    .DESCRIPTION
    Deletes the user's assignments of the org by their container id. Without -AssignmentId all
    assignments of the org are removed (e.g. member and manager). midPoint then deprovisions what
    the org induced, according to your configuration.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Org
    The org: name, OID, or an object from Get-midPointOrg.

    .PARAMETER AssignmentId
    Remove only the assignment with this container id (see Get-midPointOrgAssignment).

    .EXAMPLE
    Remove-midPointOrgAssignment jack -Org 'Some Org'

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
        [object] $Org,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Nullable[long]] $AssignmentId
    )

    process {
        Remove-midPointAssignment -Kind Org -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Org
    }
}
