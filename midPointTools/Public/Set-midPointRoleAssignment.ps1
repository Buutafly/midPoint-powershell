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
        $activationParams = Get-midPointActivationParameter -BoundParameters $PSBoundParameters
        # Validate the parameters before any request is sent.
        $null = New-midPointActivationDelta -Prefix 'activation' @activationParams
        if ($activationParams.Count -eq 0) {
            throw [System.ArgumentException]::new('Nothing to change. Give -AdministrativeStatus, -ValidFrom, -ValidTo, -ClearValidFrom or -ClearValidTo.')
        }

        $userOid = Resolve-midPointObjectOid -InputObject $Identity -Type users
        $roleOid = Resolve-midPointObjectOid -InputObject $Role -Type roles
        $data = Get-midPointRoleAssignmentRaw -UserOid $userOid -RoleOid $roleOid
        $matching = @($data.Assignments)
        if ($null -ne $AssignmentId) {
            $matching = @($matching | Where-Object { [long](Get-midPointContainerId $_) -eq $AssignmentId })
        }

        $label = Get-midPointIdentityLabel $Identity
        if ($matching.Count -eq 0) {
            $record = [System.Management.Automation.ErrorRecord]::new(
                [System.Management.Automation.ItemNotFoundException]::new("User '$label' has no assignment of role '$(Get-midPointIdentityLabel $Role)'$(if ($null -ne $AssignmentId) { " with id $AssignmentId" })."),
                'midPointAssignmentNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Role)
            $PSCmdlet.ThrowTerminatingError($record)
        }
        if ($matching.Count -gt 1) {
            $ids = ($matching | ForEach-Object { Get-midPointContainerId $_ }) -join ', '
            throw [System.InvalidOperationException]::new("User '$label' has the role assigned more than once (assignment ids $ids). Select one with -AssignmentId.")
        }

        $id = Get-midPointContainerId $matching[0]
        if ($null -eq $id) { throw [System.InvalidOperationException]::new("The assignment of role '$(Get-midPointIdentityLabel $Role)' on user '$label' has no container id.") }
        $deltas = New-midPointActivationDelta -Prefix "assignment[$id]/activation" @activationParams
        if (-not $PSCmdlet.ShouldProcess("$label ($userOid)", "Change assignment $id of role $(Get-midPointIdentityLabel $Role)")) { return }

        Invoke-midPointModify -Type users -Oid $userOid -ItemDelta $deltas
        if ($PassThru) {
            Get-midPointRoleAssignment -Identity $userOid -Role $roleOid | Where-Object AssignmentId -EQ $id
        }
    }
}
