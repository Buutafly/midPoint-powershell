function Invoke-midPointTokenRequest {
    # Thin wrapper around Invoke-RestMethod for the identity provider (discovery and token endpoint), so the
    # tests can mock it. Logs neither the request body (client secret) nor the response (access token).
    # The IdP certificate is always checked (-SkipCertificateCheck of Connect-midPoint is for midPoint only).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        # Form body (application/x-www-form-urlencoded), already encoded.
        [string] $Body,

        [int] $TimeoutSec = 100
    )

    $params = @{
        Method             = $Method
        Uri                = $Uri
        Headers            = @{ Accept = 'application/json' }
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
        TimeoutSec         = $TimeoutSec
        ErrorAction        = 'Stop'
        Verbose            = $false
        Debug              = $false
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Body = $Body
        $params.ContentType = 'application/x-www-form-urlencoded'
    }

    $response = Invoke-RestMethod @params

    [pscustomobject]@{
        StatusCode = $statusCode
        Body       = $response
    }
}

function Get-midPointTokenEndpoint {
    # OIDC discovery: reads token_endpoint from <issuer>/.well-known/openid-configuration.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [uri] $Issuer,

        [int] $TimeoutSec = 100
    )

    $discovery = '{0}/.well-known/openid-configuration' -f $Issuer.AbsoluteUri.TrimEnd('/')
    Write-Verbose "OIDC discovery: GET $discovery"
    try {
        $response = Invoke-midPointTokenRequest -Method GET -Uri $discovery -TimeoutSec $TimeoutSec
    }
    catch {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Net.Http.HttpRequestException]::new("OIDC discovery $discovery failed: $($_.Exception.Message)", $_.Exception),
            'midPointTokenConnectionFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $discovery)
        throw $record
    }

    $endpoint = if ([int]$response.StatusCode -lt 400 -and $response.Body -isnot [string]) { [string](Get-midPointProperty $response.Body 'token_endpoint') }
    if (-not $endpoint) {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new("OIDC discovery $discovery returned HTTP $($response.StatusCode) without a token_endpoint. Check -Issuer, or give the token URL with -TokenEndpoint."),
            'midPointTokenDiscoveryFailed',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $discovery)
        throw $record
    }
    Write-Verbose "OIDC token endpoint: $endpoint"
    $endpoint
}

function Get-midPointAccessToken {
    # Client credentials grant (RFC 6749 4.4) with the secret in the body (client_secret_post, supported by
    # Entra ID and Keycloak). Returns the token as SecureString and when it expires (UTC).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TokenEndpoint,

        [Parameter(Mandatory)]
        [pscredential] $ClientCredential,

        [string[]] $Scope,

        [int] $TimeoutSec = 100
    )

    $fields = [ordered]@{
        grant_type    = 'client_credentials'
        client_id     = $ClientCredential.UserName
        client_secret = $ClientCredential.GetNetworkCredential().Password
    }
    if ($Scope) { $fields.scope = $Scope -join ' ' }
    $body = ($fields.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value) }) -join '&'

    Write-Verbose "Requesting an access token from $TokenEndpoint for client $($ClientCredential.UserName)$(if ($Scope) { " (scope $($Scope -join ' '))" })"
    try {
        $response = Invoke-midPointTokenRequest -Method POST -Uri $TokenEndpoint -Body $body -TimeoutSec $TimeoutSec
    }
    catch {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Net.Http.HttpRequestException]::new("Token request to $TokenEndpoint failed: $($_.Exception.Message)", $_.Exception),
            'midPointTokenConnectionFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $TokenEndpoint)
        throw $record
    }
    finally {
        $body = $null
        $fields.client_secret = $null
    }

    $status = [int]$response.StatusCode
    $token = if ($status -lt 400 -and $response.Body -isnot [string]) { [string](Get-midPointProperty $response.Body 'access_token') }
    if (-not $token) {
        # RFC 6749 5.2: error and error_description; never the request (it holds the secret).
        $detail = if ($response.Body -and $response.Body -isnot [string]) {
            @((Get-midPointProperty $response.Body 'error'), (Get-midPointProperty $response.Body 'error_description')) | Where-Object { $_ }
        }
        $text = "Token request to $TokenEndpoint for client $($ClientCredential.UserName) failed: HTTP $status"
        if ($detail) { $text = "$text, $($detail -join ': ')" }
        elseif ($status -lt 400) { $text = "$text without an access_token" }
        $exception = [System.Exception]::new($text)
        $exception.Data['StatusCode'] = $status
        $record = [System.Management.Automation.ErrorRecord]::new(
            $exception, 'midPointTokenRequestFailed', [System.Management.Automation.ErrorCategory]::AuthenticationError, $TokenEndpoint)
        throw $record
    }

    $tokenType = [string](Get-midPointProperty $response.Body 'token_type')
    if ($tokenType -and $tokenType -ne 'Bearer') {
        Write-Warning "The identity provider issued a token of type '$tokenType'; midPoint expects a Bearer token."
    }

    $expiresAt = $null
    $expiresIn = Get-midPointProperty $response.Body 'expires_in'
    if ($null -ne $expiresIn -and "$expiresIn" -match '^\d+$') {
        $expiresAt = [datetime]::UtcNow.AddSeconds([int]$expiresIn)
    }
    else {
        $claims = ConvertFrom-midPointJwt -Token $token
        if ($claims -and "$($claims.exp)" -match '^\d+$') {
            $expiresAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).UtcDateTime
        }
    }
    Write-Verbose "Access token received$(if ($expiresAt) { ", valid until $($expiresAt.ToLocalTime().ToString('s'))" })"

    [pscustomobject]@{
        AccessToken = [System.Net.NetworkCredential]::new('', $token).SecurePassword
        ExpiresAt   = $expiresAt
    }
}

