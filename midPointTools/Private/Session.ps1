function Get-midPointSessionOrThrow {
    # Returns the session set by Connect-midPoint, or stops with a clear message.
    [CmdletBinding()]
    param()

    if (-not $script:midPointSession) {
        throw [System.InvalidOperationException]::new('No midPoint session. Run Connect-midPoint first.')
    }
    $script:midPointSession
}

function ConvertTo-midPointBaseUri {
    # Accepts https://midpoint.example.com/midpoint (with or without trailing slash) or .../midpoint/ws/rest
    # and returns the REST base without a trailing slash.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [uri] $Uri
    )

    if (-not $Uri.IsAbsoluteUri -or $Uri.Scheme -notin 'http', 'https') {
        throw [System.ArgumentException]::new("Uri '$Uri' must be an absolute http(s) URL, e.g. https://midpoint.example.com/midpoint")
    }
    $base = $Uri.GetLeftPart([System.UriPartial]::Path).TrimEnd('/')
    if ($base -notmatch '/ws/rest$') {
        $base = "$base/ws/rest"
    }
    $base
}
