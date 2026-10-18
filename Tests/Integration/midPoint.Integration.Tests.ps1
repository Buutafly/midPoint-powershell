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
# role), clears the assignment's validTo, removes the assignment and waits until the account is gone.
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
        $script:manual = $false
        if ($env:MIDPOINT_TEST_ROLE -and $env:MIDPOINT_TEST_RESOURCE) {
            $resource = Get-midPointResource $env:MIDPOINT_TEST_RESOURCE
            if (-not $resource) { throw "Test resource '$env:MIDPOINT_TEST_RESOURCE' not found (or not readable for $env:MIDPOINT_USER)." }
            if (-not $resource.ConnectorType) { Write-Warning "The connector of '$($resource.Name)' is not readable for $env:MIDPOINT_USER; treating it as a resource with a real connector." }
            $script:manual = $resource.IsManual
            Write-Host "Test resource '$($resource.Name)': connector $($resource.ConnectorType)$(if ($manual) { ' - manual resource, the test completes the cases of its account' })"
        }
        $script:wait = if ($env:MIDPOINT_SHADOW_TIMEOUT_SEC) { [int]$env:MIDPOINT_SHADOW_TIMEOUT_SEC } else { 180 }

        function Complete-TestCase {
            # Completes the open cases of the test account on the manual resource. Returns how many there were.
            param([string] $Comment)
            $open = @(Get-midPointCase -Resource $env:MIDPOINT_TEST_RESOURCE -Account $script:name -State Open)
            $open | Complete-midPointCase -Comment $Comment
            $open.Count
        }

        function Wait-TestCase {
            # Waits for an open case of the test account (midPoint opens it while processing the change).
            $deadline = [datetime]::UtcNow.AddSeconds($script:wait)
            while ([datetime]::UtcNow -lt $deadline) {
                if (@(Get-midPointCase -Resource $env:MIDPOINT_TEST_RESOURCE -Account $script:name -State Open).Count -gt 0) { return $true }
                Start-Sleep -Seconds 2
            }
            $false
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
                    $cases = @(Get-midPointCase -Resource $env:MIDPOINT_TEST_RESOURCE -Account $script:name)
                    # Reading the shadows lets midPoint record the closed cases (refreshOnRead) before they are deleted.
                    foreach ($oid in @($cases.TargetOid | Where-Object { $_ } | Select-Object -Unique)) {
                        try { $null = & (Get-Module midPointTools) { param($o) Get-midPointObjectByOid -Type shadows -Oid $o } $oid } catch { Write-Verbose "Shadow $oid not readable: $_" }
                    }
                    $cases | Remove-midPointCase -Confirm:$false
                    Write-Host "Cleanup: deleted $($cases.Count) case(s) of $script:name."
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

            $s = Wait-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -TimeoutSeconds $wait -AllowPending:$manual -NoFetch:$manual
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
            $c = @(Get-midPointCase -Resource $env:MIDPOINT_TEST_RESOURCE -Account $name -State Open)
            Write-Host "Open case(s): $(($c | ForEach-Object { "$($_.Name) [$($_.State), work items: $($_.OpenWorkItems), assignee: $($_.WorkItem.Assignee -join ', ')]" }) -join '; ')"
            $c.Count | Should -BeGreaterThan 0
            $c | Complete-midPointCase -Comment 'midPointTools integration test'

            $s = Wait-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -TimeoutSeconds $wait
            Write-Host "Shadow after the case: exists=$($s.Exists), pending=$($s.PendingOperation -join ','), attributes: $(($s.Attributes.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
            $s.Exists | Should -BeTrue
            @(Get-midPointCase -Resource $env:MIDPOINT_TEST_RESOURCE -Account $name -State Open).Count | Should -Be 0
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
            $deadline = [datetime]::UtcNow.AddSeconds($wait)
            while ((Test-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE) -and [datetime]::UtcNow -lt $deadline) {
                Start-Sleep -Seconds 2
            }
            Test-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE | Should -BeFalse
        }
    }
}
