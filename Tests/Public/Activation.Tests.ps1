BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule

    function Get-SentDelta {
        param([string] $Body)
        @(($Body | ConvertFrom-Json).objectModification.itemDelta)
    }
}

Describe 'Activation cmdlets' {
    BeforeEach {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute "^PATCH users/$UserOid$" (New-TestResponse -StatusCode 204)
        Add-TestRoute "^GET users/$UserOid$" (New-TestResponse -Json (Get-TestUserJson))
    }

    It 'Disable-midPointUser replaces administrativeStatus with disabled' {
        Disable-midPointUser $UserOid
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            $d = Get-SentDelta $Body
            $Method -eq 'PATCH' -and $d.Count -eq 1 -and
            $d[0].modificationType -eq 'replace' -and $d[0].path -eq 'activation/administrativeStatus' -and $d[0].value -eq 'disabled'
        }
    }

    It 'Enable-midPointUser sets status and validTo in the same PATCH' {
        Enable-midPointUser $UserOid -ValidTo ([datetime]::new(2027, 1, 31, 0, 0, 0, [System.DateTimeKind]::Utc))
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            ($d | Where-Object path -EQ 'activation/administrativeStatus').value -eq 'enabled' -and
            $Body -like '*"path":"activation/validTo","value":"2027-01-31T00:00:00.000+00:00"*'
        }
    }

    It 'Enable-midPointUser warns when the user stays effectively disabled' {
        Add-TestRoute "^GET users/$UserOid$" (New-TestResponse -Json (Get-TestUserJson -Activation '{ "administrativeStatus": "enabled", "effectiveStatus": "disabled", "validityStatus": "after", "validTo": "2020-01-01T00:00:00.000Z" }'))
        Enable-midPointUser $UserOid -WarningVariable w -WarningAction SilentlyContinue
        $w | Should -Match "effective status is 'disabled'.*after"
    }

    It 'Set-midPointUserActivation -AdministrativeStatus None clears the status and -ClearValidTo clears validTo' {
        Set-midPointUserActivation $UserOid -AdministrativeStatus None -ClearValidTo -ValidFrom ([datetime]::new(2026, 11, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            if ($Method -ne 'PATCH') { return $false }
            $d = Get-SentDelta $Body
            $status = $d | Where-Object path -EQ 'activation/administrativeStatus'
            $to = $d | Where-Object path -EQ 'activation/validTo'
            $d.Count -eq 3 -and
            $null -eq $status.PSObject.Properties['value'] -and $null -eq $to.PSObject.Properties['value'] -and
            $Body -like '*"path":"activation/validFrom","value":"2026-11-01T00:00:00.000+00:00"*'
        }
    }

    It 'Set-midPointUserActivation rejects -ValidTo together with -ClearValidTo' {
        { Set-midPointUserActivation $UserOid -ValidTo (Get-Date) -ClearValidTo } | Should -Throw '*either*'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly
    }

    It 'Set-midPointUserActivation needs at least one change' {
        { Set-midPointUserActivation $UserOid } | Should -Throw '*Nothing to change*'
    }

    It 'Get-midPointUserActivation returns status, validity and the read-only fields' {
        Add-TestRoute "^GET users/$UserOid$" (New-TestResponse -Json (Get-TestUserJson -Activation '{ "administrativeStatus": "disabled", "effectiveStatus": "disabled", "validityStatus": "inside", "disableReason": "http://midpoint.evolveum.com/xml/ns/public/model/disableReason#explicit", "disableTimestamp": "2026-10-01T08:00:00.000Z", "lockoutStatus": "normal" }'))
        $a = Get-midPointUserActivation $UserOid
        $a.AdministrativeStatus | Should -Be 'disabled'
        $a.DisableReason | Should -Be 'explicit'
        $a.DisableTimestamp | Should -BeOfType [datetime]
        $a.LockoutStatus | Should -Be 'normal'
        $a.PSObject.TypeNames | Should -Contain 'midPointTools.Activation'
    }

    It 'Unlock-midPointUser sets lockoutStatus to normal' {
        Unlock-midPointUser $UserOid
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter {
            $d = Get-SentDelta $Body
            $d[0].path -eq 'activation/lockoutStatus' -and $d[0].value -eq 'normal'
        }
    }
}
