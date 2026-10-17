BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule
}

Describe 'User cmdlets' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        $script:searchJack = Get-TestSearchJson -Objects "{ `"@type`": `"c:UserType`", `"oid`": `"$UserOid`", `"name`": `"jack`", `"emailAddress`": `"jack@example.com`" }"
    }

    Context 'Get-midPointUser' {
        It 'searches by exact name' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json $searchJack)

            $u = Get-midPointUser jack

            $u.Oid | Should -Be $UserOid
            $u.Name | Should -Be 'jack'
            $u.PSObject.TypeNames | Should -Contain 'midPointTools.User'
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
                ($Body | ConvertFrom-Json).query.filter.text -eq 'name = "jack"'
            }
        }

        It 'returns nothing when the name does not exist' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json (Get-TestSearchJson))
            Get-midPointUser nobody | Should -BeNullOrEmpty
        }

        It 'gets by OID with resolveNames' {
            Add-TestRoute "^GET users/$UserOid\?options=resolveNames$" (New-TestResponse -Json (Get-TestUserJson))
            $u = Get-midPointUser -Oid $UserOid -ResolveNames
            $u.FullName | Should -Be 'Jack Sparrow'
            $u.EffectiveStatus | Should -Be 'enabled'
        }

        It 'passes -Filter and -MaxResults' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json $searchJack)
            $null = Get-midPointUser -Filter 'name startsWith "MPTEST-"' -MaxResults 10
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
                $q = ($Body | ConvertFrom-Json).query
                $q.filter.text -eq 'name startsWith "MPTEST-"' -and $q.paging.maxSize -eq 10
            }
        }

        It 'lists all users with -All (no filter)' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json $searchJack)
            $null = Get-midPointUser -All
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
                $null -eq ($Body | ConvertFrom-Json).query.filter
            }
        }
    }

    Context 'New-midPointUser' {
        It 'creates the user with nested properties, activation and password' {
            Add-TestRoute '^POST users$' (New-TestResponse -StatusCode 201 -Headers @{ Location = @("https://midpoint.example.com/midpoint/ws/rest/users/$UserOid") })
            Add-TestRoute "^GET users/$UserOid$" (New-TestResponse -Json (Get-TestUserJson))

            $u = New-midPointUser -Name jack -GivenName Jack -EmailAddress jack@example.com `
                -Property @{ 'extension/costCenter' = '4711'; telephoneNumber = '+41 00 000 00 00' } `
                -AdministrativeStatus Enabled -ValidTo ([datetime]::new(2026, 12, 31, 0, 0, 0, [System.DateTimeKind]::Utc)) `
                -Password (ConvertTo-SecureString 'Initial-1' -AsPlainText -Force) -PassThru

            $u.Oid | Should -Be $UserOid
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                if ($Method -ne 'POST') { return $false }
                $b = ($Body | ConvertFrom-Json -AsHashtable).user
                $b.name -eq 'jack' -and $b.givenName -eq 'Jack' -and $b.emailAddress -eq 'jack@example.com' -and
                $b.extension.costCenter -eq '4711' -and $b.telephoneNumber -eq '+41 00 000 00 00' -and
                $b.activation.administrativeStatus -eq 'enabled' -and
                $Body -like '*"validTo":"2026-12-31T00:00:00.000+00:00"*' -and
                $b.credentials.password.value.clearValue -eq 'Initial-1' -and
                -not $b.Contains('familyName')
            }
        }

        It 'returns nothing without -PassThru' {
            Add-TestRoute '^POST users$' (New-TestResponse -StatusCode 201 -Headers @{ Location = @("https://midpoint.example.com/midpoint/ws/rest/users/$UserOid") })
            New-midPointUser -Name jack | Should -BeNullOrEmpty
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly
        }

        It 'sends nothing with -WhatIf' {
            New-midPointUser -Name jack -WhatIf
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly
        }
    }

    Context 'Set-midPointUser' {
        It 'builds replace / add / delete deltas in one PATCH' {
            Add-TestRoute "^PATCH users/$UserOid$" (New-TestResponse -StatusCode 204)

            Set-midPointUser $UserOid -EmailAddress 'new@example.com' -Description '' `
                -Replace @{ telephoneNumber = '1' } -Add @{ organizationalUnit = 'Sales' } -Remove @{ organization = 'Old' }

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
                $d = @(($Body | ConvertFrom-Json).objectModification.itemDelta)
                $mail = $d | Where-Object path -EQ 'emailAddress'
                $desc = $d | Where-Object path -EQ 'description'
                $d.Count -eq 5 -and
                $mail.modificationType -eq 'replace' -and $mail.value -eq 'new@example.com' -and
                $desc.modificationType -eq 'replace' -and $null -eq $desc.PSObject.Properties['value'] -and
                ($d | Where-Object path -EQ 'organizationalUnit').modificationType -eq 'add' -and
                ($d | Where-Object path -EQ 'organization').modificationType -eq 'delete'
            }
        }

        It 'resolves a user name to the OID' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json $searchJack)
            Add-TestRoute "^PATCH users/$UserOid$" (New-TestResponse -StatusCode 204)
            Set-midPointUser jack -GivenName Jack
            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $Method -eq 'PATCH' }
        }

        It 'fails when the name matches more than one user' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json (Get-TestSearchJson -Objects '{ "oid": "a", "name": "jack" }', '{ "oid": "b", "name": "jack" }'))
            { Set-midPointUser jack -GivenName Jack } | Should -Throw '*more than one*'
        }

        It 'fails when the name does not exist' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json (Get-TestSearchJson))
            { Set-midPointUser nobody -GivenName X } | Should -Throw '*nobody*'
        }

        It 'fails when nothing is to change' {
            { Set-midPointUser $UserOid } | Should -Throw '*Nothing to change*'
        }
    }

    Context 'Remove-midPointUser' {
        It 'deletes piped users' {
            Add-TestRoute '^POST users/search$' (New-TestResponse -Json $searchJack)
            Add-TestRoute "^DELETE users/$UserOid$" (New-TestResponse -StatusCode 204)

            Get-midPointUser jack | Remove-midPointUser -Confirm:$false

            Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        }
    }
}
