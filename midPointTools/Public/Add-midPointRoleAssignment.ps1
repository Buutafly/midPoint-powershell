function Add-midPointRoleAssignment {
    <#
    .SYNOPSIS
    Assigns a role to a midPoint user.

    .DESCRIPTION
    Adds an assignment with targetRef to the role, optionally with its own status and validity.
    midPoint then provisions what the role induces, as for an assignment made in the GUI.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Role
    The role: name, OID, or an object from Get-midPointRole.

    .PARAMETER Relation
    The relation, e.g. manager or approver. Without it midPoint uses the default relation (member).

    .PARAMETER AdministrativeStatus
    Enabled or Disabled for this assignment only.

    .PARAMETER ValidFrom
    The assignment is active from this point in time.

    .PARAMETER ValidTo
    The assignment is active until this point in time.

    .PARAMETER PassThru
    Returns the user's assignments of this role.

    .EXAMPLE
    Add-midPointRoleAssignment jack -Role 'Some Role'

    .EXAMPLE
    Add-midPointRoleAssignment jack -Role 'Some Role' -ValidTo (Get-Date).AddDays(30) -PassThru
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.RoleAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1)]
        [object] $Role,

        [string] $Relation,

        [ValidateSet('Enabled', 'Disabled')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,

        [switch] $PassThru
    )

    begin {
        $roleOid = Resolve-midPointObjectOid -InputObject $Role -Type roles
    }

    process {
        Add-midPointAssignment -Kind Role -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Role -TargetOid $roleOid
    }
}
