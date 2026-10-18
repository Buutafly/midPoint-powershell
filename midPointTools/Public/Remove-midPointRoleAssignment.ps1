function Remove-midPointRoleAssignment {
    <#
    .SYNOPSIS
    Removes a role assignment from a midPoint user.

    .DESCRIPTION
    Deletes the user's assignments of the role by their container id. Without -AssignmentId all
    assignments of the role are removed (e.g. member and manager). midPoint then deprovisions what
    the role induced, according to your configuration.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Role
    The role: name, OID, or an object from Get-midPointRole.

    .PARAMETER AssignmentId
    Remove only the assignment with this container id (see Get-midPointRoleAssignment).

    .EXAMPLE
    Remove-midPointRoleAssignment jack -Role 'Some Role'

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
        [object] $Role,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Nullable[long]] $AssignmentId
    )

    process {
        Remove-midPointAssignment -Kind Role -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Role
    }
}
