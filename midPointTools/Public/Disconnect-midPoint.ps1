function Disconnect-midPoint {
    <#
    .SYNOPSIS
    Removes the stored midPoint session.

    .DESCRIPTION
    Forgets the connection and the credential stored by Connect-midPoint (password, or access token and
    client secret). midPoint REST uses no server-side session, so nothing is sent to the server.

    .EXAMPLE
    Disconnect-midPoint
    #>
    [CmdletBinding()]
    param()

    if (-not $script:midPointSession) {
        Write-Verbose 'No midPoint session to remove.'
        return
    }
    if ($script:midPointSession.AccessToken) { $script:midPointSession.AccessToken.Dispose() }
    $script:midPointSession = $null
}
