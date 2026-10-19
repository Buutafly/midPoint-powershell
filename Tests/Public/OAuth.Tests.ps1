BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'TestHelpers.ps1')
    Initialize-TestModule
    $script:secret = 'not-a-secret&+/='
    $script:client = [pscredential]::new('client-1', (ConvertTo-SecureString $secret -AsPlainText -Force))
    $script:midPointUri = 'https://midpoint.example.com/midpoint'
    $script:issuer = 'https://idp.example.com/realms/example'
    $script:tokenUrl = 'https://idp.example.com/realms/example/protocol/openid-connect/token'

    function ConvertTo-TestBase64Url([string] $Text) {
        [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }

    function New-TestJwt {
        # Unsigned JWT; the module reads claims only.
        param([hashtable] $Claims)
        '{0}.{1}.c2lnbmF0dXJl' -f (ConvertTo-TestBase64Url '{"alg":"RS256","typ":"JWT"}'), (ConvertTo-TestBase64Url ($Claims | ConvertTo-Json -Compress))
    }

    function Add-TestIdp {
        # Mocks the identity provider: discovery and a token endpoint that issues token-1, token-2, ...
        param([int] $ExpiresIn = 3600, [object] $TokenResponse)
        $script:tokenCount = 0
        $script:tokenBodies = [System.Collections.Generic.List[string]]::new()
        $script:tokenResponse = $TokenResponse
        $script:expiresIn = $ExpiresIn
        Mock Invoke-midPointTokenRequest -ModuleName midPointTools {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ issuer = $script:issuer; token_endpoint = $script:tokenUrl } }
            }
            $script:tokenBodies.Add($Body)
            if ($script:tokenResponse) { return $script:tokenResponse }
            $script:tokenCount++
            [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ access_token = "token-$script:tokenCount"; token_type = 'Bearer'; expires_in = $script:expiresIn } }
        }
    }
}

