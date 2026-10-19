# Integration tests for the token login (OIDC client credentials) against a real midPoint test instance and
# identity provider. Not run in CI. Setup: docs/oidc.md and docs/integration-tests.md.
#
# Required environment variables (never commit values; settings.local.ps1 may set them):
#   MIDPOINT_URI                   as for the other integration tests
#   MIDPOINT_TOKEN_CLIENT_ID       client ID of the app registration (Entra ID) or client (Keycloak)
#   MIDPOINT_TOKEN_CLIENT_SECRET
#   MIDPOINT_TOKEN_ISSUER          the OIDC issuer (discovery), or instead:
#   MIDPOINT_TOKEN_ENDPOINT        the token URL
# Optional:
#   MIDPOINT_TOKEN_SCOPE           scope(s), separated by spaces (Entra ID: api://<midPoint app>/.default)
#   MIDPOINT_TOKEN_EXPECTED_USER   the midPoint user the token should log in as
#   MIDPOINT_TOKEN_OTHER_SCOPE     a scope of another API of the same issuer (e.g. the .default scope of
#                                  Microsoft Graph): does midPoint accept that token too (aud)?
#   MIDPOINT_TOKEN_URL_SUFFIX      urlSuffix of a separate REST sequence for the token: the test tries which URL
#                                  selects it
#   MIDPOINT_USER / MIDPOINT_PASSWORD  if set, the test checks that Basic still works next to the token
#   MIDPOINT_SKIP_CERT_CHECK, MIDPOINT_TIMEOUT_SEC  as for the other integration tests (midPoint only)
#
# Prints the token's claims (never the token or the secret), midPoint's answers to good and bad tokens, and
# creates and deletes one user MPTEST-<random>-TOK with the token's user (needs the API role on that user).

BeforeDiscovery {
    $script:tokenConfigured = $env:MIDPOINT_URI -and $env:MIDPOINT_TOKEN_CLIENT_ID -and $env:MIDPOINT_TOKEN_CLIENT_SECRET -and
        ($env:MIDPOINT_TOKEN_ISSUER -or $env:MIDPOINT_TOKEN_ENDPOINT)
    $script:hasBasic = $env:MIDPOINT_USER -and $env:MIDPOINT_PASSWORD
    $script:hasOtherScope = [bool]$env:MIDPOINT_TOKEN_OTHER_SCOPE
    $script:hasSuffix = [bool]$env:MIDPOINT_TOKEN_URL_SUFFIX
}

