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
        $userOid = Resolve-midPointObjectOid -InputObject $Identity -Type users

        $targetRef = [ordered]@{ oid = $roleOid; type = 'c:RoleType' }
        if ($Relation) { $targetRef.relation = ConvertTo-midPointRelation $Relation }
        $assignment = [ordered]@{ targetRef = $targetRef }
        if ($AdministrativeStatus) { Set-midPointNestedValue -Target $assignment -Path 'activation/administrativeStatus' -Value (ConvertTo-midPointActivationStatus $AdministrativeStatus) }
        if ($PSBoundParameters.ContainsKey('ValidFrom')) { Set-midPointNestedValue -Target $assignment -Path 'activation/validFrom' -Value (ConvertTo-midPointDateTime $ValidFrom) }
        if ($PSBoundParameters.ContainsKey('ValidTo')) { Set-midPointNestedValue -Target $assignment -Path 'activation/validTo' -Value (ConvertTo-midPointDateTime $ValidTo) }

        $label = Get-midPointIdentityLabel $Identity
        if (-not $PSCmdlet.ShouldProcess("$label ($userOid)", "Assign role $(Get-midPointIdentityLabel $Role) ($roleOid)")) { return }

        Invoke-midPointModify -Type users -Oid $userOid -ItemDelta @(
            New-midPointItemDelta -ModificationType add -Path 'assignment' -Value $assignment
        )
        if ($PassThru) { Get-midPointRoleAssignment -Identity $userOid -Role $roleOid }
    }
}
