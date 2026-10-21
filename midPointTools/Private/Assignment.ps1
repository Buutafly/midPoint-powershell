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

function New-midPointAssignmentValue {
    # The assignment container for an 'add' delta: targetRef with type and relation, optional activation
    # from $Parameters (Relation, AdministrativeStatus, ValidFrom, ValidTo).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory object only.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [string] $TargetOid,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters
    )

    $targetRef = [ordered]@{ oid = $TargetOid; type = $script:midPointAssignmentKind[$Kind].RefType }
    if ($Parameters['Relation']) { $targetRef.relation = ConvertTo-midPointRelation $Parameters['Relation'] }
    $assignment = [ordered]@{ targetRef = $targetRef }
    if ($Parameters['AdministrativeStatus']) { Set-midPointNestedValue -Target $assignment -Path 'activation/administrativeStatus' -Value (ConvertTo-midPointActivationStatus $Parameters['AdministrativeStatus']) }
    if ($Parameters.Keys -contains 'ValidFrom') { Set-midPointNestedValue -Target $assignment -Path 'activation/validFrom' -Value (ConvertTo-midPointDateTime $Parameters['ValidFrom']) }
    if ($Parameters.Keys -contains 'ValidTo') { Set-midPointNestedValue -Target $assignment -Path 'activation/validTo' -Value (ConvertTo-midPointDateTime $Parameters['ValidTo']) }
    $assignment
}

function Test-midPointAssignmentRelation {
    # True when the assignment's relation is $Relation. An empty $Relation or 'default' means the default
    # relation: no relation in targetRef, or org:default.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [object] $Assignment,
        [AllowEmptyString()] [string] $Relation
    )

    $want = if ($Relation) { ConvertFrom-midPointQName $Relation } else { 'default' }
    $have = ConvertFrom-midPointQName (Get-midPointProperty (Get-midPointProperty $Assignment 'targetRef') 'relation')
    if (-not $have) { $have = 'default' }
    $have -eq $want
}

function Get-midPointAssignmentTargetLabel {
    # 'Some Role (oid), Other Role (oid)' for ShouldProcess.
    [CmdletBinding()]
    [OutputType([string])]
    param([object[]] $Target, [string[]] $TargetOid)

    @(for ($i = 0; $i -lt $TargetOid.Count; $i++) { "$(Get-midPointIdentityLabel $Target[$i]) ($($TargetOid[$i]))" }) -join ', '
}

function Add-midPointAssignment {
    # Add-midPoint<Kind>Assignment: one PATCH with one 'add' delta per target. $Parameters are the caller's
    # bound parameters (Identity, Relation, activation, PassThru); $Cmdlet is the caller's $PSCmdlet, so
    # -WhatIf / -Confirm apply.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters,
        [Parameter(Mandatory)] [object[]] $Target,
        [Parameter(Mandatory)] [string[]] $TargetOid
    )

    $k = $script:midPointAssignmentKind[$Kind]
    $userOid = Resolve-midPointObjectOid -InputObject $Parameters['Identity'] -Type users
    $deltas = foreach ($oid in $TargetOid) {
        New-midPointItemDelta -ModificationType add -Path 'assignment' -Value (New-midPointAssignmentValue -Kind $Kind -TargetOid $oid -Parameters $Parameters)
    }

    $label = Get-midPointIdentityLabel $Parameters['Identity']
    if (-not $Cmdlet.ShouldProcess("$label ($userOid)", "Assign $($k.Label) $(Get-midPointAssignmentTargetLabel $Target $TargetOid)")) { return }

    Invoke-midPointModify -Type users -Oid $userOid -ItemDelta @($deltas)
    if ($Parameters['PassThru']) {
        Get-midPointAssignmentList -Kind $Kind -Identity $userOid | Where-Object { $TargetOid -contains $_."${Kind}Oid" }
    }
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
    # Remove-midPoint<Kind>Assignment: deletes the matching assignments of all targets by their container id,
    # in one PATCH.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters,
        [Parameter(Mandatory)] [object[]] $Target
    )

    $k = $script:midPointAssignmentKind[$Kind]
    $assignmentId = $Parameters['AssignmentId']
    if ($null -ne $assignmentId -and $Target.Count -gt 1) {
        throw [System.ArgumentException]::new("-AssignmentId needs a single $($k.Label); $($Target.Count) were given.")
    }
    $userOid = Resolve-midPointObjectOid -InputObject $Parameters['Identity'] -Type users
    $targetOids = @(foreach ($t in $Target) { Resolve-midPointObjectOid -InputObject $t -Type $k.Collection })
    $data = Get-midPointAssignmentRaw -UserOid $userOid -Kind $Kind

    $label = Get-midPointIdentityLabel $Parameters['Identity']
    $ids = [System.Collections.Generic.List[object]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $targetOids.Count; $i++) {
        $targetLabel = Get-midPointIdentityLabel $Target[$i]
        $matching = @($data.Assignments | Where-Object {
                (Get-midPointProperty (Get-midPointProperty $_ 'targetRef') 'oid') -eq $targetOids[$i] -and
                ($null -eq $assignmentId -or [long](Get-midPointContainerId $_) -eq $assignmentId)
            })
        if ($matching.Count -eq 0) {
            Write-Warning "User '$label' has no assignment of $($k.Label) '$targetLabel'$(if ($null -ne $assignmentId) { " with id $assignmentId" }). Nothing removed."
            continue
        }
        $targetIds = @($matching | ForEach-Object { Get-midPointContainerId $_ } | Where-Object { $null -ne $_ })
        if ($targetIds.Count -ne $matching.Count) { throw [System.InvalidOperationException]::new("An assignment of $($k.Label) '$targetLabel' on user '$label' has no container id.") }
        foreach ($id in $targetIds) { $ids.Add($id) }
        $removed.Add("$targetLabel (assignment $($targetIds -join ', '))")
    }
    if ($ids.Count -eq 0) { return }
    if (-not $Cmdlet.ShouldProcess("$label ($userOid)", "Remove $($k.Label) assignment(s): $($removed -join '; ')")) { return }

    $deltas = foreach ($id in $ids) {
        New-midPointItemDelta -ModificationType delete -Path 'assignment' -Value ([ordered]@{ '@id' = $id })
    }
    Invoke-midPointModify -Type users -Oid $userOid -ItemDelta @($deltas)
}