function ConvertFrom-midPointJwt {
    # Returns the claims (payload) of a JWT, or nothing for an opaque token. Does not check the signature:
    # only for the expiry and diagnostics, midPoint checks the token.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Token
    )

    $parts = $Token.Split('.')
    if ($parts.Count -ne 3) { return }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
    }
    try {
        [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Verbose 'The access token is not a readable JWT.'
    }
}

function Request-midPointSessionToken {
    # Requests a new token for a Bearer session with the stored client credential.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Session
    )

    $source = $Session.TokenSource
    try {
        $new = Get-midPointAccessToken -TokenEndpoint $source.TokenEndpoint -ClientCredential $source.ClientCredential -Scope $source.Scope -TimeoutSec $Session.TimeoutSec
    }
    catch {
        if ($Session.TokenExpiresAt) {
            $text = "The access token expires at $($Session.TokenExpiresAt.ToLocalTime().ToString('s')) and could not be renewed: $($_.Exception.Message)"
            $record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($text, $_.Exception), $_.FullyQualifiedErrorId, $_.CategoryInfo.Category, $_.TargetObject)
            throw $record
        }
        throw
    }
    if ($Session.AccessToken) { $Session.AccessToken.Dispose() }
    $Session.AccessToken = $new.AccessToken
    $Session.TokenExpiresAt = $new.ExpiresAt
}

function Get-midPointAuthorizationHeader {
    # The Authorization header for the session: Basic from the credential, or Bearer with the access token
    # (requested or renewed first when missing or expiring within 60 s). Sets $Renewed when it got a new token.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Session,

        [ref] $Renewed
    )

    if ($Session.AuthType -eq 'Bearer') {
        $expiring = $Session.TokenExpiresAt -and $Session.TokenExpiresAt -le [datetime]::UtcNow.AddSeconds(60)
        if (-not $Session.AccessToken -or $expiring) {
            if ($expiring) { Write-Verbose 'midPoint: the access token expires within 60 s, renewing it' }
            Request-midPointSessionToken -Session $Session
            if ($Renewed) { $Renewed.Value = $true }
        }
        return 'Bearer ' + [System.Net.NetworkCredential]::new('', $Session.AccessToken).Password
    }

    $credential = $Session.Credential
    $pair = '{0}:{1}' -f $credential.UserName, $credential.GetNetworkCredential().Password
    'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
}
