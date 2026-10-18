# Integration tests against a real midPoint test instance. Not run in CI.
# Setting up a test instance (example objects to import): docs/integration-tests.md
#
# Required environment variables (set them locally, never commit values; ./build/Invoke-Tests.ps1 -Integration
# also reads them from Tests/Integration/settings.local.ps1, which git ignores):
#   MIDPOINT_URI       e.g. https://midpoint.example.com/midpoint
#   MIDPOINT_USER      a midPoint user with REST authorizations
#   MIDPOINT_PASSWORD
# Optional:
#   MIDPOINT_SKIP_CERT_CHECK = 1   for self-signed test certificates
#   MIDPOINT_TIMEOUT_SEC           request timeout in seconds (default 30 here)
#   MIDPOINT_TEST_ROLE             a role name to assign / unassign
#   MIDPOINT_TEST_RESOURCE         a resource the role provisions to (needs MIDPOINT_TEST_ROLE)
#   MIDPOINT_SHADOW_TIMEOUT_SEC    how long to wait for the account (default 180)
#
# Run: Invoke-Pester ./Tests/Integration -Tag Integration -Output Detailed
# Creates one user named MPTEST-<random> and deletes it at the end.
# The role and the resource are never changed, only read: the test assigns the role to its own user (validTo in
# 30 days), waits for the account on the resource (needs an inducement with a construction for that resource in the
# role), clears the assignment's validTo, removes the assignment and waits until the account is deleted or disabled.
# On a manual resource (connector type ManualConnector) the account changes are cases: the test then completes the
# cases of its own account like an operator (MIDPOINT_USER must be the resource's operator) and deletes them at the end.
# With a real connector this creates and deletes an account MPTEST-<random> in the target system.

BeforeDiscovery {
    $script:configured = $env:MIDPOINT_URI -and $env:MIDPOINT_USER -and $env:MIDPOINT_PASSWORD
    $script:hasRole = [bool]$env:MIDPOINT_TEST_ROLE
    $script:hasResource = $script:hasRole -and [bool]$env:MIDPOINT_TEST_RESOURCE
}

