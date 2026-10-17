function Test-midPointShadow {
    <#
    .SYNOPSIS
    Tests whether a midPoint user has an account on a resource.

    .DESCRIPTION
    Returns $true when Get-midPointShadow finds at least one live shadow for the user on the
    resource (optionally of the given kind and intent), otherwise $false. An account that is only
    requested (pending operation) counts only with -AllowPending.

    .PARAMETER User
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Resource
    The resource: name, OID, or an object with an Oid property.

    .PARAMETER Kind
    Only shadows of this kind (account, entitlement, generic).

    .PARAMETER Intent
    Only shadows with this intent.

    .PARAMETER NoFetch
    Use midPoint's cached shadow instead of reading the resource.

    .PARAMETER AllowPending
    Also count an account that midPoint has requested but not yet created, e.g. on a manual resource
    (open case) or while an approval is pending.

    .EXAMPLE
    if (-not (Test-midPointShadow jack -Resource 'Some Resource')) { throw 'Account missing' }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Identity')]
        [object] $User,

        [Parameter(Mandatory, Position = 1)]
        [object] $Resource,

        [ValidateSet('account', 'entitlement', 'generic')]
        [string] $Kind,

        [string] $Intent,

        [switch] $NoFetch,

        [switch] $AllowPending
    )

    process {
        $params = @{ User = $User; Resource = $Resource; NoFetch = $NoFetch }
        if ($Kind) { $params.Kind = $Kind }
        if ($Intent) { $params.Intent = $Intent }
        @(Get-midPointShadow @params | Where-Object { $_.Exists -or ($AllowPending -and $_.IsPending) }).Count -gt 0
    }
}
