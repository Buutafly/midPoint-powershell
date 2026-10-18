$script:midPointOidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

# REST collection -> midPoint type name used in references.
$script:midPointTypeMap = @{
    users     = 'c:UserType'
    roles     = 'c:RoleType'
    orgs      = 'c:OrgType'
    shadows   = 'c:ShadowType'
    resources = 'c:ResourceType'
}

function Get-midPointProperty {
    # Safe property read on a PSCustomObject (returns $null when missing).
    # midPoint sometimes qualifies keys with a namespace prefix, e.g. a reference with a filter comes as
    # { "t:oid": ..., "t:type": ..., "filter": ... }; 'oid' then finds 't:oid'.
    [CmdletBinding()]
    param(
        [AllowNull()] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Name
    )
    if ($null -eq $InputObject) { return $null }
    $p = $InputObject.PSObject.Properties[$Name]
    if (-not $p -and $InputObject -is [System.Management.Automation.PSCustomObject]) {
        $suffix = ':' + $Name
        $p = $InputObject.PSObject.Properties | Where-Object { $_.Name.EndsWith($suffix) -and -not $_.Name.StartsWith('@') } | Select-Object -First 1
    }
    if ($p) { $p.Value }
}

function Get-midPointContainerId {
    # Container ids (e.g. of assignments) come as '@id' in midPoint's JSON; 'id' is accepted as well.
    [CmdletBinding()]
    param([AllowNull()] [object] $InputObject)

    $id = Get-midPointProperty $InputObject '@id'
    if ($null -eq $id) { $id = Get-midPointProperty $InputObject 'id' }
    $id
}

function ConvertFrom-midPointPolyString {
    # midPoint sends PolyStrings either as a plain string or as { orig, norm }.
    [CmdletBinding()]
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    $orig = Get-midPointProperty $Value 'orig'
    if ($null -ne $orig) { return [string]$orig }
    [string]$Value
}

function ConvertFrom-midPointQName {
    # 'org:default', 'c:RoleType' or 'http://...#RoleType' -> 'default' / 'RoleType'.
    [CmdletBinding()]
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    ([string]$Value -split '[#:]')[-1]
}

function ConvertTo-midPointDateTime {
    # [datetime] -> ISO 8601 with offset (midPoint xsd:dateTime). Unspecified kind is treated as local time.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [datetime] $Value)

    ([System.DateTimeOffset]$Value).ToString("yyyy-MM-dd'T'HH:mm:ss.fffzzz", [cultureinfo]::InvariantCulture)
}

function ConvertFrom-midPointDateTime {
    # JSON timestamps may already be [datetime] (ConvertFrom-Json does that) or strings.
    [CmdletBinding()]
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetime]) { return $Value }
    [System.DateTimeOffset]::Parse([string]$Value, [cultureinfo]::InvariantCulture).LocalDateTime
}

function ConvertTo-midPointActivationStatus {
    # 'Enabled' -> 'enabled' (ActivationStatusType values are lower case).
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Value)
    $Value.ToLowerInvariant()
}

function ConvertTo-midPointAxiomString {
    # Quotes a value for an Axiom query: "..." with \ and " escaped.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)
    '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Get-midPointObjectFromResponse {
    # Unwraps the JSON envelope:
    #   single object: { "user": { ... } }
    #   search result: { "@ns": ..., "object": { "@type": "...ObjectListType", "object": [ ... ] } }
    [CmdletBinding()]
    param([AllowNull()] [object] $Body)

    if ($null -eq $Body -or $Body -is [string]) { return }

    $list = Get-midPointProperty $Body 'object'
    if ($null -ne $list -and $list -isnot [string] -and $null -ne $list.PSObject.Properties['object']) {
        foreach ($o in @(Get-midPointProperty $list 'object')) { $o }
        return
    }
    if ($null -ne $list -and "$(Get-midPointProperty $list '@type')" -like '*ObjectListType') {
        return  # empty search result
    }

    $root = @($Body.PSObject.Properties | Where-Object { -not $_.Name.StartsWith('@') })
    if ($root.Count -eq 1) {
        $root[0].Value
    }
    else {
        $Body
    }
}

function Find-midPointObject {
    # POST <type>/search with an Axiom filter. Returns raw objects.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Type,
        [string] $Filter,
        [int] $MaxResults,
        [string[]] $Options
    )

    $query = [ordered]@{}
    if ($Filter) { $query.filter = [ordered]@{ text = $Filter } }
    if ($MaxResults -gt 0) { $query.paging = [ordered]@{ maxSize = $MaxResults } }

    $params = @{
        Method = 'POST'
        Path   = "$Type/search"
        Body   = [ordered]@{ query = $query }
    }
    if ($Options) { $params.Query = @{ options = $Options } }

    $response = Invoke-midPointRestMethod @params
    Get-midPointObjectFromResponse -Body $response.Body
}

function Get-midPointObjectByOid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Type,
        [Parameter(Mandatory)] [string] $Oid,
        [string[]] $Options
    )

    $params = @{
        Method = 'GET'
        Path   = '{0}/{1}' -f $Type, [uri]::EscapeDataString($Oid)
    }
    if ($Options) { $params.Query = @{ options = $Options } }
    $response = Invoke-midPointRestMethod @params
    Get-midPointObjectFromResponse -Body $response.Body
}