Describe 'Connect-midPoint with client credentials' {
    BeforeEach {
        Clear-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute '^GET self$' (New-TestResponse -Json (Get-TestUserJson -Oid '00000000-0000-0000-0000-000000000003' -Name 'svc-midpoint'))
    }

    It 'finds the token endpoint by discovery, gets a token and sends it as Bearer' {
        Add-TestIdp
        $session = Connect-midPoint -Uri $midPointUri -Issuer "$issuer/" -ClientCredential $client -Scope 'api://midpoint/.default', 'openid' -PassThru

        Should -Invoke Invoke-midPointTokenRequest -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -eq 'https://idp.example.com/realms/example/.well-known/openid-configuration'
        }
        Should -Invoke Invoke-midPointTokenRequest -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -eq $tokenUrl }
        $tokenBodies[0] | Should -Be 'grant_type=client_credentials&client_id=client-1&client_secret=not-a-secret%26%2B%2F%3D&scope=api%3A%2F%2Fmidpoint%2F.default%20openid'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://midpoint.example.com/midpoint/ws/rest/self' -and $Headers.Authorization -eq 'Bearer token-1'
        }

        $session.AuthType | Should -Be 'Bearer'
        $session.UserName | Should -Be 'svc-midpoint'
        $session.UserOid | Should -Be '00000000-0000-0000-0000-000000000003'
        $session.TokenExpiresAt | Should -BeGreaterThan (Get-Date).AddMinutes(59)
        $session.TokenExpiresAt | Should -BeLessThan (Get-Date).AddMinutes(61)
        $session.PSObject.Properties.Name | Should -Not -Contain 'AccessToken'
        $session.PSObject.Properties.Name | Should -Not -Contain 'TokenSource'
        $session.PSObject.Properties.Name | Should -Not -Contain 'Credential'
    }

    It 'uses -TokenEndpoint without discovery and without scope' {
        Add-TestIdp
        Connect-midPoint -Uri $midPointUri -TokenEndpoint $tokenUrl -ClientCredential $client
        Should -Invoke Invoke-midPointTokenRequest -ModuleName midPointTools -Times 0 -Exactly -ParameterFilter { $Method -eq 'GET' }
        $tokenBodies[0] | Should -Be 'grant_type=client_credentials&client_id=client-1&client_secret=not-a-secret%26%2B%2F%3D'
        (Get-midPointSession).AuthType | Should -Be 'Bearer'
    }

    It 'does not accept -Credential together with -Issuer' {
        $cred = [pscredential]::new('tester', (ConvertTo-SecureString 'x' -AsPlainText -Force))
        { Connect-midPoint -Uri $midPointUri -Credential $cred -Issuer $issuer -ClientCredential $client } | Should -Throw '*parameter set*'
    }

    It 'reads the expiry from the JWT when expires_in is missing' {
        $exp = [DateTimeOffset]::UtcNow.AddMinutes(30).ToUnixTimeSeconds()
        $jwt = New-TestJwt @{ sub = 'x'; exp = $exp }
        Add-TestIdp -TokenResponse ([pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ access_token = $jwt; token_type = 'Bearer' } })
        Connect-midPoint -Uri $midPointUri -TokenEndpoint $tokenUrl -ClientCredential $client
        (Get-midPointSession).TokenExpiresAt.ToUniversalTime() | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds($exp).UtcDateTime)
    }

    It 'shows the error of the identity provider and keeps the previous session' {
        Set-TestSession
        Add-TestIdp -TokenResponse ([pscustomobject]@{ StatusCode = 401; Body = [pscustomobject]@{ error = 'invalid_client'; error_description = 'Invalid client secret' } })
        $err = $null
        try { Connect-midPoint -Uri 'https://other.example.com/midpoint' -TokenEndpoint $tokenUrl -ClientCredential $client } catch { $err = $_ }
        $err.Exception.Message | Should -BeLike '*HTTP 401*invalid_client: Invalid client secret*'
        $err.Exception.Message | Should -Not -BeLike "*$secret*"
        $err.CategoryInfo.Category | Should -Be 'AuthenticationError'
        (Get-midPointSession).Uri | Should -Be 'https://midpoint.example.com/midpoint/ws/rest'
        (Get-midPointSession).AuthType | Should -Be 'Basic'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 0 -Exactly
    }

    It 'says so when discovery finds no token endpoint' {
        Mock Invoke-midPointTokenRequest -ModuleName midPointTools { [pscustomobject]@{ StatusCode = 404; Body = 'Not Found' } }
        { Connect-midPoint -Uri $midPointUri -Issuer $issuer -ClientCredential $client } | Should -Throw '*HTTP 404 without a token_endpoint*-TokenEndpoint*'
        Get-midPointSession | Should -BeNullOrEmpty
    }

    It 'reports an unreachable identity provider as ConnectionError' {
        Mock Invoke-midPointTokenRequest -ModuleName midPointTools { throw [System.Net.Http.HttpRequestException]::new('No such host') }
        $err = $null
        try { Connect-midPoint -Uri $midPointUri -TokenEndpoint $tokenUrl -ClientCredential $client } catch { $err = $_ }
        $err.CategoryInfo.Category | Should -Be 'ConnectionError'
        $err.Exception.Message | Should -BeLike "*$tokenUrl*No such host*"
    }

    It 'does not retry when midPoint rejects a token it just got, and explains the 401' {
        Add-TestIdp
        Add-TestRoute '^GET self$' (New-TestResponse -StatusCode 401 -Headers @{ 'WWW-Authenticate' = @('Bearer error="invalid_token"') })
        $err = $null
        try { Connect-midPoint -Uri $midPointUri -TokenEndpoint $tokenUrl -ClientCredential $client } catch { $err = $_ }
        $err.Exception.Message | Should -BeLike '*HTTP 401*access token rejected (Bearer error="invalid_token")*user name claim*'
        $err.CategoryInfo.Category | Should -Be 'AuthenticationError'
        $tokenCount | Should -Be 1
        Get-midPointSession | Should -BeNullOrEmpty
    }

    It 'warns about http for midPoint and for the identity provider' {
        Add-TestIdp
        Connect-midPoint -Uri 'http://localhost:8080/midpoint' -TokenEndpoint 'http://localhost:8180/token' -ClientCredential $client -WarningVariable w -WarningAction SilentlyContinue
        ($w -join "`n") | Should -Match 'access token is sent in clear text'
        ($w -join "`n") | Should -Match 'client secret is sent in clear text'
    }

    It 'never writes the secret or the token to Verbose or Debug' {
        Add-TestIdp
        $out = Connect-midPoint -Uri $midPointUri -Issuer $issuer -ClientCredential $client -Verbose -Debug 4>&1 5>&1 | Out-String
        $out | Should -Match 'Requesting an access token'
        $out | Should -Not -Match ([regex]::Escape($secret))
        $out | Should -Not -Match 'not-a-secret'
        $out | Should -Not -Match 'token-1'
    }
}

