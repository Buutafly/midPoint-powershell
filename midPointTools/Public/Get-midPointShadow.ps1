function Get-midPointShadow {
    <#
    .SYNOPSIS
    Gets the accounts (shadows) of a midPoint user on its resources.

    .DESCRIPTION
    Follows the user's linkRefs and reads each shadow. By default midPoint fetches the current
    attribute values from the resource; -NoFetch returns what midPoint has cached instead (faster,
    and works when the resource is down). Dead shadows (deleted accounts) are skipped unless
    -IncludeDead is given.

    .PARAMETER User
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Resource
    Only accounts on this resource: name, OID, or an object with an Oid property.

    .PARAMETER Kind
    Only shadows of this kind (account, entitlement, generic).

    .PARAMETER Intent
    Only shadows with this intent.

    .PARAMETER NoFetch
    Do not read from the resource; return midPoint's cached values.

    .PARAMETER IncludeDead
    Also return dead shadows.

    .EXAMPLE
    Get-midPointShadow jack -Resource 'Some Resource'

    .EXAMPLE
    (Get-midPointShadow jack -Resource 'Some Resource').Attributes.mail
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.Shadow')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Identity')]
        [object] $User,

        [Parameter(Position = 1)]
        [object] $Resource,

        [ValidateSet('account', 'entitlement', 'generic')]
        [string] $Kind,

        [string] $Intent,

        [switch] $NoFetch,

        [switch] $IncludeDead
    )

    begin {
        $resourceOid = if ($PSBoundParameters.ContainsKey('Resource')) { Resolve-midPointObjectOid -InputObject $Resource -Type resources } else { $null }
        $options = @('resolveNames')
        if ($NoFetch) { $options += 'noFetch' }
    }

    process {
        $userOid = Resolve-midPointObjectOid -InputObject $User -Type users
        $userObject = Get-midPointObjectByOid -Type users -Oid $userOid

        foreach ($link in @(Get-midPointProperty $userObject 'linkRef')) {
            $shadowOid = Get-midPointProperty $link 'oid'
            if (-not $shadowOid) { continue }

            try {
                $raw = Get-midPointObjectByOid -Type shadows -Oid $shadowOid -Options $options
            }
            catch {
                # A link can point to a shadow that was deleted in the meantime.
                if ($_.Exception.Data['StatusCode'] -eq 404) {
                    Write-Verbose "Shadow $shadowOid of user $userOid no longer exists."
                    continue
                }
                throw
            }

            $shadow = ConvertTo-midPointShadowObject -InputObject $raw -User $userObject
            if ($resourceOid -and $shadow.ResourceOid -ne $resourceOid) { continue }
            if ($Kind -and $shadow.Kind -ne $Kind) { continue }
            if ($Intent -and $shadow.Intent -ne $Intent) { continue }
            if ($shadow.Dead -and -not $IncludeDead) { continue }
            $shadow
        }
    }
}