function Resolve-midPointObjectOid {
    # The -Identity pattern: accepts an object with an Oid (module output or raw midPoint object),
    # an OID string, or a name. A name is looked up and must match exactly one object.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowNull()] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Type
    )

    if ($null -eq $InputObject -or "$InputObject" -eq '') {
        throw [System.ArgumentException]::new("No $Type identity given.")
    }
    if ($InputObject -isnot [string]) {
        $oid = Get-midPointProperty $InputObject 'Oid'
        if ($oid) { return [string]$oid }
        $InputObject = [string]$InputObject
    }
    if ($InputObject -match $script:midPointOidPattern) {
        return $InputObject
    }

    # A search over resources or shadows must not contact the connectors: without noFetch midPoint
    # completes schema and capabilities of every resource it finds (and reports a partial error when one fails).
    $options = if ($Type -in 'resources', 'shadows') { @('noFetch') } else { @() }
    $found = @(Find-midPointObject -Type $Type -Filter ('name = {0}' -f (ConvertTo-midPointAxiomString $InputObject)) -Options $options)
    if ($found.Count -eq 0) {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.Management.Automation.ItemNotFoundException]::new("No object of type '$Type' with name '$InputObject' found."),
            'midPointObjectNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $InputObject)
        throw $record
    }
    if ($found.Count -gt 1) {
        throw [System.InvalidOperationException]::new("More than one object of type '$Type' has the name '$InputObject'. Use the OID.")
    }
    [string](Get-midPointProperty $found[0] 'oid')
}

function New-midPointItemDelta {
    # One itemDelta of an objectModification. Without -Value a 'replace' clears the item.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory object only.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('add', 'replace', 'delete')]
        [string] $ModificationType,

        [Parameter(Mandatory)] [string] $Path,

        [AllowNull()] [object] $Value
    )

    $delta = [ordered]@{
        modificationType = $ModificationType
        path             = $Path
    }
    if ($PSBoundParameters.ContainsKey('Value') -and $null -ne $Value -and -not ($Value -is [string] -and $Value -eq '')) {
        $values = @($Value)
        $delta.value = if ($values.Count -eq 1) { $values[0] } else { $values }
    }
    $delta
}

function Invoke-midPointModify {
    # PATCH <type>/<oid> with a list of item deltas.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Type,
        [Parameter(Mandatory)] [string] $Oid,
        [Parameter(Mandatory)] [object[]] $ItemDelta
    )

    $body = [ordered]@{ objectModification = [ordered]@{ itemDelta = @($ItemDelta) } }
    $null = Invoke-midPointRestMethod -Method PATCH -Path ('{0}/{1}' -f $Type, [uri]::EscapeDataString($Oid)) -Body $body
}

function Set-midPointNestedValue {
    # 'activation/validTo' = x  ->  $target.activation.validTo = x (creates the dictionaries).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory object only.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Target,
        [Parameter(Mandatory)] [string] $Path,
        [AllowNull()] [object] $Value
    )

    $parts = $Path.Trim('/') -split '/'
    $node = $Target
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if (-not $node.Contains($parts[$i]) -or $node[$parts[$i]] -isnot [System.Collections.IDictionary]) {
            $node[$parts[$i]] = [ordered]@{}
        }
        $node = $node[$parts[$i]]
    }
    $node[$parts[-1]] = $Value
}

function New-midPointActivationDelta {
    # Item deltas for administrativeStatus / validFrom / validTo below $Prefix
    # ('activation' or 'assignment[3]/activation'). Returns an empty list if nothing is set.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an in-memory object only.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Prefix,
        [string] $AdministrativeStatus,
        [object] $ValidFrom,
        [object] $ValidTo,
        [switch] $ClearValidFrom,
        [switch] $ClearValidTo
    )

    if ($ClearValidFrom -and $null -ne $ValidFrom) { throw [System.ArgumentException]::new('Use either -ValidFrom or -ClearValidFrom, not both.') }
    if ($ClearValidTo -and $null -ne $ValidTo) { throw [System.ArgumentException]::new('Use either -ValidTo or -ClearValidTo, not both.') }

    $deltas = [System.Collections.Generic.List[object]]::new()
    if ($AdministrativeStatus) {
        if ($AdministrativeStatus -eq 'None') {
            $deltas.Add((New-midPointItemDelta -ModificationType replace -Path "$Prefix/administrativeStatus"))
        }
        else {
            $deltas.Add((New-midPointItemDelta -ModificationType replace -Path "$Prefix/administrativeStatus" -Value (ConvertTo-midPointActivationStatus $AdministrativeStatus)))
        }
    }
    if ($null -ne $ValidFrom) { $deltas.Add((New-midPointItemDelta -ModificationType replace -Path "$Prefix/validFrom" -Value (ConvertTo-midPointDateTime $ValidFrom))) }
    if ($ClearValidFrom) { $deltas.Add((New-midPointItemDelta -ModificationType replace -Path "$Prefix/validFrom")) }
    if ($null -ne $ValidTo) { $deltas.Add((New-midPointItemDelta -ModificationType replace -Path "$Prefix/validTo" -Value (ConvertTo-midPointDateTime $ValidTo))) }
    if ($ClearValidTo) { $deltas.Add((New-midPointItemDelta -ModificationType replace -Path "$Prefix/validTo")) }
    , $deltas.ToArray()
}

function Get-midPointIdentityLabel {
    # Readable label for ShouldProcess / messages: the Name of a module object, else the string.
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [object] $InputObject)

    if ($null -eq $InputObject) { return '' }
    if ($InputObject -is [string]) { return $InputObject }
    $name = Get-midPointProperty $InputObject 'Name'
    if ($name) { return ConvertFrom-midPointPolyString $name }
    $oid = Get-midPointProperty $InputObject 'Oid'
    if ($oid) { return [string]$oid }
    [string]$InputObject
}
