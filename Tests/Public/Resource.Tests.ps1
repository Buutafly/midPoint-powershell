BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    $script:ConnectorOid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:resourceJson = "{ `"oid`": `"$ResourceOid`", `"name`": `"Test Resource`", `"connectorRef`": { `"oid`": `"$ConnectorOid`", `"type`": `"c:ConnectorType`" } }"
}

Describe 'Get-midPointResource' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute '^POST resources/search\?options=noFetch$' (New-TestResponse -Json (Get-TestSearchJson -Objects $resourceJson))
        Add-TestRoute "^GET resources/$ResourceOid\?options=noFetch$" (New-TestResponse -Json "{ `"resource`": $resourceJson }")
        Add-TestRoute "^GET connectors/$ConnectorOid$" (New-TestResponse -Json "{ `"connector`": { `"oid`": `"$ConnectorOid`", `"connectorType`": `"ManualConnector`" } }")
    }

    It 'finds a resource by name without contacting the connector and reads the connector type' {
        $r = Get-midPointResource 'Test Resource'
        $r.Oid | Should -Be $ResourceOid
        $r.ConnectorType | Should -Be 'ManualConnector'
        $r.IsManual | Should -BeTrue
        $r.PSObject.TypeNames | Should -Contain 'midPointTools.Resource'
    }

    It 'gets a resource by OID with noFetch' {
        (Get-midPointResource -Oid $ResourceOid).Name | Should -Be 'Test Resource'
    }

    It 'reads the connector OID of a reference with a filter (prefixed keys, as midPoint 4.10 sends it)' {
        $json = "{ `"oid`": `"$ResourceOid`", `"name`": `"Test Resource`", `"connectorRef`": { `"t:oid`": `"$ConnectorOid`", `"t:relation`": `"org:default`", `"t:type`": `"c:ConnectorType`", `"filter`": { `"@ns`": `"http://prism.evolveum.com/xml/ns/public/query-3`", `"text`": `"connectorType = \`"ManualConnector\`"`" } } }"
        Add-TestRoute '^POST resources/search\?options=noFetch$' (New-TestResponse -Json (Get-TestSearchJson -Objects $json))
        $r = Get-midPointResource 'Test Resource'
        $r.ConnectorOid | Should -Be $ConnectorOid
        $r.IsManual | Should -BeTrue
    }

    It 'leaves the connector type empty when the connector is not readable' {
        Add-TestRoute "^GET connectors/$ConnectorOid$" (New-TestResponse -StatusCode 403 -Json '{ "message": "Not authorized" }')
        $r = Get-midPointResource 'Test Resource'
        $r.ConnectorType | Should -BeNullOrEmpty
        $r.IsManual | Should -BeFalse
    }

    It 'returns nothing for an unknown name' {
        Add-TestRoute '^POST resources/search\?options=noFetch$' (New-TestResponse -Json (Get-TestSearchJson))
        Get-midPointResource 'Nope' | Should -BeNullOrEmpty
    }
}
