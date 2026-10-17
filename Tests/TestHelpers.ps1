# Shared helpers for the unit tests. Dot-source in BeforeAll.
# The tests never reach a midPoint server: Invoke-midPointHttp (the only network call) is mocked
# and answered from routes the test defines.

$script:ModuleManifest = Join-Path $PSScriptRoot '..' 'midPointTools' 'midPointTools.psd1'

$script:UserOid = '11111111-1111-1111-1111-111111111111'
$script:RoleOid = '22222222-2222-2222-2222-222222222222'
$script:ShadowOid = '33333333-3333-3333-3333-333333333333'
$script:ResourceOid = '44444444-4444-4444-4444-444444444444'
$script:OtherOid = '55555555-5555-5555-5555-555555555555'

function Initialize-TestModule {
    Get-Module midPointTools | Remove-Module -Force
    Import-Module $script:ModuleManifest -Force
}

function Set-TestSession {
    InModuleScope midPointTools {
        $script:midPointSession = [pscustomobject]@{
            PSTypeName           = 'midPointTools.SessionData'
            Uri                  = 'https://midpoint.example.com/midpoint/ws/rest'
            AuthType             = 'Basic'
            Credential           = [pscredential]::new('tester', (ConvertTo-SecureString 'not-a-secret' -AsPlainText -Force))
            SkipCertificateCheck = $false
            TimeoutSec           = 100
            UserName             = 'tester'
            UserOid              = '00000000-0000-0000-0000-000000000002'
            ConnectedAt          = Get-Date
        }
    }
}

function Clear-TestSession {
    InModuleScope midPointTools { $script:midPointSession = $null }
}

function New-TestResponse {
    param(
        [int] $StatusCode = 200,
        [string] $Json,
        [hashtable] $Headers = @{}
    )
    [pscustomobject]@{
        StatusCode = $StatusCode
        Headers    = $Headers
        Body       = if ($Json) { $Json | ConvertFrom-Json } else { $null }
    }
}

$script:TestRoutes = [System.Collections.Generic.List[object]]::new()

function Reset-TestRoute { $script:TestRoutes.Clear() }

function Add-TestRoute {
    # Pattern is a regex matched against "<METHOD> <path after /ws/rest/>".
    # Response is a response object, or a scriptblock (gets $Body) that returns one.
    # Several responses for one route are returned in order; the last one repeats.
    param(
        [Parameter(Mandatory)] [string] $Pattern,
        [Parameter(Mandatory)] [object[]] $Response
    )
    $script:TestRoutes.Insert(0, [pscustomobject]@{ Pattern = $Pattern; Responses = $Response; Calls = 0 })
}

function Invoke-TestRoute {
    param([string] $Method, [string] $Uri, [string] $Body)

    $path = $Uri -replace '^https?://[^/]+/(.*/)?ws/rest/', ''
    $key = "$Method $path"
    foreach ($route in $script:TestRoutes) {
        if ($key -match $route.Pattern) {
            $index = [Math]::Min($route.Calls, $route.Responses.Count - 1)
            $route.Calls++
            $r = $route.Responses[$index]
            if ($r -is [scriptblock]) { return & $r $Body }
            return $r
        }
    }
    throw "No test route for '$key'"
}

function Get-TestUserJson {
    param(
        [string] $Oid = $script:UserOid,
        [string] $Name = 'jack',
        [string] $Assignments = '[]',
        [string] $LinkRefs = '[]',
        [string] $Activation = '{ "administrativeStatus": "enabled", "effectiveStatus": "enabled" }'
    )
    @"
{ "user": {
    "oid": "$Oid",
    "name": "$Name",
    "fullName": "Jack Sparrow",
    "givenName": "Jack",
    "familyName": "Sparrow",
    "emailAddress": "jack@example.com",
    "activation": $Activation,
    "assignment": $Assignments,
    "linkRef": $LinkRefs
} }
"@
}

function Get-TestSearchJson {
    param([string[]] $Objects)
    $inner = if ($Objects) { $Objects -join ',' } else { '' }
    @"
{ "@ns": "http://prism.evolveum.com/xml/ns/public/types-3",
  "object": { "@type": "http://midpoint.evolveum.com/xml/ns/public/common/api-types-3#ObjectListType",
              "object": [ $inner ] } }
"@
}
