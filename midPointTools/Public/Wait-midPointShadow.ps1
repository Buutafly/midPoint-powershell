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

    .PARAMETER AllowPending
    Also accept an account that midPoint has requested but not yet created, e.g. on a manual resource
    (open case) or while an approval is pending. Attributes are then compared with the requested values.

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

        [switch] $AllowPending,

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

        $resourceLabel = Get-midPointIdentityLabel $Resource
        $activity = "Waiting for the account of '$label' on '$resourceLabel'"
        $started = [datetime]::UtcNow
        $deadline = $started.AddSeconds($TimeoutSeconds)
        $lastState = 'no account found'
        try {
            while ($true) {
                $all = @(Get-midPointShadow @params)
                $shadows = @($all | Where-Object { $_.Exists -or ($AllowPending -and $_.IsPending) })
                foreach ($shadow in $shadows) {
                    $mismatch = @(Get-midPointAttributeMismatch -Shadow $shadow -Expected $Attribute)
                    if ($mismatch.Count -eq 0) {
                        return $shadow
                    }
                    $lastState = 'account found, but ' + ($mismatch -join '; ')
                }
                if ($shadows.Count -eq 0 -and @($all | Where-Object IsPending).Count -gt 0) {
                    $lastState = 'the account is only requested (pending ' + ((@($all | Where-Object IsPending)[0].PendingOperation) -join ', ') +
                        '), e.g. an open case on a manual resource or a pending approval; use -AllowPending to accept it'
                }

                $now = [datetime]::UtcNow
                if ($now -ge $deadline) { break }
                $elapsed = [int]($now - $started).TotalSeconds
                Write-Progress -Activity $activity -Status "$lastState ($elapsed of $TimeoutSeconds s)" -PercentComplete ([Math]::Min(100, 100 * $elapsed / $TimeoutSeconds))
                Write-Verbose "$activity ($lastState)"
                Start-Sleep -Seconds $IntervalSeconds
            }
        }
        finally {
            Write-Progress -Activity $activity -Completed
        }

        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.TimeoutException]::new("Timeout after $TimeoutSeconds s waiting for the account of '$label' on resource '$resourceLabel': $lastState."),
            'midPointShadowWaitTimeout', [System.Management.Automation.ErrorCategory]::OperationTimeout, $User)
        $PSCmdlet.ThrowTerminatingError($record)
    }
}
