function Wait-midPointShadow {
    <#
    .SYNOPSIS
    Waits until a midPoint user's account exists on a resource, optionally with expected attribute values.

    .DESCRIPTION
    Polls Get-midPointShadow until a live shadow on the resource exists and every attribute in
    -Attribute has the expected value, then returns the shadow. Stops with an error after
    -TimeoutSeconds, showing what was found last.
    Attribute names are the resource attribute names without namespace prefix (e.g. mail, not ri:mail).
    A multi-valued attribute matches when it contains all expected values. String comparison is
    case-insensitive.

    .PARAMETER User
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Resource
    The resource: name, OID, or an object with an Oid property.

    .PARAMETER Attribute
    Expected attribute values, e.g. @{ mail = 'jack@example.com'; department = 'IT' }.
    Use $null as value to wait until an attribute is empty.

    .PARAMETER Kind
    Only shadows of this kind (account, entitlement, generic).

    .PARAMETER Intent
    Only shadows with this intent.

    .PARAMETER NoFetch
    Compare midPoint's cached values instead of reading the resource each time.

    .PARAMETER TimeoutSeconds
    How long to wait. Default 120.

    .PARAMETER IntervalSeconds
    Time between checks. Default 5.

    .EXAMPLE
    Wait-midPointShadow jack -Resource 'Some Resource'

    .EXAMPLE
    Wait-midPointShadow $u -Resource 'Some Resource' -Attribute @{ mail = $u.EmailAddress } -TimeoutSeconds 300
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.Shadow')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Identity')]
        [object] $User,

        [Parameter(Mandatory, Position = 1)]
        [object] $Resource,

        [hashtable] $Attribute,

        [ValidateSet('account', 'entitlement', 'generic')]
        [string] $Kind,

        [string] $Intent,

        [switch] $NoFetch,

        [ValidateRange(1, 86400)]
        [int] $TimeoutSeconds = 120,

        [ValidateRange(1, 3600)]
        [int] $IntervalSeconds = 5
    )

    begin {
        # Resolve once, so a wrong resource name fails immediately instead of after the timeout.
        $resourceOid = Resolve-midPointObjectOid -InputObject $Resource -Type resources
    }

    process {
        $userOid = Resolve-midPointObjectOid -InputObject $User -Type users
        $label = Get-midPointIdentityLabel $User
        $params = @{ User = $userOid; Resource = $resourceOid; NoFetch = $NoFetch }
        if ($Kind) { $params.Kind = $Kind }
        if ($Intent) { $params.Intent = $Intent }

        $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
        $lastState = 'no account found'
        while ($true) {
            $shadows = @(Get-midPointShadow @params | Where-Object Exists)
            foreach ($shadow in $shadows) {
                $mismatch = @(Get-midPointAttributeMismatch -Shadow $shadow -Expected $Attribute)
                if ($mismatch.Count -eq 0) {
                    return $shadow
                }
                $lastState = 'account found, but ' + ($mismatch -join '; ')
            }

            if ([datetime]::UtcNow -ge $deadline) { break }
            Write-Verbose "Waiting for account of '$label' on resource $resourceOid ($lastState)"
            Start-Sleep -Seconds $IntervalSeconds
        }

        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.TimeoutException]::new("Timeout after $TimeoutSeconds s waiting for the account of '$label' on resource '$(Get-midPointIdentityLabel $Resource)': $lastState."),
            'midPointShadowWaitTimeout', [System.Management.Automation.ErrorCategory]::OperationTimeout, $User)
        $PSCmdlet.ThrowTerminatingError($record)
    }
}
