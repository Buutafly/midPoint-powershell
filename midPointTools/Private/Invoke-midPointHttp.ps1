function Invoke-midPointHttp {
    # Thin wrapper around Invoke-RestMethod so the rest of the module (and the tests)
    # can work with status code, headers and body as one object.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [string] $Body,

        [switch] $SkipCertificateCheck,

        [int] $TimeoutSec = 100
    )

    $params = @{
        Method                  = $Method
        Uri                     = $Uri
        Headers                 = $Headers
        SkipHttpErrorCheck      = $true
        StatusCodeVariable      = 'statusCode'
        ResponseHeadersVariable = 'responseHeaders'
        TimeoutSec              = $TimeoutSec
        ErrorAction             = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $params.ContentType = 'application/json; charset=utf-8'
    }
    if ($SkipCertificateCheck) {
        $params.SkipCertificateCheck = $true
    }

    $response = Invoke-RestMethod @params

    [pscustomobject]@{
        StatusCode = $statusCode
        Headers    = $responseHeaders
        Body       = $response
    }
}
