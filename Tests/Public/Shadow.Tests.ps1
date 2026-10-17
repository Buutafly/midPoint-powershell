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
        Add-TestRoute '^POST resources/search$' (New-TestResponse -Json (Get-TestSearchJson -Objects "{ `"oid`": `"$ResourceOid`", `"name`": `"Test Resource`" }"))
    }

    Context 'Get-midPointShadow' {
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
}
