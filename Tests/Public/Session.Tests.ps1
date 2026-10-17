BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule
    $script:cred = [pscredential]::new('tester', (ConvertTo-SecureString 'not-a-secret' -AsPlainText -Force))
}

Describe 'ConvertTo-midPointBaseUri' {
    It 'turns <In> into <Out>' -ForEach @(
        @{ In = 'https://midpoint.example.com/midpoint'; Out = 'https://midpoint.example.com/midpoint/ws/rest' }
        @{ In = 'https://midpoint.example.com/midpoint/'; Out = 'https://midpoint.example.com/midpoint/ws/rest' }
        @{ In = 'https://midpoint.example.com/midpoint/ws/rest/'; Out = 'https://midpoint.example.com/midpoint/ws/rest' }
        @{ In = 'https://midpoint.example.com:8443/midpoint?x=1'; Out = 'https://midpoint.example.com:8443/midpoint/ws/rest' }
    ) {
        InModuleScope midPointTools -Parameters @{ In = $In } { ConvertTo-midPointBaseUri -Uri $In } | Should -Be $Out
    }

    It 'rejects a relative URL' {
        { InModuleScope midPointTools { ConvertTo-midPointBaseUri -Uri 'midpoint/ws/rest' } } | Should -Throw '*absolute*'
    }
}

Describe 'Connect-midPoint' {
    BeforeEach {
        Clear-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
    }

    It 'checks the login with GET /self and stores the session' {
        Add-TestRoute '^GET self$' (New-TestResponse -Json (Get-TestUserJson -Oid '00000000-0000-0000-0000-000000000002' -Name 'tester'))

        $session = Connect-midPoint -Uri 'https://midpoint.example.com/midpoint' -Credential $cred -PassThru

        $session.Uri | Should -Be 'https://midpoint.example.com/midpoint/ws/rest'
        $session.UserName | Should -Be 'tester'
        $session.UserOid | Should -Be '00000000-0000-0000-0000-000000000002'
        $session.AuthType | Should -Be 'Basic'
        $session.PSObject.Properties.Name | Should -Not -Contain 'Credential'

        $expected = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('tester:not-a-secret'))
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'https://midpoint.example.com/midpoint/ws/rest/self' -and
            $Headers.Authorization -eq $expected -and $Headers.Accept -eq 'application/json'
        }
    }

    It 'passes -SkipCertificateCheck to every request' {
        Add-TestRoute '^GET self$' (New-TestResponse -Json (Get-TestUserJson))
        Connect-midPoint -Uri 'https://midpoint.example.com/midpoint' -Credential $cred -SkipCertificateCheck
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $SkipCertificateCheck -eq $true }
        (Get-midPointSession).SkipCertificateCheck | Should -BeTrue
    }

    It 'passes -TimeoutSec to every request' {
        Add-TestRoute '^GET self$' (New-TestResponse -Json (Get-TestUserJson))
        Connect-midPoint -Uri 'https://midpoint.example.com/midpoint' -Credential $cred -TimeoutSec 15
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $TimeoutSec -eq 15 }
        (Get-midPointSession).TimeoutSec | Should -Be 15
    }

    It 'keeps the previous session when the login fails' {
        Set-TestSession
        Add-TestRoute '^GET self$' (New-TestResponse -StatusCode 401 -Json '{ "message": "Authentication failed" }')

        { Connect-midPoint -Uri 'https://other.example.com/midpoint' -Credential $cred } | Should -Throw '*401*Authentication failed*'
        (Get-midPointSession).Uri | Should -Be 'https://midpoint.example.com/midpoint/ws/rest'
    }

    It 'warns about http' {
        Add-TestRoute '^GET self$' (New-TestResponse -Json (Get-TestUserJson))
        Mock Invoke-midPointHttp -ModuleName midPointTools { New-TestResponse -Json (Get-TestUserJson) }
        Connect-midPoint -Uri 'http://localhost:8080/midpoint' -Credential $cred -WarningVariable w -WarningAction SilentlyContinue
        $w | Should -Match 'clear text'
    }
}

Describe 'Get-midPointSession / Disconnect-midPoint' {
    It 'returns nothing without a session' {
        Clear-TestSession
        Get-midPointSession | Should -BeNullOrEmpty
    }

    It 'other cmdlets ask for Connect-midPoint first' {
        Clear-TestSession
        { Get-midPointUser -Oid $UserOid } | Should -Throw '*Connect-midPoint*'
    }

    It 'Disconnect-midPoint removes the session' {
        Set-TestSession
        Disconnect-midPoint
        Get-midPointSession | Should -BeNullOrEmpty
    }
}
