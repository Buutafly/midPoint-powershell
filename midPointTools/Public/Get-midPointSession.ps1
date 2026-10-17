function Get-midPointSession {
    <#
    .SYNOPSIS
    Shows the current midPoint connection.

    .DESCRIPTION
    Returns the URL, the connected user and the connection options. The password is not part of the output.
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
        SkipCertificateCheck = $session.SkipCertificateCheck
        ConnectedAt          = $session.ConnectedAt
    }
}
