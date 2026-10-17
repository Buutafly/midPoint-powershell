function Get-midPointRoleAssignmentRaw {
    # Reads the user (with resolveNames, so targetRef carries targetName) and returns
    # the user plus its role assignments, optionally only those to one role OID.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $UserOid,
        [string] $RoleOid
    )

    $user = Get-midPointObjectByOid -Type users -Oid $UserOid -Options 'resolveNames'
    $assignments = @(Get-midPointProperty $user 'assignment') | Where-Object {
        $ref = Get-midPointProperty $_ 'targetRef'
        $ref -and "$(Get-midPointProperty $ref 'type')" -match '(^|[#:])RoleType$' -and
        (-not $RoleOid -or (Get-midPointProperty $ref 'oid') -eq $RoleOid)
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
