BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    function Get-SentDelta {
        param([string] $Body)
        @(($Body | ConvertFrom-Json).objectModification.itemDelta)
    }

    $script:assignments = @"
[
  { "@id": 3, "targetRef": { "oid": "$RoleOid", "type": "c:RoleType", "targetName": "Some Role" },
    "activation": { "effectiveStatus": "enabled", "validTo": "2027-01-31T00:00:00.000Z" } },
  { "@id": 4, "targetRef": { "oid": "$OtherOid", "type": "c:OrgType", "targetName": "Some Org" } },
  { "@id": 7, "targetRef": { "oid": "$OtherOid", "type": "http://midpoint.evolveum.com/xml/ns/public/common/common-3#RoleType", "relation": "org:manager", "targetName": "Other Role" } }
]
"@
    $script:twice = @"
[
  { "@id": 3, "targetRef": { "oid": "$RoleOid", "type": "c:RoleType" } },
  { "id": 9, "targetRef": { "oid": "$RoleOid", "type": "c:RoleType", "relation": "org:approver" } }
]
"@
}

Describe 'Role cmdlets' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute "^GET users/$UserOid\?options=resolveNames$" (New-TestResponse -Json (Get-TestUserJson -Assignments $assignments))
        Add-TestRoute "^PATCH users/$UserOid$" (New-TestResponse -StatusCode 204)
        Add-TestRoute '^POST roles/search$' (New-TestResponse -Json (Get-TestSearchJson -Objects "{ `"oid`": `"$RoleOid`", `"name`": `"Some Role`" }"))
    }

    It 'Get-midPointRole finds a role by name' {
        $r = Get-midPointRole 'Some Role'
        $r.Oid | Should -Be $RoleOid
        $r.PSObject.TypeNames | Should -Contain 'midPointTools.Role'
    }

    It 'Get-midPointRoleAssignment lists only role assignments' {
        $a = @(Get-midPointRoleAssignment $UserOid)
        $a.Count | Should -Be 2
        $a[0].Role | Should -Be 'Some Role'
        $a[0].AssignmentId | Should -Be 3
        $a[0].ValidTo | Should -BeOfType [datetime]
        $a[1].Relation | Should -Be 'manager'
    }

    It 'Get-midPointRoleAssignment -Role filters by role' {
        @(Get-midPointRoleAssignment $UserOid -Role 'Some Role').RoleOid | Should -Be @($RoleOid)
    }

    It 'Add-midPointRoleAssignment adds an assignment with relation and validity' {
        Add-midPointRoleAssignment $UserOid -Role 'Some Role' -Relation manager -AdministrativeStatus Disabled `
            -ValidFrom ([datetime]::new(2026, 11, 1, 0, 0, 0, [System.DateTimeKind]::Utc))

        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $v = $d[0].value
            $d.Count -eq 1 -and $d[0].modificationType -eq 'add' -and $d[0].path -eq 'assignment' -and
            $v.targetRef.oid -eq $RoleOid -and $v.targetRef.type -eq 'c:RoleType' -and $v.targetRef.relation -eq 'org:manager' -and
            $v.activation.administrativeStatus -eq 'disabled' -and $Body -like '*"validFrom":"2026-11-01T00:00:00.000+00:00"*'
        }
    }

    It 'Add-midPointRoleAssignment sends no relation by default' {
        Add-midPointRoleAssignment $UserOid -Role $RoleOid
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
            $Method -eq 'PATCH' -and $null -eq (Get-SentDelta $Body)[0].value.targetRef.PSObject.Properties['relation']
        }
    }

    It 'Set-midPointRoleAssignment changes the activation of the assignment by id' {
        Set-midPointRoleAssignment $UserOid -Role 'Some Role' -ValidTo ([datetime]::new(2027, 6, 30, 0, 0, 0, [System.DateTimeKind]::Utc)) -AdministrativeStatus None

        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $Body -like '*"path":"assignment`[3`]/activation/validTo","value":"2027-06-30T00:00:00.000+00:00"*' -and
            $null -ne ($d | Where-Object path -EQ 'assignment[3]/activation/administrativeStatus')
        }
    }

    It 'Set-midPointRoleAssignment asks for -AssignmentId when the role is assigned twice' {
        Add-TestRoute "^GET users/$UserOid\?options=resolveNames$" (New-TestResponse -Json (Get-TestUserJson -Assignments $twice))
        { Set-midPointRoleAssignment $UserOid -Role $RoleOid -ValidTo (Get-Date) } | Should -Throw '*3, 9*AssignmentId*'

        Set-midPointRoleAssignment $UserOid -Role $RoleOid -AssignmentId 9 -AdministrativeStatus Disabled
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
            $Method -eq 'PATCH' -and (Get-SentDelta $Body)[0].path -eq 'assignment[9]/activation/administrativeStatus'
        }
    }

    It 'Set-midPointRoleAssignment fails when the user lacks the role' {
        { Set-midPointRoleAssignment $UserOid -Role '99999999-9999-9999-9999-999999999999' -ValidTo (Get-Date) } | Should -Throw '*no assignment*'
    }

    It 'Remove-midPointRoleAssignment deletes all assignments of the role by id' {
        Add-TestRoute "^GET users/$UserOid\?options=resolveNames$" (New-TestResponse -Json (Get-TestUserJson -Assignments $twice))
        Remove-midPointRoleAssignment $UserOid -Role $RoleOid

        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $d.Count -eq 2 -and ($d.modificationType | Select-Object -Unique) -eq 'delete' -and
            (@($d.value.'@id') -join ',') -eq '3,9'
        }
    }

    It 'Remove-midPointRoleAssignment takes piped assignments' {
        Get-midPointRoleAssignment $UserOid -Role 'Some Role' | Remove-midPointRoleAssignment
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
            $Method -eq 'PATCH' -and (Get-SentDelta $Body)[0].value.'@id' -eq 3
        }
    }

    It 'Remove-midPointRoleAssignment warns when there is nothing to remove' {
        Remove-midPointRoleAssignment $UserOid -Role '99999999-9999-9999-9999-999999999999' -WarningVariable w -WarningAction SilentlyContinue
        $w | Should -Match 'Nothing removed'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }
}
