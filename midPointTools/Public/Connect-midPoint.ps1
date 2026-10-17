function Connect-midPoint {
    <#
    .SYNOPSIS
    Connects to a midPoint server and stores the session for the other cmdlets.

    .DESCRIPTION
    Checks the credential with GET /self and keeps the connection in memory for the
    current PowerShell session. All other midPointTools cmdlets use it automatically.
    Authentication is HTTP Basic (midPoint's default for the REST API). The user needs
    the REST authorizations for the operations you want to run.
    Nothing is written to disk.

    .PARAMETER Uri
    The midPoint base URL, e.g. https://midpoint.example.com/midpoint. A URL that already
    ends with /ws/rest is accepted too.

    .PARAMETER Credential
    The midPoint user and password.

    .PARAMETER SkipCertificateCheck
    Do not validate the server certificate (test systems with self-signed certificates only).

    .PARAMETER TimeoutSec
    How long to wait for midPoint to answer a request, in seconds. Default 100.

    .PARAMETER PassThru
    Return the session object.

    .EXAMPLE
    Connect-midPoint -Uri https://midpoint.example.com/midpoint -Credential (Get-Credential)

    .EXAMPLE
    $cred = Get-Credential
    Connect-midPoint -Uri $env:MIDPOINT_URI -Credential $cred -PassThru
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.Session')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [uri] $Uri,

        [Parameter(Mandatory, Position = 1)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [switch] $SkipCertificateCheck,

        [ValidateRange(1, 3600)]
        [int] $TimeoutSec = 100,

        [switch] $PassThru
    )

    $baseUri = ConvertTo-midPointBaseUri -Uri $Uri
    if ($baseUri -like 'http://*') {
        Write-Warning 'The connection uses http. The password is sent in clear text; use https outside of local test systems.'
    }

    Write-Verbose "Connecting to $baseUri (timeout $TimeoutSec s)"
    $previous = $script:midPointSession
    $script:midPointSession = [pscustomobject]@{
        PSTypeName           = 'midPointTools.SessionData'
        Uri                  = $baseUri
        AuthType             = 'Basic'
        Credential           = $Credential
        SkipCertificateCheck = [bool]$SkipCertificateCheck
        TimeoutSec           = $TimeoutSec
        UserName             = $null
        UserOid              = $null
        ConnectedAt          = $null
    }

    try {
        $response = Invoke-midPointRestMethod -Method GET -Path 'self'
    }
    catch {
        $script:midPointSession = $previous
        $PSCmdlet.ThrowTerminatingError($_)
    }

    $self = Get-midPointObjectFromResponse -Body $response.Body
    $script:midPointSession.UserName = ConvertFrom-midPointPolyString (Get-midPointProperty $self 'name')
    if (-not $script:midPointSession.UserName) { $script:midPointSession.UserName = $Credential.UserName }
    $script:midPointSession.UserOid = [string](Get-midPointProperty $self 'oid')
    $script:midPointSession.ConnectedAt = Get-Date

    Write-Verbose "Connected to $baseUri as $($script:midPointSession.UserName)"
    if ($PassThru) {
        Get-midPointSession
    }
}
