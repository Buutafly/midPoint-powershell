function Connect-midPoint {
    <#
    .SYNOPSIS
    Connects to a midPoint server and stores the session for the other cmdlets.

    .DESCRIPTION
    Checks the login with GET /self and keeps the connection in memory for the
    current PowerShell session. All other midPointTools cmdlets use it automatically.
    Nothing is written to disk.

    Two ways to log in:
    - HTTP Basic (midPoint's default for the REST API) with -Credential: a midPoint user and password.
    - OIDC client credentials with -ClientCredential and -Issuer or -TokenEndpoint: the cmdlet gets an access
      token from the identity provider (e.g. Entra ID or Keycloak) and sends it as Bearer token. midPoint must
      accept tokens of that provider (an oidc module with resourceServer in the security policy) and finds the
      midPoint user named after a claim of the token. The token is renewed automatically with the client
      secret, which stays in memory until Disconnect-midPoint. See docs/oidc.md.

    The midPoint user needs the REST authorizations for the operations you want to run.

    .PARAMETER Uri
    The midPoint base URL, e.g. https://midpoint.example.com/midpoint. A URL that already
    ends with /ws/rest is accepted too.

    .PARAMETER Credential
    The midPoint user and password (HTTP Basic).

    .PARAMETER Issuer
    The OIDC issuer of the identity provider; the token endpoint is read from
    <Issuer>/.well-known/openid-configuration. Entra ID: https://login.microsoftonline.com/<tenant>/v2.0,
    Keycloak: https://idp.example.com/realms/<realm>.

    .PARAMETER TokenEndpoint
    The token URL of the identity provider, instead of -Issuer (no discovery).

    .PARAMETER ClientCredential
    Client ID as user name and client secret as password (like Connect-AzAccount -ServicePrincipal).

    .PARAMETER Scope
    The scope(s) to request. Entra ID needs the midPoint app's scope, e.g. api://<app>/.default; Keycloak
    works without.

    .PARAMETER SkipCertificateCheck
    Do not validate midPoint's server certificate (test systems with self-signed certificates only).
    The identity provider's certificate is always checked.

    .PARAMETER TimeoutSec
    How long to wait for midPoint (and the identity provider) to answer a request, in seconds. Default 100.

    .PARAMETER PassThru
    Return the session object.

    .EXAMPLE
    Connect-midPoint -Uri https://midpoint.example.com/midpoint -Credential (Get-Credential)

    .EXAMPLE
    $cred = Get-Credential
    Connect-midPoint -Uri $env:MIDPOINT_URI -Credential $cred -PassThru

    .EXAMPLE
    $client = Get-Credential -Message 'Client ID and secret'
    Connect-midPoint -Uri https://midpoint.example.com/midpoint -Issuer https://idp.example.com/realms/example -ClientCredential $client

    Keycloak: client credentials of a confidential client with service account.

    .EXAMPLE
    Connect-midPoint -Uri https://midpoint.example.com/midpoint -Issuer https://login.microsoftonline.com/<tenant>/v2.0 -ClientCredential $client -Scope 'api://<midPoint app ID>/.default'

    Entra ID: the token is requested for the midPoint app registration (Expose an API).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    [OutputType('midPointTools.Session')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [uri] $Uri,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Credential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory, ParameterSetName = 'Issuer')]
        [uri] $Issuer,

        [Parameter(Mandatory, ParameterSetName = 'TokenEndpoint')]
        [uri] $TokenEndpoint,

        [Parameter(Mandatory, ParameterSetName = 'Issuer')]
        [Parameter(Mandatory, ParameterSetName = 'TokenEndpoint')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $ClientCredential,

        [Parameter(ParameterSetName = 'Issuer')]
        [Parameter(ParameterSetName = 'TokenEndpoint')]
        [string[]] $Scope,

        [switch] $SkipCertificateCheck,

        [ValidateRange(1, 3600)]
        [int] $TimeoutSec = 100,

        [switch] $PassThru
    )

    $baseUri = ConvertTo-midPointBaseUri -Uri $Uri
    $bearer = $PSCmdlet.ParameterSetName -ne 'Credential'
    if ($baseUri -like 'http://*') {
        $what = if ($bearer) { 'access token' } else { 'password' }
        Write-Warning "The connection uses http. The $what is sent in clear text; use https outside of local test systems."
    }

    Write-Verbose "Connecting to $baseUri (timeout $TimeoutSec s)"
    $previous = $script:midPointSession
    $session = [pscustomobject]@{
        PSTypeName           = 'midPointTools.SessionData'
        Uri                  = $baseUri
        AuthType             = if ($bearer) { 'Bearer' } else { 'Basic' }
        Credential           = if ($bearer) { $null } else { $Credential }
        AccessToken          = $null
        TokenExpiresAt       = $null
        TokenSource          = $null
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        TimeoutSec           = $TimeoutSec
        UserName             = $null
        UserOid              = $null
        ConnectedAt          = $null
    }

    try {
        if ($bearer) {
            foreach ($idp in @($Issuer, $TokenEndpoint) | Where-Object { $_ }) {
                if (-not $idp.IsAbsoluteUri -or $idp.Scheme -notin 'http', 'https') {
                    throw [System.ArgumentException]::new("'$idp' must be an absolute http(s) URL.")
                }
                if ($idp.Scheme -eq 'http') {
                    Write-Warning "The identity provider uses http. The client secret is sent in clear text; use https outside of local test systems."
                }
            }
            $endpoint = if ($Issuer) { Get-midPointTokenEndpoint -Issuer $Issuer -TimeoutSec $TimeoutSec } else { $TokenEndpoint.AbsoluteUri }
            $session.TokenSource = [pscustomobject]@{
                Issuer           = if ($Issuer) { $Issuer.AbsoluteUri } else { $null }
                TokenEndpoint    = $endpoint
                ClientCredential = $ClientCredential
                Scope            = $Scope
            }
        }
        $script:midPointSession = $session
        # For Bearer the first request gets the token.
        $response = Invoke-midPointRestMethod -Method GET -Path 'self'
    }
    catch {
        if ($session.AccessToken) { $session.AccessToken.Dispose() }
        $script:midPointSession = $previous
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $self = Get-midPointObjectFromResponse -Body $response.Body
    $script:midPointSession.UserName = ConvertFrom-midPointPolyString (Get-midPointProperty $self 'name')
    if (-not $script:midPointSession.UserName) {
        $script:midPointSession.UserName = if ($bearer) { $ClientCredential.UserName } else { $Credential.UserName }
    }
    $script:midPointSession.UserOid = [string](Get-midPointProperty $self 'oid')
    $script:midPointSession.ConnectedAt = Get-Date

    Write-Verbose "Connected to $baseUri as $($script:midPointSession.UserName)"
    if ($PassThru) {
        Get-midPointSession
    }
}
