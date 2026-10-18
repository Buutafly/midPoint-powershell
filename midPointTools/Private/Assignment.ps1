# Assignments to roles and orgs share one implementation; the *-midPointRoleAssignment and
# *-midPointOrgAssignment cmdlets are thin wrappers that pass -Kind.
$script:midPointAssignmentKind = @{
    Role = @{ Collection = 'roles'; RefType = 'c:RoleType'; TypeName = 'RoleType'; Label = 'role' }
    Org  = @{ Collection = 'orgs'; RefType = 'c:OrgType'; TypeName = 'OrgType'; Label = 'org' }
}

function Get-midPointAssignmentRaw {
    # Reads the user (with resolveNames, so targetRef carries targetName) and returns
    # the user plus its assignments of one kind, optionally only those to one target OID.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $UserOid,
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [string] $TargetOid
    )

    $typeName = $script:midPointAssignmentKind[$Kind].TypeName
    $user = Get-midPointObjectByOid -Type users -Oid $UserOid -Options 'resolveNames'
    $assignments = @(Get-midPointProperty $user 'assignment') | Where-Object {
        $ref = Get-midPointProperty $_ 'targetRef'
        $ref -and "$(Get-midPointProperty $ref 'type')" -match "(^|[#:])$typeName$" -and
        (-not $TargetOid -or (Get-midPointProperty $ref 'oid') -eq $TargetOid)
    }
    [pscustomobject]@{
        User        = $user
        Assignments = @($assignments)
    }
}

function ConvertTo-midPointRelation {
    # 'manager' -> 'org:manager'; a value with a prefix or a full URI is kept.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Relation)

    if ($Relation -match '[:#]') { return $Relation }
    "org:$Relation"
}

function Get-midPointAssignmentList {
    # Get-midPoint<Kind>Assignment: the user's assignments of one kind as module objects.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [object] $Identity,
        [object] $Target
    )

    $userOid = Resolve-midPointObjectOid -InputObject $Identity -Type users
    $targetOid = if ($null -ne $Target) { Resolve-midPointObjectOid -InputObject $Target -Type $script:midPointAssignmentKind[$Kind].Collection } else { $null }
    $data = Get-midPointAssignmentRaw -UserOid $userOid -Kind $Kind -TargetOid $targetOid
    foreach ($a in $data.Assignments) {
        ConvertTo-midPointAssignmentObject -Assignment $a -User $data.User -Kind $Kind
    }
}

function Add-midPointAssignment {
    # Add-midPoint<Kind>Assignment. $Parameters are the caller's bound parameters (Identity, Relation,
    # activation, PassThru); $Cmdlet is the caller's $PSCmdlet, so -WhatIf / -Confirm apply.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters,
        [Parameter(Mandatory)] [object] $Target,
        [Parameter(Mandatory)] [string] $TargetOid
    )

    $k = $script:midPointAssignmentKind[$Kind]
    $userOid = Resolve-midPointObjectOid -InputObject $Parameters['Identity'] -Type users

    $targetRef = [ordered]@{ oid = $TargetOid; type = $k.RefType }
    if ($Parameters['Relation']) { $targetRef.relation = ConvertTo-midPointRelation $Parameters['Relation'] }
    $assignment = [ordered]@{ targetRef = $targetRef }
    if ($Parameters['AdministrativeStatus']) { Set-midPointNestedValue -Target $assignment -Path 'activation/administrativeStatus' -Value (ConvertTo-midPointActivationStatus $Parameters['AdministrativeStatus']) }
    if ($Parameters.Keys -contains 'ValidFrom') { Set-midPointNestedValue -Target $assignment -Path 'activation/validFrom' -Value (ConvertTo-midPointDateTime $Parameters['ValidFrom']) }
    if ($Parameters.Keys -contains 'ValidTo') { Set-midPointNestedValue -Target $assignment -Path 'activation/validTo' -Value (ConvertTo-midPointDateTime $Parameters['ValidTo']) }

    $label = Get-midPointIdentityLabel $Parameters['Identity']
    if (-not $Cmdlet.ShouldProcess("$label ($userOid)", "Assign $($k.Label) $(Get-midPointIdentityLabel $Target) ($TargetOid)")) { return }

    Invoke-midPointModify -Type users -Oid $userOid -ItemDelta @(
        New-midPointItemDelta -ModificationType add -Path 'assignment' -Value $assignment
    )
    if ($Parameters['PassThru']) { Get-midPointAssignmentList -Kind $Kind -Identity $userOid -Target $TargetOid }
}

