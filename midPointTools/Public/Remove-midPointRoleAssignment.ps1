function Remove-midPointRoleAssignment {
    <#
    .SYNOPSIS
    Removes a role assignment from a midPoint user.

    .DESCRIPTION
    Deletes the user's assignments of the role by their container id. Without -AssignmentId all
    assignments of the role are removed (e.g. member and manager). midPoint then deprovisions what
    the role induced, according to your configuration.
    Several roles in -Role are removed in one modification (one PATCH). Piped assignment objects
    (from Get-midPointRoleAssignment) are removed with one PATCH per object; to remove several in one
    modification, give them in -Role.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Role
    One or more roles: name, OID, or an object from Get-midPointRole.

    .PARAMETER AssignmentId
    Remove only the assignment with this container id (see Get-midPointRoleAssignment). Only with a single target.

    .EXAMPLE
    Remove-midPointRoleAssignment jack -Role 'Some Role'

    .EXAMPLE
    Remove-midPointRoleAssignment jack -Role 'Some Role', 'Other Role'

    Removes the assignments of both roles in one modification.

    .EXAMPLE
    Get-midPointRoleAssignment jack | Where-Object Relation -eq 'manager' | Remove-midPointRoleAssignment
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('UserOid', 'Oid')]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [Alias('RoleOid')]
        [object[]] $Role,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Nullable[long]] $AssignmentId
    )

    process {
        Remove-midPointAssignment -Kind Role -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Role
    }
}
