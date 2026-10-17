function Get-midPointRoleAssignment {
    <#
    .SYNOPSIS
    Lists the role assignments of a midPoint user.

    .DESCRIPTION
    Returns the user's direct role assignments with relation, assignment id, status and validity.
    Roles the user gets indirectly (via other roles, orgs or archetypes) are not listed.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Role
    Only assignments of this role: name, OID, or an object from Get-midPointRole.

    .EXAMPLE
    Get-midPointRoleAssignment jack

    .EXAMPLE
    Get-midPointRoleAssignment jack -Role 'Some Role' | Select-Object Role, ValidTo, EffectiveStatus
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.RoleAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [Parameter(Position = 1)]
        [object] $Role
    )

    process {
        $userOid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $roleOid = if ($PSBoundParameters.ContainsKey('Role')) { Resolve-midPointObjectOid -InputObject $Role -Type roles } else { $null }

        $data = Get-midPointRoleAssignmentRaw -UserOid $userOid -RoleOid $roleOid
        foreach ($a in $data.Assignments) {
            ConvertTo-midPointAssignmentObject -Assignment $a -User $data.User
        }
    }
}
