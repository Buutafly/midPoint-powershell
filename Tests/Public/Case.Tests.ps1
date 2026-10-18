BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    $script:CaseOid = '88888888-8888-8888-8888-888888888888'
    $script:ClosedOid = '99999999-9999-9999-9999-999999999999'

    function Get-CaseJson {
        param([string] $Oid, [string] $Account, [string] $State = 'open', [string] $WorkItems = '[]', [string] $Outcome = '')
        $outcomeJson = if ($Outcome) { ", `"outcome`": `"$Outcome`"" } else { '' }
        @"
{ "oid": "$Oid", "name": "Request to add '$Account' on 'Test Resource'", "state": "$State"$outcomeJson,
  "objectRef": { "oid": "$ResourceOid", "type": "c:ResourceType", "targetName": "Test Resource" },
  "targetRef": { "oid": "$ShadowOid", "type": "c:ShadowType", "targetName": "$Account" },
  "workItem": $WorkItems }
"@
    }

    $script:openItems = '[ { "@id": 4, "name": "Add account", "assigneeRef": [ { "oid": "00000000-0000-0000-0000-000000000002", "type": "c:UserType", "targetName": "tester" } ] } ]'
    $script:closedItems = '[ { "@id": 4, "closeTimestamp": "2026-10-18T10:00:00.000Z", "output": { "outcome": "http://midpoint.evolveum.com/xml/ns/public/model/approval/outcome#approve" } } ]'
}

Describe 'Case cmdlets' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute '^POST resources/search\?options=noFetch$' (New-TestResponse -Json (Get-TestSearchJson -Objects "{ `"oid`": `"$ResourceOid`", `"name`": `"Test Resource`" }"))
        Add-TestRoute '^POST cases/search\?options=resolveNames$' (New-TestResponse -Json (Get-TestSearchJson -Objects @(
                    (Get-CaseJson -Oid $CaseOid -Account 'jack' -WorkItems $openItems),
                    (Get-CaseJson -Oid $ClosedOid -Account 'jack2' -State 'closed' -WorkItems $closedItems -Outcome 'http://midpoint.evolveum.com/xml/ns/public/model/approval/outcome#approve')
                )))
        Add-TestRoute "^GET cases/$CaseOid" (New-TestResponse -Json "{ `"case`": $(Get-CaseJson -Oid $CaseOid -Account 'jack' -WorkItems $openItems) }")
        Add-TestRoute "^GET cases/$ClosedOid" (New-TestResponse -Json "{ `"case`": $(Get-CaseJson -Oid $ClosedOid -Account 'jack2' -State 'closed' -WorkItems $closedItems) }")
        Add-TestRoute "^POST cases/$CaseOid/workItems/4/complete$" (New-TestResponse -StatusCode 204)
        Add-TestRoute "^DELETE cases/$CaseOid$" (New-TestResponse -StatusCode 204)
    }

    Context 'Get-midPointCase' {
        It 'searches the cases of a resource by its OID' {
            $c = @(Get-midPointCase -Resource 'Test Resource')
            $c.Count | Should -Be 2
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
                $Uri -like '*cases/search*' -and ($Body | ConvertFrom-Json).query.filter.text -eq "objectRef matches (oid = `"$ResourceOid`")"
            }
        }

        It 'returns names, references and work items' {
            $c = @(Get-midPointCase -Resource 'Test Resource')[0]
            $c.PSObject.TypeNames | Should -Contain 'midPointTools.Case'
            $c.Name | Should -Be "Request to add 'jack' on 'Test Resource'"
            $c.State | Should -Be 'open'
            $c.Object | Should -Be 'Test Resource'
            $c.Target | Should -Be 'jack'
            $c.OpenWorkItems | Should -Be 1
            $c.WorkItem[0].Id | Should -Be 4
            $c.WorkItem[0].Assignee | Should -Be 'tester'
        }

        It 'filters open cases and one account' {
            @(Get-midPointCase -Resource 'Test Resource' -State Open).Oid | Should -Be @($CaseOid)
            @(Get-midPointCase -Resource 'Test Resource' -Account 'jack2').Oid | Should -Be @($ClosedOid)
            @(Get-midPointCase -Resource 'Test Resource' -Account 'jac').Count | Should -Be 0
        }

        It 'asks midPoint for closed cases only with -State Closed' {
            $null = Get-midPointCase -Resource 'Test Resource' -State Closed -Filter 'name startsWith "Request"'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
                ($Body | ConvertFrom-Json).query.filter.text -eq "objectRef matches (oid = `"$ResourceOid`") and state = `"closed`" and (name startsWith `"Request`")"
            }
        }

        It 'reads the outcome of a closed case' {
            (Get-midPointCase -Oid $ClosedOid).WorkItem[0].Outcome | Should -Be 'approve'
            @(Get-midPointCase -Resource 'Test Resource')[1].Outcome | Should -Be 'approve'
        }
    }

    Context 'Complete-midPointCase' {
        It 'completes the open work item with outcome approve' {
            Get-midPointCase -Oid $CaseOid | Complete-midPointCase -Comment 'done'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like "*cases/$CaseOid/workItems/4/complete" -and
                ($Body | ConvertFrom-Json).output.outcome -eq 'http://midpoint.evolveum.com/xml/ns/public/model/approval/outcome#approve' -and
                ($Body | ConvertFrom-Json).output.comment -eq 'done'
            }
        }

        It 'sends reject for -Outcome Failure' {
            Complete-midPointCase $CaseOid -Outcome Failure
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
                $Method -eq 'POST' -and ($Body | ConvertFrom-Json).output.outcome -like '*#reject'
            }
        }

        It 'warns when nothing is open' {
            Complete-midPointCase $ClosedOid -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -BeLike '*no open work item*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Uri -like '*/complete' }
        }

        It 'sends nothing with -WhatIf' {
            Complete-midPointCase $CaseOid -WhatIf
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Uri -like '*/complete' }
        }
    }

    Context 'Remove-midPointCase' {
        It 'deletes piped cases' {
            Get-midPointCase -Resource 'Test Resource' -State Open | Remove-midPointCase -Confirm:$false
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like "*cases/$CaseOid" }
        }
    }
}