function Move-midPointAssignment {
    # Move-midPoint<Kind>Assignment: deletes the user's assignments of From (with the relation) and adds To
    # (same relation) in one PATCH. If the user already has To with that relation, only From is removed.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called on the public cmdlet ($Cmdlet).')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Role', 'Org')] [string] $Kind,
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet] $Cmdlet,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Parameters
    )

    $k = $script:midPointAssignmentKind[$Kind]
    $from = $Parameters['From']
    $to = $Parameters['To']
    $relation = [string]$Parameters['Relation']
    $userOid = Resolve-midPointObjectOid -InputObject $Parameters['Identity'] -Type users
    $fromOid = Resolve-midPointObjectOid -InputObject $from -Type $k.Collection
    $toOid = Resolve-midPointObjectOid -InputObject $to -Type $k.Collection
    if ($fromOid -eq $toOid) { throw [System.ArgumentException]::new("-From and -To are the same $($k.Label) ($fromOid).") }

    $data = Get-midPointAssignmentRaw -UserOid $userOid -Kind $Kind
    $ofTarget = {
        param($oid)
        @($data.Assignments | Where-Object {
                (Get-midPointProperty (Get-midPointProperty $_ 'targetRef') 'oid') -eq $oid -and (Test-midPointAssignmentRelation -Assignment $_ -Relation $relation)
            })
    }
    $fromAssignments = & $ofTarget $fromOid
    $toAssignments = & $ofTarget $toOid

    $label = Get-midPointIdentityLabel $Parameters['Identity']
    $relationLabel = if ($relation) { ConvertFrom-midPointQName $relation } else { 'default' }
    if ($fromAssignments.Count -eq 0) {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new("User '$label' has no assignment of $($k.Label) '$(Get-midPointIdentityLabel $from)' with relation $relationLabel."),
            'midPointAssignmentNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $from)
        $Cmdlet.ThrowTerminatingError($record)
    }
    $ids = @($fromAssignments | ForEach-Object { Get-midPointContainerId $_ } | Where-Object { $null -ne $_ })
    if ($ids.Count -ne $fromAssignments.Count) { throw [System.InvalidOperationException]::new("An assignment of $($k.Label) '$(Get-midPointIdentityLabel $from)' on user '$label' has no container id.") }

    $deltas = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $ids) { $deltas.Add((New-midPointItemDelta -ModificationType delete -Path 'assignment' -Value ([ordered]@{ '@id' = $id }))) }
    $action = "Move from $($k.Label) $(Get-midPointIdentityLabel $from) ($fromOid, assignment $($ids -join ', ')) to $(Get-midPointIdentityLabel $to) ($toOid), relation $relationLabel"
    if ($toAssignments.Count -gt 0) {
        Write-Verbose "User '$label' already has $($k.Label) '$(Get-midPointIdentityLabel $to)' with relation $relationLabel; only the assignment(s) of '$(Get-midPointIdentityLabel $from)' are removed."
        $action = "$action (already assigned: only remove)"
    }
    else {
        $value = New-midPointAssignmentValue -Kind $Kind -TargetOid $toOid -Parameters @{ Relation = $relation }
        $deltas.Add((New-midPointItemDelta -ModificationType add -Path 'assignment' -Value $value))
    }
    if (-not $Cmdlet.ShouldProcess("$label ($userOid)", $action)) { return }

    Invoke-midPointModify -Type users -Oid $userOid -ItemDelta $deltas.ToArray()
    if ($Parameters['PassThru']) { Get-midPointAssignmentList -Kind $Kind -Identity $userOid -Target $toOid }
}
