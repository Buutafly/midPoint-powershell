BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    $script:deadOid = '66666666-6666-6666-6666-666666666666'
    $script:links = "[ { `"oid`": `"$ShadowOid`", `"type`": `"c:ShadowType`" }, { `"oid`": `"$OtherOid`", `"type`": `"c:ShadowType`" }, { `"oid`": `"$deadOid`", `"type`": `"c:ShadowType`" } ]"

    function Get-ShadowJson {
        param([string] $Oid, [string] $ResourceOid, [string] $Mail = 'jack@example.com', [string] $Extra = '')
        @"
{ "shadow": {
    "oid": "$Oid", "name": "jack",
    "resourceRef": { "oid": "$ResourceOid", "type": "c:ResourceType", "targetName": "Test Resource" },
    "objectClass": "ri:AccountObjectClass", "kind": "account", "intent": "default",
    "synchronizationSituation": "linked",
    "attributes": { "ri:mail": [ "$Mail" ], "ri:memberOf": [ "a", "b" ] }
    $Extra
} }
"@
    }
}

Describe 'Shadow cmdlets' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Mock Start-Sleep -ModuleName midPointTools { }
        Add-TestRoute "^GET users/$UserOid$" (New-TestResponse -Json (Get-TestUserJson -LinkRefs $links))
        Add-TestRoute "^GET shadows/$ShadowOid\?" (New-TestResponse -Json (Get-ShadowJson -Oid $ShadowOid -ResourceOid $ResourceOid))
        Add-TestRoute "^GET shadows/$OtherOid\?" (New-TestResponse -Json (Get-ShadowJson -Oid $OtherOid -ResourceOid '77777777-7777-7777-7777-777777777777'))
        Add-TestRoute "^GET shadows/$deadOid\?" (New-TestResponse -Json (Get-ShadowJson -Oid $deadOid -ResourceOid $ResourceOid -Extra ', "dead": true, "exists": false'))
        Add-TestRoute '^POST resources/search\?options=noFetch$' (New-TestResponse -Json (Get-TestSearchJson -Objects "{ `"oid`": `"$ResourceOid`", `"name`": `"Test Resource`" }"))
    }

    Context 'Get-midPointShadow' {
        It 'looks up the resource name with noFetch' {
            $null = Get-midPointShadow $UserOid -Resource 'Test Resource'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $Uri -like '*resources/search?options=noFetch' }
        }

        It 'returns the live accounts on the resource with flattened attributes' {
            $s = @(Get-midPointShadow $UserOid -Resource 'Test Resource')
            $s.Count | Should -Be 1
            $s[0].Oid | Should -Be $ShadowOid
            $s[0].Resource | Should -Be 'Test Resource'
            $s[0].ObjectClass | Should -Be 'AccountObjectClass'
            $s[0].Attributes.mail | Should -Be 'jack@example.com'
            @($s[0].Attributes.memberOf) | Should -Be @('a', 'b')
            $s[0].PSObject.TypeNames | Should -Contain 'midPointTools.Shadow'
        }

        It 'returns all live shadows without -Resource and dead ones with -IncludeDead' {
            @(Get-midPointShadow $UserOid).Count | Should -Be 2
            @(Get-midPointShadow $UserOid -IncludeDead).Count | Should -Be 3
        }

        It 'sends noFetch with -NoFetch' {
            $null = Get-midPointShadow $UserOid -NoFetch
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $Uri -like '*shadows/*options=resolveNames&options=noFetch' }
        }

        It 'skips links to shadows that no longer exist' {
            Add-TestRoute "^GET shadows/$OtherOid\?" (New-TestResponse -StatusCode 404 -Json '{ "message": "not found" }')
            @(Get-midPointShadow $UserOid).Oid | Should -Be @($ShadowOid)
        }
    }

    Context 'Pending accounts (manual resource)' {
        BeforeEach {
            $pendingJson = @"
{ "shadow": {
    "oid": "$ShadowOid", "name": "jack", "exists": false,
    "resourceRef": { "oid": "$ResourceOid", "type": "c:ResourceType", "targetName": "Test Resource" },
    "kind": "account", "intent": "default",
    "pendingOperation": [ { "executionStatus": "executing", "type": "manual",
        "delta": { "changeType": "add", "objectToAdd": { "attributes": { "ri:mail": [ "jack@example.com" ] } } } } ]
} }
"@
            Add-TestRoute "^GET shadows/$ShadowOid\?" (New-TestResponse -Json $pendingJson)
        }

        It 'reports the pending add and the requested attributes' {
            $s = @(Get-midPointShadow $UserOid -Resource $ResourceOid)
            $s.Count | Should -Be 1
            $s[0].Exists | Should -BeFalse
            $s[0].IsPending | Should -BeTrue
            $s[0].PendingOperation | Should -Be 'add'
            $s[0].Attributes.mail | Should -Be 'jack@example.com'
        }

        It 'Test-midPointShadow counts it only with -AllowPending' {
            Test-midPointShadow $UserOid -Resource $ResourceOid | Should -BeFalse
            Test-midPointShadow $UserOid -Resource $ResourceOid -AllowPending | Should -BeTrue
        }

        It 'Wait-midPointShadow accepts it with -AllowPending' {
            (Wait-midPointShadow $UserOid -Resource $ResourceOid -AllowPending -Attribute @{ mail = 'jack@example.com' }).IsPending | Should -BeTrue
        }

        It 'Wait-midPointShadow explains the timeout without -AllowPending' {
            { Wait-midPointShadow $UserOid -Resource $ResourceOid -TimeoutSeconds 1 -IntervalSeconds 1 } |
                Should -Throw '*only requested (pending add)*-AllowPending*'
        }
    }

    Context 'Test-midPointShadow' {
        It 'is true when the account exists' {
            Test-midPointShadow $UserOid -Resource $ResourceOid | Should -BeTrue
        }

        It 'is false when there is no account on the resource' {
            Test-midPointShadow $UserOid -Resource '88888888-8888-8888-8888-888888888888' | Should -BeFalse
        }
    }

    Context 'Wait-midPointShadow' {
        It 'polls until the attribute has the expected value' {
            Add-TestRoute "^GET shadows/$ShadowOid\?" @(
                (New-TestResponse -Json (Get-ShadowJson -Oid $ShadowOid -ResourceOid $ResourceOid -Mail 'old@example.com'))
                (New-TestResponse -Json (Get-ShadowJson -Oid $ShadowOid -ResourceOid $ResourceOid -Mail 'JACK@example.com'))
            )

            $s = Wait-midPointShadow $UserOid -Resource $ResourceOid -Attribute @{ mail = 'jack@example.com'; memberOf = 'b' } -IntervalSeconds 1

            $s.Oid | Should -Be $ShadowOid
            Should -Invoke Start-Sleep -ModuleName midPointTools -Times 1 -Exactly
        }

        It 'shows progress while waiting' {
            Mock Write-Progress -ModuleName midPointTools { }
            Add-TestRoute "^GET shadows/$ShadowOid\?" @(
                (New-TestResponse -Json (Get-ShadowJson -Oid $ShadowOid -ResourceOid $ResourceOid -Mail 'old@example.com'))
                (New-TestResponse -Json (Get-ShadowJson -Oid $ShadowOid -ResourceOid $ResourceOid))
            )
            $null = Wait-midPointShadow $UserOid -Resource $ResourceOid -Attribute @{ mail = 'jack@example.com' } -IntervalSeconds 1
            Should -Invoke Write-Progress -ModuleName midPointTools -ParameterFilter { $Status -like '*mail is*old@example.com*' }
            Should -Invoke Write-Progress -ModuleName midPointTools -ParameterFilter { $Completed }
        }

        It 'returns at once when no attributes are given' {
            (Wait-midPointShadow $UserOid -Resource $ResourceOid).Oid | Should -Be $ShadowOid
            Should -Invoke Start-Sleep -ModuleName midPointTools -Times 0 -Exactly
        }

        It 'times out with the last state' {
            { Wait-midPointShadow $UserOid -Resource $ResourceOid -Attribute @{ mail = 'other@example.com' } -TimeoutSeconds 1 -IntervalSeconds 1 } |
                Should -Throw '*Timeout*mail is*jack@example.com*expected*other@example.com*'
        }

        It 'can wait for an attribute to be empty' {
            { Wait-midPointShadow $UserOid -Resource $ResourceOid -Attribute @{ mail = $null } -TimeoutSeconds 1 -IntervalSeconds 1 } |
                Should -Throw '*Timeout*'
            (Wait-midPointShadow $UserOid -Resource $ResourceOid -Attribute @{ telephoneNumber = $null }).Oid | Should -Be $ShadowOid
        }
    }

    Context 'Remove-midPointShadow' {
        It 'reads the shadow with noFetch and deletes it' {
            Add-TestRoute "^DELETE shadows/$ShadowOid$" (New-TestResponse -StatusCode 204)

            Remove-midPointShadow $ShadowOid -Confirm:$false

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like "*shadows/${ShadowOid}?options=noFetch&options=resolveNames"
            }
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -like "*/shadows/$ShadowOid"
            }
        }

        It 'deletes the shadows piped from Get-midPointShadow' {
            Add-TestRoute '^DELETE shadows/' (New-TestResponse -StatusCode 204)

            Get-midPointShadow $UserOid -NoFetch | Remove-midPointShadow -Confirm:$false

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like "*/shadows/$ShadowOid" }
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -like "*/shadows/$OtherOid" }
        }

        It 'refuses a user object piped by mistake and sends nothing' {
            $user = & (Get-Module midPointTools) { param($j) $j | ConvertFrom-Json | ForEach-Object user | ConvertTo-midPointUserObject } (Get-TestUserJson)

            { $user | Remove-midPointShadow -Confirm:$false } | Should -Throw '*midPointTools.User object is not a shadow*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly
        }

        It 'refuses a name' {
            { Remove-midPointShadow 'jack' -Confirm:$false } | Should -Throw "*'jack' is not an OID*"
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly
        }

        It 'refuses an OID that is not a shadow' {
            Add-TestRoute "^GET shadows/$UserOid\?" (New-TestResponse -Json (Get-TestUserJson))
            { Remove-midPointShadow $UserOid -Confirm:$false } | Should -Throw '*not a shadow*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        }

        It 'warns when the shadow no longer exists (404 on GET)' {
            Add-TestRoute "^GET shadows/$ShadowOid\?" (New-TestResponse -StatusCode 404 -Json '{ "message": "Object not found" }')

            Remove-midPointShadow $ShadowOid -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue

            "$w" | Should -BeLike '*no longer exists*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        }

        It 'warns and sends nothing for a dead shadow' {
            Remove-midPointShadow $deadOid -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue
            "$w" | Should -BeLike '*already deleted*'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        }

        It 'warns when the shadow is gone by the time of the delete (404 on DELETE)' {
            Add-TestRoute "^DELETE shadows/$ShadowOid$" (New-TestResponse -StatusCode 404 -Json '{ "message": "Object not found" }')
            Remove-midPointShadow $ShadowOid -Confirm:$false -WarningVariable w -WarningAction SilentlyContinue
            "$w" | Should -BeLike '*no longer exists*'
        }

        It 'stops with the status code when midPoint refuses the delete (409, assignment policy)' {
            Add-TestRoute "^DELETE shadows/$ShadowOid$" (New-TestResponse -StatusCode 409 -Json '{ "message": "Attempt to delete shadow while it is assigned violates an assignment policy" }')

            $err = $null
            try { Remove-midPointShadow $ShadowOid -Confirm:$false } catch { $err = $_ }

            $err.Exception.Data['StatusCode'] | Should -Be 409
            $err.Exception.Message | Should -BeLike '*assignment policy*'
        }

        It 'sends nothing with -WhatIf and names the account and resource' {
            Remove-midPointShadow $ShadowOid -WhatIf
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        }
    }
}
