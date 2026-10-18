function Invoke-midPointRestMethod {
    # The only place that talks to midPoint. Builds the URL and the Basic header from the
    # current session, sends JSON, and turns midPoint errors into terminating errors.
    # Returns an object with StatusCode, Headers and Body.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string] $Method,

        # Path relative to <base>/ws/rest, e.g. 'users/<oid>' or 'users/search'.
        [Parameter(Mandatory)]
        [string] $Path,

        # Query parameters. An array value is sent as a repeated parameter
        # (midPoint expects ?options=raw&options=resolveNames).
        [System.Collections.IDictionary] $Query,

        # Request body; serialized to JSON.
        [object] $Body
    )

    $session = Get-midPointSessionOrThrow

    $uri = '{0}/{1}' -f $session.Uri, $Path.TrimStart('/')
    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            foreach ($value in @($Query[$key])) {
                if ($null -ne $value -and "$value" -ne '') {
                    '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString([string]$value)
                }
            }
        }
        if ($pairs) {
            $uri = '{0}?{1}' -f $uri, ($pairs -join '&')
        }
    }

    $credential = $session.Credential
    $pair = '{0}:{1}' -f $credential.UserName, $credential.GetNetworkCredential().Password
    $headers = @{
        Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
        Accept        = 'application/json'
    }

    $httpParams = @{
        Method               = $Method
        Uri                  = $uri
        Headers              = $headers
        SkipCertificateCheck = [bool]$session.SkipCertificateCheck
    }
    if ($session.TimeoutSec) {
        $httpParams.TimeoutSec = $session.TimeoutSec
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $httpParams.Body = ConvertTo-Json -InputObject $Body -Depth 50 -Compress
        Write-Debug ("midPoint request body: " + ($httpParams.Body -replace '"clearValue":"(\\.|[^"\\])*"', '"clearValue":"***"'))
    }

    Write-Verbose "midPoint: $Method $uri"
    try {
        $response = Invoke-midPointHttp @httpParams
    }
    catch {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Net.Http.HttpRequestException]::new("midPoint request $Method $uri failed: $($_.Exception.Message)", $_.Exception),
            'midPointConnectionFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $uri)
        throw $record
    }

    $status = [int]$response.StatusCode
    Write-Verbose "midPoint: HTTP $status"

    if ($status -ge 400) {
        $message = Get-midPointErrorMessage -Body $response.Body
        $category = switch ($status) {
            400 { 'InvalidArgument' }
            401 { 'AuthenticationError' }
            403 { 'PermissionDenied' }
            404 { 'ObjectNotFound' }
            409 { 'ResourceExists' }
            default { 'InvalidOperation' }
        }
        $text = "midPoint returned HTTP $status for $Method $Path"
        if ($message) { $text = "$text`: $message" }
        elseif ($status -eq 401) { $text = "$text`: login rejected, check user name, password and that the user may use REST" }
        $exception = [System.Exception]::new($text)
        $exception.Data['StatusCode'] = $status
        $record = [System.Management.Automation.ErrorRecord]::new(
            $exception, "midPointHttp$status", [System.Management.Automation.ErrorCategory]$category, $uri)
        throw $record
    }

    # 240 = handled error, 250 = partial error (midPoint REST operation docs).
    if ($status -eq 250) {
        Write-Warning "midPoint reported a partial error for $Method $Path`: $(Get-midPointErrorMessage -Body $response.Body)"
    }
    elseif ($status -eq 240) {
        Write-Verbose "midPoint handled an error for $Method $Path`: $(Get-midPointErrorMessage -Body $response.Body)"
    }

    $response
}

function Get-midPointErrorMessage {
    # Pulls the most useful message out of a midPoint OperationResult (or any body).
    # TODO(verify): exact JSON shape of the OperationResult on 4.10; this searches for
    # the first non-empty 'message' property at any depth.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Body
    )

    if ($null -eq $Body) { return '' }
    if ($Body -is [string]) { return $Body.Trim() }

    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue($Body)
    while ($queue.Count -gt 0) {
        $item = $queue.Dequeue()
        if ($item -is [System.Management.Automation.PSCustomObject]) {
            $msg = $item.PSObject.Properties['message']
            if ($msg -and $msg.Value -is [string] -and $msg.Value) { return $msg.Value }
            foreach ($p in $item.PSObject.Properties) {
                if ($null -ne $p.Value -and $p.Value -isnot [string]) { $queue.Enqueue($p.Value) }
            }
        }
        elseif ($item -is [System.Collections.IEnumerable]) {
            foreach ($child in $item) { if ($null -ne $child) { $queue.Enqueue($child) } }
        }
    }
    ''
}
