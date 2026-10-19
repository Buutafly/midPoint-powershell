function Get-midPointSession {
    <#
    .SYNOPSIS
    Shows the current midPoint connection.

    .DESCRIPTION
    Returns the URL, the connected user and the connection options. Neither the password nor the access token
    or client secret are part of the output. With a token login (AuthType Bearer), TokenExpiresAt shows when
    the current access token expires; it is renewed automatically.
    Returns nothing when there is no connection.

    .EXAMPLE
    Get-midPointSession
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.Session')]
    param()

    $session = $script:midPointSession
    if (-not $session) { return }

    [pscustomobject]@{
        PSTypeName           = 'midPointTools.Session'
        Uri                  = $session.Uri
        UserName             = $session.UserName
        UserOid              = $session.UserOid
        AuthType             = $session.AuthType
        TokenExpiresAt       = if ($session.TokenExpiresAt) { $session.TokenExpiresAt.ToLocalTime() } else { $null }
        SkipCertificateCheck = $session.SkipCertificateCheck
        TimeoutSec           = $session.TimeoutSec
        ConnectedAt          = $session.ConnectedAt
    }
}
