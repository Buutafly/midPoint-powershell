BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule
}

Describe 'Invoke-midPointRestMethod' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
    }

    It 'sends repeated query parameters and escapes values' {
        Add-TestRoute '^GET users/' (New-TestResponse -Json (Get-TestUserJson))
        InModuleScope midPointTools {
            $null = Invoke-midPointRestMethod -Method GET -Path 'users/a b' -Query ([ordered]@{ options = @('raw', 'resolveNames'); x = 'a&b' })
        }
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
            $Uri -eq 'https://midpoint.example.com/midpoint/ws/rest/users/a b?options=raw&options=resolveNames&x=a%26b'
        }
    }

    It 'serializes the body as JSON' {
        Add-TestRoute '^POST users$' (New-TestResponse -StatusCode 201)
        InModuleScope midPointTools {
            $null = Invoke-midPointRestMethod -Method POST -Path 'users' -Body ([ordered]@{ user = [ordered]@{ name = 'jäck' } })
        }
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $Body -eq '{"user":{"name":"jäck"}}' }
    }

    It 'turns HTTP <Status> into category <Category> with the midPoint message' -ForEach @(
        @{ Status = 400; Category = 'InvalidArgument' }
        @{ Status = 403; Category = 'PermissionDenied' }
        @{ Status = 404; Category = 'ObjectNotFound' }
        @{ Status = 409; Category = 'ResourceExists' }
        @{ Status = 500; Category = 'InvalidOperation' }
    ) {
        Add-TestRoute '^GET users/x$' (New-TestResponse -StatusCode $Status -Json '{ "object": { "@type": "c:OperationResultType", "status": "fatal_error", "partialResults": [ { "message": "Object not found: x" } ] } }')
        $err = $null
        try { InModuleScope midPointTools { Invoke-midPointRestMethod -Method GET -Path 'users/x' } } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.CategoryInfo.Category | Should -Be $Category
        $err.Exception.Message | Should -BeLike "*HTTP $Status*Object not found: x*"
        $err.Exception.Data['StatusCode'] | Should -Be $Status
    }

    It 'warns on 250 partial error' {
        Add-TestRoute '^PATCH users/x$' (New-TestResponse -StatusCode 250 -Json '{ "object": { "message": "Resource down" } }')
        InModuleScope midPointTools {
            $null = Invoke-midPointRestMethod -Method PATCH -Path 'users/x' -Body @{} -WarningVariable w -WarningAction SilentlyContinue
            $w | Should -Match 'partial error.*Resource down'
        }
    }

    It 'reports connection failures as ConnectionError' {
        Mock Invoke-midPointHttp -ModuleName midPointTools { throw [System.Net.Http.HttpRequestException]::new('No such host') }
        $err = $null
        try { InModuleScope midPointTools { Invoke-midPointRestMethod -Method GET -Path 'self' } } catch { $err = $_ }
        $err.CategoryInfo.Category | Should -Be 'ConnectionError'
        $err.Exception.Message | Should -BeLike '*No such host*'
    }
}

Describe 'Get-midPointObjectFromResponse' {
    It 'unwraps a single object' {
        InModuleScope midPointTools -Parameters @{ Json = (Get-TestUserJson) } {
            (Get-midPointObjectFromResponse -Body ($Json | ConvertFrom-Json)).name | Should -Be 'jack'
        }
    }

    It 'unwraps a search result' {
        $json = Get-TestSearchJson -Objects '{ "@type": "c:UserType", "oid": "a", "name": "a" }', '{ "@type": "c:UserType", "oid": "b", "name": "b" }'
        InModuleScope midPointTools -Parameters @{ Json = $json } {
            @(Get-midPointObjectFromResponse -Body ($Json | ConvertFrom-Json)).oid | Should -Be @('a', 'b')
        }
    }

    It 'returns nothing for an empty search result' {
        $json = Get-TestSearchJson
        InModuleScope midPointTools -Parameters @{ Json = $json } {
            @(Get-midPointObjectFromResponse -Body ($Json | ConvertFrom-Json)).Count | Should -Be 0
        }
    }
}

Describe 'Value conversion' {
    It 'writes dates as ISO 8601 with offset' {
        InModuleScope midPointTools {
            $d = [datetime]::new(2026, 12, 31, 23, 59, 0, [System.DateTimeKind]::Utc)
            ConvertTo-midPointDateTime $d | Should -Be '2026-12-31T23:59:00.000+00:00'
        }
    }

    It 'escapes Axiom strings' {
        InModuleScope midPointTools {
            ConvertTo-midPointAxiomString 'a"b\c' | Should -Be '"a\"b\\c"'
        }
    }

    It 'reads PolyStrings in both forms' {
        InModuleScope midPointTools {
            ConvertFrom-midPointPolyString 'jack' | Should -Be 'jack'
            ConvertFrom-midPointPolyString ([pscustomobject]@{ orig = 'Jäck'; norm = 'jack' }) | Should -Be 'Jäck'
        }
    }
}

Describe 'Debug output' {
    It 'masks password values' {
        Set-TestSession
        Mock Invoke-midPointHttp -ModuleName midPointTools { New-TestResponse -StatusCode 201 }
        $out = InModuleScope midPointTools {
            $DebugPreference = 'Continue'
            Invoke-midPointRestMethod -Method POST -Path 'users' -Body @{ user = @{ credentials = @{ password = @{ value = @{ clearValue = 'Se"cret' } } } } } 5>&1 |
                Where-Object { $_ -is [System.Management.Automation.DebugRecord] }
        }
        "$out" | Should -Match '"clearValue":"\*\*\*"'
        "$out" | Should -Not -Match 'cret'
    }
}