Describe 'midPoint token login (OIDC client credentials)' -Tag 'Integration' -Skip:(-not $tokenConfigured) {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'midPointTools' 'midPointTools.psd1') -Force
        $script:module = Get-Module midPointTools
        $secret = ConvertTo-SecureString $env:MIDPOINT_TOKEN_CLIENT_SECRET -AsPlainText -Force
        $script:client = [pscredential]::new($env:MIDPOINT_TOKEN_CLIENT_ID, $secret)
        $script:scope = @(if ($env:MIDPOINT_TOKEN_SCOPE) { $env:MIDPOINT_TOKEN_SCOPE -split '\s+' | Where-Object { $_ } })
        $script:skipCert = $env:MIDPOINT_SKIP_CERT_CHECK -eq '1'
        $script:timeout = if ($env:MIDPOINT_TIMEOUT_SEC) { [int]$env:MIDPOINT_TIMEOUT_SEC } else { 30 }
        $script:rest = & $module { param($u) ConvertTo-midPointBaseUri -Uri $u } $env:MIDPOINT_URI
        $script:root = $rest -replace '/ws/rest$', ''
        $script:name = 'MPTEST-{0}-TOK' -f (Get-Random -Minimum 100000 -Maximum 999999)

        $script:connectParams = @{
            Uri                  = $env:MIDPOINT_URI
            ClientCredential     = $client
            SkipCertificateCheck = $skipCert
            TimeoutSec           = $timeout
            WarningAction        = 'SilentlyContinue'
        }
        if ($env:MIDPOINT_TOKEN_ISSUER) { $connectParams.Issuer = $env:MIDPOINT_TOKEN_ISSUER } else { $connectParams.TokenEndpoint = $env:MIDPOINT_TOKEN_ENDPOINT }
        if ($scope) { $connectParams.Scope = $scope }

        function Get-TestToken {
            # A token straight from the IdP (module functions), as plain text for the raw calls. Never printed.
            param([string[]] $TokenScope)
            $endpoint = if ($env:MIDPOINT_TOKEN_ISSUER) {
                & $module { param($i, $t) Get-midPointTokenEndpoint -Issuer $i -TimeoutSec $t } $env:MIDPOINT_TOKEN_ISSUER $timeout
            }
            else { $env:MIDPOINT_TOKEN_ENDPOINT }
            $t = & $module { param($e, $c, $s, $to) Get-midPointAccessToken -TokenEndpoint $e -ClientCredential $c -Scope $s -TimeoutSec $to } $endpoint $client $TokenScope $timeout
            [System.Net.NetworkCredential]::new('', $t.AccessToken).Password
        }

        function Get-TestClaim {
            param([string] $Token)
            & $module { param($t) ConvertFrom-midPointJwt -Token $t } $Token
        }

        function Format-Claim {
            # The claims that matter for midPoint; tid and other ids only by name.
            param($Claims)
            if (-not $Claims) { return 'not a JWT (opaque token): midPoint needs resourceServer/opaqueToken' }
            $shown = foreach ($n in 'iss', 'aud', 'azp', 'appid', 'client_id', 'sub', 'preferred_username', 'upn', 'scp', 'roles', 'ver', 'iat', 'exp') {
                $p = $Claims.PSObject.Properties[$n]
                if (-not $p) { continue }
                if ($n -in 'iat', 'exp') { '{0}={1:s}' -f $n, [DateTimeOffset]::FromUnixTimeSeconds([long]$p.Value).LocalDateTime }
                else { '{0}={1}' -f $n, (@($p.Value) -join ' ') }
            }
            "$($shown -join ', ') | all claims: $(@($Claims.PSObject.Properties.Name) -join ', ')"
        }

        function Invoke-RawSelf {
            # GET self with a given Authorization header (or none), past the module's error handling.
            param([string] $Authorization, [string] $Base = $rest)
            $headers = @{ Accept = 'application/json' }
            if ($Authorization) { $headers.Authorization = $Authorization }
            try {
                $r = & $module { param($u, $h, $s, $t) Invoke-midPointHttp -Method GET -Uri $u -Headers $h -SkipCertificateCheck:$s -TimeoutSec $t } "$Base/self" $headers $skipCert $timeout
            }
            catch { return [pscustomobject]@{ Status = 0; Challenge = ''; Name = $null; Text = "request failed: $($_.Exception.Message)" } }
            $challenge = & $module { param($h) Get-midPointHeaderValue $h 'WWW-Authenticate' } $r.Headers
            $selfName = $null
            $text = if ($null -eq $r.Body) { '<no body>' }
            elseif ($r.Body -is [string]) { $r.Body.Trim() }
            else {
                $obj = & $module { param($b) Get-midPointObjectFromResponse -Body $b } $r.Body
                $selfName = & $module { param($o) ConvertFrom-midPointPolyString (Get-midPointProperty $o 'name') } $obj
                if ($selfName) { "user $selfName" } else { & $module { param($b) Get-midPointErrorMessage -Body $b } $r.Body }
            }
            if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + '...' }
            [pscustomobject]@{ Status = [int]$r.StatusCode; Challenge = $challenge; Name = $selfName; Text = $text }
        }

        function Show-Answer {
            param([string] $Label, $Answer)
            Write-Host ("{0}: HTTP {1}, WWW-Authenticate: {2}, body: {3}" -f $Label, $Answer.Status, $(if ($Answer.Challenge) { $Answer.Challenge } else { '<none>' }), $Answer.Text)
        }

        Write-Host "Token login: midPoint $rest, $(if ($env:MIDPOINT_TOKEN_ISSUER) { 'issuer (discovery)' } else { 'token endpoint' }), client ID set, scope '$($scope -join ' ')'"
        $script:token = Get-TestToken -TokenScope $scope
        $script:claims = Get-TestClaim $token
    }

    AfterAll {
        if ((Get-midPointSession) -and (Get-midPointSession).AuthType -eq 'Bearer') {
            Get-midPointUser -Filter ('name = "{0}"' -f $name) | Remove-midPointUser -Confirm:$false
            Disconnect-midPoint
        }
        $script:token = $null
    }

    It 'gets an access token from the identity provider' {
        $token | Should -Not -BeNullOrEmpty
        $header = & $module { param($t) $p = $t.Split('.'); if ($p.Count -eq 3) { ConvertFrom-midPointJwt -Token ('x.' + $p[0] + '.x') } } $token
        Write-Host "Token header: alg=$($header.alg), typ=$($header.typ)"
        Write-Host "Token claims: $(Format-Claim $claims)"
    }

    It 'midPoint accepts the token (GET self, raw)' {
        $a = Invoke-RawSelf -Authorization "Bearer $token"
        Show-Answer 'GET self with the token' $a
        if ($a.Name -and $claims) {
            $matching = @($claims.PSObject.Properties | Where-Object { "$($_.Value)" -eq $a.Name } | ForEach-Object Name)
            Write-Host "midPoint user '$($a.Name)' matches the claim(s): $(if ($matching) { $matching -join ', ' } else { '<none>' })"
        }
        $a.Status | Should -Be 200
    }

    It 'Connect-midPoint logs in with the token' {
        $s = Connect-midPoint @connectParams -PassThru
        Write-Host "Session: user $($s.UserName) ($($s.UserOid)), AuthType $($s.AuthType), token expires $($s.TokenExpiresAt.ToString('s'))"
        $s.AuthType | Should -Be 'Bearer'
        $s.UserOid | Should -Not -BeNullOrEmpty
        if ($env:MIDPOINT_TOKEN_EXPECTED_USER) { $s.UserName | Should -Be $env:MIDPOINT_TOKEN_EXPECTED_USER }
    }

    It 'the API role works for the token user (create, search, delete a user)' {
        if (-not (Get-midPointSession)) { Set-ItResult -Skipped -Because 'Connect-midPoint failed'; return }
        $u = New-midPointUser -Name $name -PassThru
        try {
            (Get-midPointUser $name).Oid | Should -Be $u.Oid
            Write-Host "Created and found $name with the token"
        }
        finally { $u | Remove-midPointUser -Confirm:$false }
        Get-midPointUser $name | Should -BeNullOrEmpty
    }

    It 'renews a token that expires within 60 s' {
        if (-not (Get-midPointSession)) { Set-ItResult -Skipped -Because 'Connect-midPoint failed'; return }
        $before = & $module { [System.Net.NetworkCredential]::new('', $script:midPointSession.AccessToken).Password.GetHashCode(); $script:midPointSession.TokenExpiresAt = [datetime]::UtcNow.AddSeconds(30) }
        $out = @(Get-midPointUser -Oid (Get-midPointSession).UserOid -Verbose 4>&1)
        $after = & $module { [System.Net.NetworkCredential]::new('', $script:midPointSession.AccessToken).Password.GetHashCode() }
        Write-Host "Verbose: $(($out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match 'token' }).Message -join ' | ')"
        Write-Host "New token: $(if ($after -ne $before) { 'different' } else { 'the same as before (IdP cache)' }), expires $((Get-midPointSession).TokenExpiresAt.ToString('s'))"
        ($out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }).Oid | Should -Be (Get-midPointSession).UserOid
        (Get-midPointSession).TokenExpiresAt | Should -BeGreaterThan (Get-Date).AddMinutes(1)
    }

    It 'renews a rejected token once (HTTP 401, retry)' {
        if (-not (Get-midPointSession)) { Set-ItResult -Skipped -Because 'Connect-midPoint failed'; return }
        & $module { $script:midPointSession.AccessToken = [System.Net.NetworkCredential]::new('', 'garbled-token').SecurePassword }
        $out = @(Get-midPointUser -Oid (Get-midPointSession).UserOid -Verbose 4>&1)
        Write-Host "Verbose: $(($out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '^midPoint: HTTP|token' }).Message -join ' | ')"
        ($out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }).Oid | Should -Be (Get-midPointSession).UserOid
    }

    It 'answers bad tokens with 401' {
        $parts = $token.Split('.')
        $cases = [ordered]@{
            'no Authorization header'    = $null
            'garbled token'              = 'Bearer not-a-token'
        }
        if ($parts.Count -eq 3) {
            # Same header and claims, other signature.
            $sig = $parts[2]
            $bad = if ($sig.StartsWith('A')) { 'B' + $sig.Substring(1) } else { 'A' + $sig.Substring(1) }
            $cases['token with a wrong signature'] = "Bearer $($parts[0]).$($parts[1]).$bad"
        }
        foreach ($c in $cases.GetEnumerator()) {
            $a = Invoke-RawSelf -Authorization $c.Value
            Show-Answer $c.Key $a
            $a.Status | Should -Not -Be 200 -Because "$($c.Key) must not log in"
        }
    }

    It 'Basic still works next to the token (same URL)' -Skip:(-not $hasBasic) {
        $a = Invoke-RawSelf -Authorization ('Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($env:MIDPOINT_USER):$($env:MIDPOINT_PASSWORD)")))
        Show-Answer 'GET self with Basic' $a
        $a.Status | Should -Be 200
    }

    It 'a token for another API of the same issuer (aud check)' -Skip:(-not $hasOtherScope) {
        $other = $null
        try { $other = Get-TestToken -TokenScope ($env:MIDPOINT_TOKEN_OTHER_SCOPE -split '\s+') }
        catch { Write-Warning "No token for '$env:MIDPOINT_TOKEN_OTHER_SCOPE': $($_.Exception.Message)" }
        if (-not $other) { Set-ItResult -Inconclusive -Because 'the IdP issued no token for the other scope'; return }
        Write-Host "Other token claims: $(Format-Claim (Get-TestClaim $other))"
        $a = Invoke-RawSelf -Authorization "Bearer $other"
        Show-Answer 'GET self with the other token' $a
        if ($a.Status -eq 200) { Write-Warning 'midPoint accepts a token for another audience: aud is not checked.' }
        else { Write-Host 'midPoint rejects a token for another audience.' }
    }

    It 'which URL selects the REST sequence with urlSuffix (MIDPOINT_TOKEN_URL_SUFFIX)' -Skip:(-not $hasSuffix) {
        $sfx = $env:MIDPOINT_TOKEN_URL_SUFFIX.Trim('/')
        $found = foreach ($base in "$root/ws/rest/$sfx", "$root/ws/$sfx", "$root/$sfx/ws/rest", "$root/rest/$sfx") {
            $a = Invoke-RawSelf -Authorization "Bearer $token" -Base $base
            Show-Answer "GET $($base.Substring($root.Length))/self" $a
            if ($a.Status -eq 200) { $base.Substring($root.Length) }
        }
        Write-Host "URL(s) that work with the token: $(if ($found) { $found -join ', ' } else { '<none>' })"
    }
}