Describe 'Bearer session' {
    BeforeEach {
        Clear-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Add-TestRoute '^GET self$' (New-TestResponse -Json (Get-TestUserJson -Name 'svc-midpoint'))
        Add-TestIdp
        Connect-midPoint -Uri $midPointUri -TokenEndpoint $tokenUrl -ClientCredential $client
    }

    It 'renews the token when it expires within 60 s' {
        InModuleScope midPointTools { $script:midPointSession.TokenExpiresAt = [datetime]::UtcNow.AddSeconds(30) }
        Add-TestRoute '^GET users/' (New-TestResponse -Json (Get-TestUserJson))
        $null = Get-midPointUser -Oid $UserOid
        $tokenCount | Should -Be 2
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Uri -like '*/users/*' -and $Headers.Authorization -eq 'Bearer token-2' }
        (Get-midPointSession).TokenExpiresAt | Should -BeGreaterThan (Get-Date).AddMinutes(59)
    }

    It 'keeps using a token that is still valid' {
        Add-TestRoute '^GET users/' (New-TestResponse -Json (Get-TestUserJson))
        $null = Get-midPointUser -Oid $UserOid
        $tokenCount | Should -Be 1
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -ParameterFilter { $Uri -like '*/users/*' -and $Headers.Authorization -eq 'Bearer token-1' }
    }

    It 'renews the token once on HTTP 401 and repeats the request' {
        Add-TestRoute '^GET users/' (New-TestResponse -StatusCode 401), (New-TestResponse -Json (Get-TestUserJson))
        (Get-midPointUser -Oid $UserOid).Name | Should -Be 'jack'
        $tokenCount | Should -Be 2
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Uri -like '*/users/*' -and $Headers.Authorization -eq 'Bearer token-1' }
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Uri -like '*/users/*' -and $Headers.Authorization -eq 'Bearer token-2' }
    }

    It 'gives up after one renewal' {
        Add-TestRoute '^GET users/' (New-TestResponse -StatusCode 401)
        { Get-midPointUser -Oid $UserOid } | Should -Throw '*HTTP 401*access token rejected*'
        $tokenCount | Should -Be 2
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 2 -Exactly -ParameterFilter { $Uri -like '*/users/*' }
    }

    It 'says when the token expired and could not be renewed' {
        InModuleScope midPointTools { $script:midPointSession.TokenExpiresAt = [datetime]::UtcNow.AddSeconds(-5) }
        $script:tokenResponse = [pscustomobject]@{ StatusCode = 400; Body = [pscustomobject]@{ error = 'unauthorized_client' } }
        { Get-midPointUser -Oid $UserOid } | Should -Throw '*access token expires at*could not be renewed*unauthorized_client*'
    }

    It 'shows TokenExpiresAt and Bearer in the session output' {
        $s = Get-midPointSession
        $s.AuthType | Should -Be 'Bearer'
        $s.TokenExpiresAt.Kind | Should -Be 'Local'
        ($s | Out-String) | Should -Match 'TokenExpiresAt'
        ($s | Out-String) | Should -Not -Match 'token-1'
    }

    It 'Disconnect-midPoint drops token and client secret' {
        $data = InModuleScope midPointTools { $script:midPointSession }
        Disconnect-midPoint
        Get-midPointSession | Should -BeNullOrEmpty
        InModuleScope midPointTools { $script:midPointSession } | Should -BeNullOrEmpty
        { $data.AccessToken.Copy() } | Should -Throw
    }
}

Describe 'ConvertFrom-midPointJwt' {
    It 'reads the claims of a JWT' {
        $jwt = New-TestJwt @{ sub = 'abc'; preferred_username = 'service-account-client-1'; azp = 'client-1' }
        $claims = InModuleScope midPointTools -Parameters @{ Jwt = $jwt } { ConvertFrom-midPointJwt -Token $Jwt }
        $claims.preferred_username | Should -Be 'service-account-client-1'
        $claims.azp | Should -Be 'client-1'
    }

    It 'returns nothing for an opaque token' {
        InModuleScope midPointTools { ConvertFrom-midPointJwt -Token 'opaque-token' } | Should -BeNullOrEmpty
        InModuleScope midPointTools { ConvertFrom-midPointJwt -Token 'a.%%%.c' } | Should -BeNullOrEmpty
    }
}

Describe 'Basic session' {
    It 'still sends the Basic header (no token request)' {
        Set-TestSession
        Reset-TestRoute
        Mock Invoke-midPointHttp -ModuleName midPointTools { Invoke-TestRoute -Method $Method -Uri $Uri -Body $Body }
        Mock Invoke-midPointTokenRequest -ModuleName midPointTools { throw 'no token request expected' }
        Add-TestRoute '^GET users/' (New-TestResponse -StatusCode 401)
        { Get-midPointUser -Oid $UserOid } | Should -Throw '*login rejected*'
        Should -Invoke Invoke-midPointHttp -ModuleName midPointTools -Times 1 -Exactly -ParameterFilter { $Headers.Authorization -like 'Basic *' }
    }
}
