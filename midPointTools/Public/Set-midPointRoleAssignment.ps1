function Set-midPointRoleAssignment {
    <#
    .SYNOPSIS
    Changes the status or validity of an existing role assignment.

    .DESCRIPTION
    Changes assignment[id]/activation of the user's assignment of the role without removing it,
    e.g. to extend validTo or to suspend the assignment. If the user has the role assigned more
    than once (e.g. with different relations), select one with -AssignmentId.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Role
    The role: name, OID, or an object from Get-midPointRole.

    .PARAMETER AssignmentId
    The assignment's container id (see Get-midPointRoleAssignment).

    .PARAMETER AdministrativeStatus
    Enabled, Disabled, or None. None removes the explicit status, so the validity dates decide again.

    .PARAMETER ValidFrom
    The assignment is active from this point in time.

    .PARAMETER ValidTo
    The assignment is active until this point in time.

    .PARAMETER ClearValidFrom
    Removes validFrom.

    .PARAMETER ClearValidTo
    Removes validTo.

    .PARAMETER PassThru
    Returns the assignment after the change.

    .EXAMPLE
    Set-midPointRoleAssignment jack -Role 'Some Role' -ValidTo (Get-Date).AddMonths(6)

    .EXAMPLE
    Set-midPointRoleAssignment jack -Role 'Some Role' -AdministrativeStatus Disabled
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.RoleAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('UserOid', 'Oid')]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [Alias('RoleOid')]
        [object] $Role,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Nullable[long]] $AssignmentId,

        [ValidateSet('Enabled', 'Disabled', 'None')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,
        [switch] $ClearValidFrom,
        [switch] $ClearValidTo,

        [switch] $PassThru
    )

    process {
        Set-midPointAssignment -Kind Role -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Role
    }
}
