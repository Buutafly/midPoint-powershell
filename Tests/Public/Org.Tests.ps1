BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    function Get-SentDelta {
        param([string] $Body)
        @(($Body | ConvertFrom-Json).objectModification.itemDelta)
    }

    # $OtherOid is the org; the role assignment must not show up as an org assignment.
    $script:Org2Oid = '66666666-6666-6666-6666-666666666666'
    $script:assignments = @"
[
  { "@id": 3, "targetRef": { "oid": "$RoleOid", "type": "c:RoleType", "targetName": "Some Role" } },
  { "@id": 5, "targetRef": { "oid": "$OtherOid", "type": "c:OrgType", "relation": "org:default", "targetName": "Some Org" },
    "activation": { "effectiveStatus": "enabled", "validTo": "2027-01-31T00:00:00.000Z" } },
  { "@id": 6, "targetRef": { "oid": "$OtherOid", "type": "http://midpoint.evolveum.com/xml/ns/public/common/common-3#OrgType", "relation": "org:manager", "targetName": "Some Org" } }
]
"@
}

Describe 'Org cmdlets' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute "^GET users/$UserOid\?options=resolveNames$" (New-TestResponse -Json (Get-TestUserJson -Assignments $assignments))
        Add-TestRoute "^PATCH users/$UserOid$" (New-TestResponse -StatusCode 204)
        Add-TestRoute '^POST orgs/search$' (New-TestResponse -Json (Get-TestSearchJson -Objects "{ `"oid`": `"$OtherOid`", `"name`": `"Some Org`", `"identifier`": `"4711`" }"))
    }

    It 'Get-midPointOrg finds an org by name' {
        $o = Get-midPointOrg 'Some Org'
        $o.Oid | Should -Be $OtherOid
        $o.Identifier | Should -Be '4711'
        $o.PSObject.TypeNames | Should -Contain 'midPointTools.Org'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $Body -like '*name = \"Some Org\"*' }
    }

    It 'Get-midPointOrg returns extension items with plain keys' {
        $org = "{ `"oid`": `"$OtherOid`", `"name`": `"Some Org`", `"extension`": { `"@ns`": `"http://example.com/xml/ns/extension`", `"costCenter`": `"4711`", `"ext:sharePath`": [`"\\\\server\\share`"] } }"
        Add-TestRoute '^POST orgs/search$' (New-TestResponse -Json (Get-TestSearchJson -Objects $org))
        Add-TestRoute "^GET orgs/$OtherOid$" (New-TestResponse -Json "{ `"org`": $org }")

        foreach ($o in (Get-midPointOrg 'Some Org'), (Get-midPointOrg -Oid $OtherOid)) {
            $o.Extension.costCenter | Should -Be '4711'
            $o.Extension.sharePath | Should -Be '\\server\share'
            $o.Extension.Keys | Should -Not -Contain '@ns'
        }
    }

    It 'Get-midPointOrg returns an empty Extension when the org has none' {
        (Get-midPointOrg 'Some Org').Extension.Count | Should -Be 0
    }

    It 'Get-midPointOrgAssignment lists only org assignments, with relation' {
        $a = @(Get-midPointOrgAssignment $UserOid)
        $a.Count | Should -Be 2
        $a[0].Org | Should -Be 'Some Org'
        $a[0].OrgOid | Should -Be $OtherOid
        $a[0].Relation | Should -Be 'default'
        $a[0].ValidTo | Should -BeOfType [datetime]
        $a[1].Relation | Should -Be 'manager'
        $a[0].PSObject.TypeNames | Should -Contain 'midPointTools.OrgAssignment'
    }

    It 'Get-midPointRoleAssignment does not list org assignments' {
        @(Get-midPointRoleAssignment $UserOid).Role | Should -Be @('Some Role')
    }

    It 'Add-midPointOrgAssignment adds an assignment to the org with relation and validity' {
        Add-midPointOrgAssignment $UserOid -Org 'Some Org' -Relation manager -ValidTo ([datetime]::new(2027, 6, 30, 0, 0, 0, [System.DateTimeKind]::Utc))

        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $v = $d[0].value
            $d.Count -eq 1 -and $d[0].modificationType -eq 'add' -and $d[0].path -eq 'assignment' -and
            $v.targetRef.oid -eq $OtherOid -and $v.targetRef.type -eq 'c:OrgType' -and $v.targetRef.relation -eq 'org:manager' -and
            $Body -like '*"validTo":"2027-06-30T00:00:00.000+00:00"*'
        }
    }

    It 'Add-midPointOrgAssignment -PassThru returns the org assignments' {
        $a = @(Add-midPointOrgAssignment $UserOid -Org $OtherOid -PassThru)
        $a.Count | Should -Be 2
        $a.Org | Select-Object -Unique | Should -Be 'Some Org'
    }

    It 'Set-midPointOrgAssignment asks for -AssignmentId when the org is assigned twice' {
        { Set-midPointOrgAssignment $UserOid -Org $OtherOid -ValidTo (Get-Date) } | Should -Throw '*org assigned more than once*5, 6*'

        Set-midPointOrgAssignment $UserOid -Org $OtherOid -AssignmentId 6 -ClearValidTo
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
            $Method -eq 'PATCH' -and (Get-SentDelta $Body)[0].path -eq 'assignment[6]/activation/validTo'
        }
    }

    It 'Remove-midPointOrgAssignment takes piped assignments (only the manager one)' {
        Get-midPointOrgAssignment $UserOid | Where-Object Relation -EQ 'manager' | Remove-midPointOrgAssignment
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $d.Count -eq 1 -and $d[0].modificationType -eq 'delete' -and $d[0].value.'@id' -eq 6
        }
    }

    It 'Remove-midPointOrgAssignment warns when there is nothing to remove' {
        Remove-midPointOrgAssignment $UserOid -Org '99999999-9999-9999-9999-999999999999' -WarningVariable w -WarningAction SilentlyContinue
        $w | Should -Match 'no assignment of org'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'Remove-midPointOrgAssignment -WhatIf sends nothing' {
        Remove-midPointOrgAssignment $UserOid -Org $OtherOid -WhatIf
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'Add-midPointOrgAssignment adds several orgs in one PATCH' {
        Add-midPointOrgAssignment $UserOid -Org $OtherOid, $Org2Oid

        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $d.Count -eq 2 -and (@($d.value.targetRef.oid) -join ',') -eq "$OtherOid,$Org2Oid" -and
            ($d.value.targetRef.type | Select-Object -Unique) -eq 'c:OrgType' -and $null -eq $d[0].value.targetRef.relation
        }
    }

    It 'Remove-midPointOrgAssignment removes several orgs in one PATCH and warns for the missing one' {
        Remove-midPointOrgAssignment $UserOid -Org 'Some Org', $Org2Oid -WarningVariable w -WarningAction SilentlyContinue
        "$w" | Should -BeLike "*$Org2Oid*"
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and (@((Get-SentDelta $Body).value.'@id') -join ',') -eq '5,6'
        }
    }

    Context 'Move-midPointOrgAssignment' {
        It 'deletes the -From assignment and adds -To in one PATCH' {
            Move-midPointOrgAssignment $UserOid -From 'Some Org' -To $Org2Oid

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                if ($Method -ne 'PATCH') { return $false }
                $d = Get-SentDelta $Body
                # Only the member assignment (id 5) moves; the manager assignment (id 6) stays.
                $d.Count -eq 2 -and
                $d[0].modificationType -eq 'delete' -and $d[0].value.'@id' -eq 5 -and
                $d[1].modificationType -eq 'add' -and $d[1].path -eq 'assignment' -and
                $d[1].value.targetRef.oid -eq $Org2Oid -and $d[1].value.targetRef.type -eq 'c:OrgType' -and
                $null -eq $d[1].value.targetRef.PSObject.Properties['relation']
            }
        }

        It 'moves only the assignments with -Relation' {
            Move-midPointOrgAssignment $UserOid -From $OtherOid -To $Org2Oid -Relation manager

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                if ($Method -ne 'PATCH') { return $false }
                $d = Get-SentDelta $Body
                $d.Count -eq 2 -and $d[0].value.'@id' -eq 6 -and $d[1].value.targetRef.relation -eq 'org:manager'
            }
        }

        It 'only removes -From when the user is already in -To' {
            $both = @"
[
  { "@id": 5, "targetRef": { "oid": "$OtherOid", "type": "c:OrgType", "targetName": "Some Org" } },
  { "@id": 8, "targetRef": { "oid": "$Org2Oid", "type": "c:OrgType", "relation": "org:default", "targetName": "Org 2" } }
]
"@
            Add-TestRoute "^GET users/$UserOid\?options=resolveNames$" (New-TestResponse -Json (Get-TestUserJson -Assignments $both))

            Move-midPointOrgAssignment $UserOid -From $Org2Oid -To $OtherOid

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                if ($Method -ne 'PATCH') { return $false }
                $d = Get-SentDelta $Body
                $d.Count -eq 1 -and $d[0].modificationType -eq 'delete' -and $d[0].value.'@id' -eq 8
            }
        }

        It 'stops and sends nothing when the user is not in -From' {
            $err = $null
            try { Move-midPointOrgAssignment $UserOid -From $Org2Oid -To $OtherOid } catch { $err = $_ }

            $err.FullyQualifiedErrorId | Should -BeLike 'midPointAssignmentNotFound*'
            $err.Exception.Message | Should -BeLike '*relation default*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'refuses the same org as -From and -To' {
            { Move-midPointOrgAssignment $UserOid -From 'Some Org' -To $OtherOid } | Should -Throw '*same org*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'returns the -To assignments with -PassThru and sends nothing with -WhatIf' {
            Move-midPointOrgAssignment $UserOid -From $OtherOid -To $Org2Oid -WhatIf
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }

            $a = @(Move-midPointOrgAssignment $UserOid -From $OtherOid -To $Org2Oid -PassThru)
            # The mocked user does not change, so -PassThru reads no assignment of -To.
            $a.Count | Should -Be 0
            # One read for -WhatIf, one before the PATCH and one for -PassThru.
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 3 -Exactly -ParameterFilter { $Method -eq 'GET' }
        }

        It 'takes piped users' {
            Add-TestRoute "^GET users/$UserOid$" (New-TestResponse -Json (Get-TestUserJson))
            Get-midPointUser -Oid $UserOid | Move-midPointOrgAssignment -From $OtherOid -To $Org2Oid
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
        }
    }
}