Describe 'midPoint integration' -Tag 'Integration' -Skip:(-not $configured) {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'midPointTools' 'midPointTools.psd1') -Force
        $password = ConvertTo-SecureString $env:MIDPOINT_PASSWORD -AsPlainText -Force
        $cred = [pscredential]::new($env:MIDPOINT_USER, $password)
        $timeout = if ($env:MIDPOINT_TIMEOUT_SEC) { [int]$env:MIDPOINT_TIMEOUT_SEC } else { 30 }
        Write-Host "Connecting to $env:MIDPOINT_URI as $env:MIDPOINT_USER (timeout $timeout s)..."
        # Test instances often run on http; its only warning (clear-text password) is noise here.
        Connect-midPoint -Uri $env:MIDPOINT_URI -Credential $cred -SkipCertificateCheck:($env:MIDPOINT_SKIP_CERT_CHECK -eq '1') -TimeoutSec $timeout -WarningAction SilentlyContinue
        $script:name = 'MPTEST-{0}' -f (Get-Random -Minimum 100000 -Maximum 999999)
        $script:wait = if ($env:MIDPOINT_SHADOW_TIMEOUT_SEC) { [int]$env:MIDPOINT_SHADOW_TIMEOUT_SEC } else { 180 }

        function Get-TestCase {
            # Cases of one test account on the test resource; with -AnyTestAccount those of every MPTEST- account.
            param([string] $Account = $script:name, [switch] $AnyTestAccount, [string] $State = 'All')
            $pattern = if ($AnyTestAccount) { "*'MPTEST-*'*" } else { "*'$([WildcardPattern]::Escape($Account))'*" }
            @(Get-midPointCase -Resource $env:MIDPOINT_TEST_RESOURCE -State $State) | Where-Object Name -Like $pattern
        }

        function Complete-TestCase {
            # Completes the open cases of the test account on the manual resource. Returns how many there were.
            param([string] $Comment, [string] $Account = $script:name, [switch] $AnyTestAccount)
            $open = @(Get-TestCase -Account $Account -AnyTestAccount:$AnyTestAccount -State Open)
            $open | Complete-midPointCase -Comment $Comment
            $open.Count
        }

        function Remove-TestCase {
            # Deletes the (closed) cases of the test account. Returns how many there were.
            param([string] $Account = $script:name, [switch] $AnyTestAccount)
            $cases = @(Get-TestCase -Account $Account -AnyTestAccount:$AnyTestAccount)
            # Reading the shadows lets midPoint record the closed cases (refreshOnRead) before they are deleted.
            foreach ($oid in @($cases.TargetOid | Where-Object { $_ } | Select-Object -Unique)) {
                try { $null = & (Get-Module midPointTools) { param($o) Get-midPointObjectByOid -Type shadows -Oid $o } $oid } catch { Write-Verbose "Shadow $oid not readable: $_" }
            }
            $cases | Remove-midPointCase -Confirm:$false
            $cases.Count
        }

        function Wait-TestCase {
            # Waits for an open case of the test account (midPoint opens it while processing the change).
            param([int] $TimeoutSeconds = $script:wait)
            $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
            while ([datetime]::UtcNow -lt $deadline) {
                if (@(Get-TestCase -State Open).Count -gt 0) { return $true }
                Start-Sleep -Seconds 2
            }
            $false
        }

        $script:manual = $false
        $script:connectorUnknown = $false
        if ($env:MIDPOINT_TEST_ROLE -and $env:MIDPOINT_TEST_RESOURCE) {
            # -Verbose only to catch the reason when the connector is not readable.
            $out = @(Get-midPointResource $env:MIDPOINT_TEST_RESOURCE -Verbose 4>&1)
            $resource = $out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }
            if (-not $resource) { throw "Test resource '$env:MIDPOINT_TEST_RESOURCE' not found (or not readable for $env:MIDPOINT_USER)." }
            if (-not $resource.ConnectorType) {
                $script:connectorUnknown = $true
                $reason = ($out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like 'Connector * is not readable*' }).Message
                Write-Warning "The connector of '$($resource.Name)' is not readable for $env:MIDPOINT_USER$(if ($reason) { ": $reason" } elseif (-not $resource.ConnectorOid) { ": no connector OID in the resource's connectorRef: $(ConvertTo-Json -InputObject $resource.Raw.connectorRef -Depth 5 -Compress)" })"
                if ($resource.ConnectorOid) {
                    # Probe: the same read without the connector's schema (a large XSD).
                    try {
                        $probe = & (Get-Module midPointTools) { param($o) Invoke-midPointRestMethod -Method GET -Path "connectors/$o" -Query @{ exclude = 'schema' } } $resource.ConnectorOid
                        $type = (& (Get-Module midPointTools) { param($b) Get-midPointObjectFromResponse -Body $b } $probe.Body).connectorType
                        Write-Warning "GET connectors/<oid>?exclude=schema works (connectorType '$type'): the schema in the response is the problem."
                    }
                    catch { Write-Warning "GET connectors/<oid>?exclude=schema fails as well: $($_.Exception.Message)" }
                }
                Write-Warning 'The test decides by the account: pending with an open case means a manual resource.'
            }
            $script:manual = $resource.IsManual
            Write-Host "Test resource '$($resource.Name)': connector $($resource.ConnectorType)$(if ($manual) { ' - manual resource, the test completes the cases of its account' })"
        }

        # Leftovers of an aborted run (Ctrl+C skips AfterAll): MPTEST- users and the cases of their accounts.
        $stale = @(Get-midPointUser -Filter 'name startsWith "MPTEST-"')
        if ($stale.Count -gt 0 -or $env:MIDPOINT_TEST_RESOURCE) {
            try {
                $completed = 0
                if ($env:MIDPOINT_TEST_RESOURCE) { $completed += Complete-TestCase -AnyTestAccount -Comment 'midPointTools integration test: leftover' }
                $stale | Remove-midPointUser -Confirm:$false
                if ($env:MIDPOINT_TEST_RESOURCE) {
                    # Deleting a user may open a case to delete its account.
                    $completed += Complete-TestCase -AnyTestAccount -Comment 'midPointTools integration test: leftover'
                    $removed = Remove-TestCase -AnyTestAccount
                }
                if ($stale.Count -or $completed -or $removed) {
                    Write-Host "Leftovers of an earlier run: deleted $($stale.Count) user(s) ($(($stale.Name) -join ', ')), completed $completed and deleted $removed case(s)."
                }
            }
            catch { Write-Warning "Leftovers of an earlier run could not be cleared: $_" }
        }
    }

    AfterAll {
        # Skip the cleanup when Connect-midPoint failed, so its error is the only one shown.
        if ($script:name -and (Get-midPointSession)) {
            if ($script:manual) {
                # A failed run can leave cases open; complete them so midPoint keeps no pending operations.
                try { $null = Complete-TestCase -Comment 'midPointTools integration test cleanup' }
                catch { Write-Warning "Cleanup: completing open cases failed: $_" }
            }
            Get-midPointUser $script:name | Remove-midPointUser -Confirm:$false
            if ($script:manual) {
                try {
                    # Deleting the user may open a case to delete the account.
                    $null = Complete-TestCase -Comment 'midPointTools integration test cleanup'
                    $count = Remove-TestCase
                    Write-Host "Cleanup: deleted $count case(s) of $script:name."
                }
                catch { Write-Warning "Cleanup: cases of $script:name could not be cleared: $_" }
            }
            Disconnect-midPoint
        }
    }

    It 'connected (GET /self)' {
        (Get-midPointSession).UserOid | Should -Not -BeNullOrEmpty
    }

    It 'creates a user (OID from the Location header)' {
        $script:user = New-midPointUser -Name $name -GivenName 'Test' -FamilyName 'User' -EmailAddress "$name@example.com" -PassThru
        $user.Oid | Should -Match '^[0-9a-f-]{36}$'
        $user.Name | Should -Be $name
    }

    It 'finds the user by name (search with an Axiom text filter)' {
        (Get-midPointUser $name).Oid | Should -Be $user.Oid
        @(Get-midPointUser -Filter ('name startsWith "{0}"' -f $name)).Count | Should -Be 1
    }

    It 'returns nothing for an unknown name' {
        Get-midPointUser "$name-does-not-exist" | Should -BeNullOrEmpty
    }

    It 'reports a missing OID as ObjectNotFound with a message' {
        $err = $null
        try { Get-midPointUser -Oid '00000000-0000-0000-0000-00000000dead' } catch { $err = $_ }
        $err.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $err.Exception.Message | Should -Match 'HTTP 404'
    }

    It 'changes properties' {
        $u = Set-midPointUser $user -Description 'midPointTools integration test' -PassThru
        $u.Description | Should -Be 'midPointTools integration test'
    }

    It 'disables and enables the user' {
        (Disable-midPointUser $user -PassThru).EffectiveStatus | Should -Be 'disabled'
        (Enable-midPointUser $user -PassThru).EffectiveStatus | Should -Be 'enabled'
    }

    It 'sets and clears validity' {
        $a = Set-midPointUserActivation $user -AdministrativeStatus None -ValidTo (Get-Date).AddDays(-1) -PassThru
        $a.EffectiveStatus | Should -Be 'disabled'
        $a.ValidityStatus | Should -Be 'after'
        $a = Set-midPointUserActivation $user -ClearValidTo -PassThru
        $a.ValidTo | Should -BeNullOrEmpty
        $a.EffectiveStatus | Should -Be 'enabled'
    }

    Context 'Role assignment' -Skip:(-not $hasRole) {
        It 'assigns the role with validTo' {
            $a = Add-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE -ValidTo (Get-Date).AddDays(30) -PassThru
            @($a).Count | Should -Be 1
            $a.ValidTo | Should -Not -BeNullOrEmpty
        }

        It 'shows the account on the resource' -Skip:(-not $hasResource) {
            Write-Host "Waiting up to $wait s for the account on '$env:MIDPOINT_TEST_RESOURCE'$(if ($manual) { ' (manual resource: a pending account counts)' })..."

            # With an unreadable connector a pending account is accepted too; an open case for it marks a manual resource.
            $detect = $manual -or $connectorUnknown
            $s = Wait-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -TimeoutSeconds $wait -AllowPending:$detect -NoFetch:$detect
            if ($connectorUnknown -and -not $manual) {
                if ($s.IsPending -and -not $s.Exists -and (Wait-TestCase -TimeoutSeconds 10)) {
                    $script:manual = $true
                    Write-Host 'The account is pending with an open case: treating the test resource as manual.'
                }
                else {
                    # A real connector: wait for the account itself and read it from the resource.
                    $s = Wait-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -TimeoutSeconds $wait
                }
            }
            Write-Host "Found shadow $($s.Oid): exists=$($s.Exists), pending=$($s.PendingOperation -join ','), attributes: $(($s.Attributes.Keys | Sort-Object) -join ', ')"
            if ($manual) {
                ($s.Exists -or $s.IsPending) | Should -BeTrue
            }
            else {
                $s.Exists | Should -BeTrue
                $s.Attributes.Count | Should -BeGreaterThan 0
            }
            Test-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -AllowPending:$manual -NoFetch:$manual | Should -BeTrue
        }

        It 'completes the case and the account exists (manual resource)' -Skip:(-not $hasResource) {
            if (-not $manual) { Set-ItResult -Skipped -Because 'the test resource has a real connector'; return }
            $c = @(Get-TestCase -State Open)
            Write-Host "Open case(s): $(($c | ForEach-Object { "$($_.Name) [$($_.State), work items: $($_.OpenWorkItems), assignee: $($_.WorkItem.Assignee -join ', ')]" }) -join '; ')"
            $c.Count | Should -BeGreaterThan 0
            $c | Complete-midPointCase -Comment 'midPointTools integration test'

            $s = Wait-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -TimeoutSeconds $wait
            Write-Host "Shadow after the case: exists=$($s.Exists), pending=$($s.PendingOperation -join ','), attributes: $(($s.Attributes.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
            $s.Exists | Should -BeTrue
            @(Get-TestCase -State Open).Count | Should -Be 0
        }

        It 'changes the assignment validity' {
            $a = Set-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE -ClearValidTo -PassThru
            $a.ValidTo | Should -BeNullOrEmpty
        }

        It 'removes the role' {
            Remove-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE -Confirm:$false
            Get-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE | Should -BeNullOrEmpty
        }

        It 'removes the account' -Skip:(-not $hasResource) {
            if ($manual) {
                Wait-TestCase | Should -BeTrue -Because 'removing the role opens a case to delete the account'
                Complete-TestCase -Comment 'midPointTools integration test' | Should -BeGreaterThan 0
            }
            # Depending on the resource, midPoint deletes the account or only disables it when the role is removed.
            Write-Host "Waiting up to $wait s until the account is deleted or disabled..."
            $started = [datetime]::UtcNow
            $state = $null
            while ($true) {
                $live = @(Get-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE)
                $state = if ($live.Count -eq 0) { 'deleted' }
                elseif (@($live | Where-Object AdministrativeStatus -EQ 'disabled').Count -eq $live.Count) { 'disabled' }
                $elapsed = [int]([datetime]::UtcNow - $started).TotalSeconds
                if ($state -or $elapsed -ge $wait) { break }
                Write-Progress -Activity "Waiting for the account of $name to be removed" -Status "still active ($elapsed of $wait s)" -PercentComplete ([Math]::Min(100, 100 * $elapsed / $wait))
                Start-Sleep -Seconds 2
            }
            Write-Progress -Activity "Waiting for the account of $name to be removed" -Completed
            $info = if ($state) { $state } else { "still active: $(($live | ForEach-Object { "$($_.Name) (exists=$($_.Exists), status=$($_.AdministrativeStatus))" }) -join ', ')" }
            Write-Host "Account after removing the role: $info"
            $state | Should -Not -BeNullOrEmpty -Because 'midPoint deletes or disables the account when the role is removed'
        }
    }
}