function Select-midPointAssignment {
    # The user's assignments of one target, narrowed to -AssignmentId when given.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [string] $UserOid,
        [Parameter(Mandatory)] [string] $TargetOid,
        [Nullable[long]] $AssignmentId
    )

    $data = Get-midPointAssignmentRaw -UserOid $UserOid -Kind $Kind -TargetOid $TargetOid
    $matching = @($data.Assignments)
    if ($null -ne $AssignmentId) {
        $matching = @($matching | Where-Object { [long](Get-midPointContainerId $_) -eq $AssignmentId })
    }
    , $matching
}

function Set-midPointAssignment {
    # Set-midPoint<Kind>Assignment: changes assignment[id]/activation of one assignment.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters,
        [Parameter(Mandatory)] [object] $Target
    )

    $k = $script:midPointAssignmentKind[$Kind]
    $activationParams = Get-midPointActivationParameter -BoundParameters $Parameters
    # Validate the parameters before any request is sent.
    $null = New-midPointActivationDelta -Prefix 'activation' @activationParams
    if ($activationParams.Count -eq 0) {
        throw [System.ArgumentException]::new('Nothing to change. Give -AdministrativeStatus, -ValidFrom, -ValidTo, -ClearValidFrom or -ClearValidTo.')
    }

    $userOid = Resolve-midPointObjectOid -InputObject $Parameters['Identity'] -Type users
    $targetOid = Resolve-midPointObjectOid -InputObject $Target -Type $k.Collection
    $assignmentId = $Parameters['AssignmentId']
    $matching = Select-midPointAssignment -Kind $Kind -UserOid $userOid -TargetOid $targetOid -AssignmentId $assignmentId

    $label = Get-midPointIdentityLabel $Parameters['Identity']
    $targetLabel = Get-midPointIdentityLabel $Target
    if ($matching.Count -eq 0) {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new("User '$label' has no assignment of $($k.Label) '$targetLabel'$(if ($null -ne $assignmentId) { " with id $assignmentId" })."),
            'midPointAssignmentNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Target)
        $Cmdlet.ThrowTerminatingError($record)
    }
    if ($matching.Count -gt 1) {
        $ids = ($matching | ForEach-Object { Get-midPointContainerId $_ }) -join ', '
        throw [System.InvalidOperationException]::new("User '$label' has the $($k.Label) assigned more than once (assignment ids $ids). Select one with -AssignmentId.")
    }

    $id = Get-midPointContainerId $matching[0]
    if ($null -eq $id) { throw [System.InvalidOperationException]::new("The assignment of $($k.Label) '$targetLabel' on user '$label' has no container id.") }
    $deltas = New-midPointActivationDelta -Prefix "assignment[$id]/activation" @activationParams
    if (-not $Cmdlet.ShouldProcess("$label ($userOid)", "Change assignment $id of $($k.Label) $targetLabel")) { return }

    Invoke-midPointModify -Type users -Oid $userOid -ItemDelta $deltas
    if ($Parameters['PassThru']) {
        Get-midPointAssignmentList -Kind $Kind -Identity $userOid -Target $targetOid | Where-Object AssignmentId -EQ $id
    }
}

function Remove-midPointAssignment {
    # Remove-midPoint<Kind>Assignment: deletes the matching assignments by their container id.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters,
        [Parameter(Mandatory)] [object] $Target
    )

    $k = $script:midPointAssignmentKind[$Kind]
    $userOid = Resolve-midPointObjectOid -InputObject $Parameters['Identity'] -Type users
    $targetOid = Resolve-midPointObjectOid -InputObject $Target -Type $k.Collection
    $assignmentId = $Parameters['AssignmentId']
    $matching = Select-midPointAssignment -Kind $Kind -UserOid $userOid -TargetOid $targetOid -AssignmentId $assignmentId

    $label = Get-midPointIdentityLabel $Parameters['Identity']
    $targetLabel = Get-midPointIdentityLabel $Target
    if ($matching.Count -eq 0) {
        Write-Warning "User '$label' has no assignment of $($k.Label) '$targetLabel'$(if ($null -ne $assignmentId) { " with id $assignmentId" }). Nothing removed."
        return
    }

    $ids = @($matching | ForEach-Object { Get-midPointContainerId $_ } | Where-Object { $null -ne $_ })
    if ($ids.Count -ne $matching.Count) { throw [System.InvalidOperationException]::new("An assignment of $($k.Label) '$targetLabel' on user '$label' has no container id.") }
    if (-not $Cmdlet.ShouldProcess("$label ($userOid)", "Remove assignment(s) $($ids -join ', ') of $($k.Label) $targetLabel")) { return }

    $deltas = foreach ($id in $ids) {
        New-midPointItemDelta -ModificationType delete -Path 'assignment' -Value ([ordered]@{ '@id' = $id })
    }
    Invoke-midPointModify -Type users -Oid $userOid -ItemDelta @($deltas)
}
