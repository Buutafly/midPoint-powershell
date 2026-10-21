BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    function Get-SentDelta {
        param([string] $Body)
        @(($Body | ConvertFrom-Json).objectModification.itemDelta)
    }

    # $OtherOid is the org; the role assignment must not show up as an org assignment.
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
}
