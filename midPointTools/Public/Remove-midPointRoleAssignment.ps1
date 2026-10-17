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
        $userOid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $roleOid = Resolve-midPointObjectOid -InputObject $Role -Type roles
        $data = Get-midPointRoleAssignmentRaw -UserOid $userOid -RoleOid $roleOid
        $matching = @($data.Assignments)
        if ($null -ne $AssignmentId) {
            $matching = @($matching | Where-Object { [long](Get-midPointProperty $_ 'id') -eq $AssignmentId })
        }

        $label = Get-midPointIdentityLabel $Identity
        if ($matching.Count -eq 0) {
            Write-Warning "User '$label' has no assignment of role '$(Get-midPointIdentityLabel $Role)'$(if ($null -ne $AssignmentId) { " with id $AssignmentId" }). Nothing removed."
            return
        }

        $ids = @($matching | ForEach-Object { Get-midPointProperty $_ 'id' })
        if (-not $PSCmdlet.ShouldProcess("$label ($userOid)", "Remove assignment(s) $($ids -join ', ') of role $(Get-midPointIdentityLabel $Role)")) { return }

        $deltas = foreach ($id in $ids) {
            New-midPointItemDelta -ModificationType delete -Path 'assignment' -Value ([ordered]@{ id = $id })
        }
        Invoke-midPointModify -Type users -Oid $userOid -ItemDelta @($deltas)
    }
}
