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
#   MIDPOINT_TEST_ORG              an org name to assign / unassign (as member and as manager)
#   MIDPOINT_TEST_EXTENSION_ITEM   a single-valued string extension item of UserType (local name, e.g. costCenter)
#
# Run: Invoke-Pester ./Tests/Integration -Tag Integration -Output Detailed
# Creates one user named MPTEST-<random> and deletes it at the end (plus MPTEST-<random>-PW / -EXT for the password
# and extension tests, deleted right away, and MPTEST-<random>-RCA / -RCB with the test role for the recompute test).
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
    $script:hasExtension = [bool]$env:MIDPOINT_TEST_EXTENSION_ITEM
    $script:hasOrg = [bool]$env:MIDPOINT_TEST_ORG
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

        function Get-ModuleProperty {
            # The module's prefix-tolerant property read ('oid' also finds 't:oid').
            param($InputObject, [string] $Name)
            & (Get-Module midPointTools) { param($o, $n) Get-midPointProperty $o $n } $InputObject $Name
        }

        function Format-Json {
            # Raw JSON for the run output, so one run shows what midPoint sends.
            param($InputObject)
            if ($null -eq $InputObject) { return '<none>' }
            ConvertTo-Json -InputObject $InputObject -Depth 10 -Compress
        }

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
            param([int] $TimeoutSeconds = $script:wait, [string] $Account = $script:name)
            # Checks at least once (-TimeoutSeconds 0 only looks).
            $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
            do {
                if (@(Get-TestCase -Account $Account -State Open).Count -gt 0) { return $true }
                if ([datetime]::UtcNow -ge $deadline) { break }
                Start-Sleep -Seconds 2
            } while ($true)
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
            $script:resourceName = $resource.Name
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
                    Write-Host "Leftovers of an earlier run: deleted $($stale.Count) user(s)$(if ($stale.Count) { " ($($stale.Name -join ', '))" }), completed $completed and deleted $removed case(s)."
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
            Get-midPointUser -Filter ('name startsWith "{0}"' -f $script:name) | Remove-midPointUser -Confirm:$false
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

    It 'creates a user with an initial password (credentials/password/value/clearValue)' {
        # A second user, so a rejected password does not break the other tests. No login check: MPTEST- users
        # have no REST rights.
        $secret = ConvertTo-SecureString ('Mp1!' + [guid]::NewGuid().ToString('N').Substring(0, 16)) -AsPlainText -Force
        $u = New-midPointUser -Name "$name-PW" -Password $secret -PassThru
        try {
            $password = Get-ModuleProperty (Get-ModuleProperty $u.Raw 'credentials') 'password'
            # Only the item names, never the (encrypted or hashed) value.
            Write-Host "credentials/password of $($u.Name): items [$(@($password.PSObject.Properties.Name) -join ', ')], value items [$(@((Get-ModuleProperty $password 'value').PSObject.Properties.Name) -join ', ')]"
            $password | Should -Not -BeNullOrEmpty -Because 'midPoint stores the initial password'
        }
        finally { $u | Remove-midPointUser -Confirm:$false }
    }

    It 'sets an extension item on create and change (MIDPOINT_TEST_EXTENSION_ITEM)' -Skip:(-not $hasExtension) {
        $item = $env:MIDPOINT_TEST_EXTENSION_ITEM
        $u = New-midPointUser -Name "$name-EXT" -Property @{ "extension/$item" = 'mptest-1' } -PassThru
        try {
            Write-Host "extension after create: $(Format-Json (Get-ModuleProperty $u.Raw 'extension'))"
            Get-ModuleProperty (Get-ModuleProperty $u.Raw 'extension') $item | Should -Be 'mptest-1'
            $u.Extension[$item] | Should -Be 'mptest-1' -Because 'the user object has the Extension property'

            $u = Set-midPointUser $u -Replace @{ "extension/$item" = 'mptest-2' } -PassThru
            Write-Host "extension after replace: $(Format-Json (Get-ModuleProperty $u.Raw 'extension'))"
            $u.Extension[$item] | Should -Be 'mptest-2'

            $u = Set-midPointUser $u -Replace @{ "extension/$item" = '' } -PassThru
            $u.Extension[$item] | Should -BeNullOrEmpty
        }
        finally { $u | Remove-midPointUser -Confirm:$false }
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

    Context 'Org assignment' -Skip:(-not $hasOrg) {
        BeforeAll {
            $script:org = Get-midPointOrg $env:MIDPOINT_TEST_ORG
            if (-not $org) {
                # A search hides objects the user may not read; a GET by OID tells "missing" (404) from "not
                # allowed" (403 / 500 Access denied). The OID is the one of the example org 050-org-test.xml.
                $exampleOid = '6d707400-0000-4000-8000-000000000005'
                try {
                    $byOid = Get-midPointOrg -Oid $exampleOid
                    Write-Warning "Search for '$env:MIDPOINT_TEST_ORG' found nothing, but GET orgs/$exampleOid works: '$($byOid.Name)'. Check MIDPOINT_TEST_ORG."
                }
                catch { Write-Warning "Search for '$env:MIDPOINT_TEST_ORG' found nothing; GET orgs/$exampleOid fails: $($_.Exception.Message)" }
            }
        }

        It 'finds the org' {
            $org | Should -Not -BeNullOrEmpty -Because "the test org '$env:MIDPOINT_TEST_ORG' must exist and be readable"
            Write-Host "Test org: $($org.Name) (identifier $($org.Identifier))"
        }

        It 'assigns the org as member' {
            if (-not $org) { Set-ItResult -Skipped -Because 'the test org is not found (see the warning above)'; return }
            $a = @(Add-midPointOrgAssignment $user -Org $org -PassThru)
            $a.Count | Should -Be 1
            $a[0].Org | Should -Be $org.Name -Because 'resolveNames fills targetRef.targetName'
            $a[0].Relation | Should -Be 'default'
        }

        It 'assigns the org as manager with validTo' {
            if (-not $org) { Set-ItResult -Skipped -Because 'the test org is not found (see the warning above)'; return }
            Add-midPointOrgAssignment $user -Org $org -Relation manager -ValidTo (Get-Date).AddDays(30)
            $a = @(Get-midPointOrgAssignment $user -Org $org)
            Write-Host "Org assignments: $(($a | ForEach-Object { "$($_.Relation) (id $($_.AssignmentId), validTo $($_.ValidTo))" }) -join '; ')"
            Write-Host "parentOrgRef of the user: $(Format-Json @(Get-ModuleProperty (Get-midPointUser -Oid $user.Oid).Raw 'parentOrgRef'))"
            @($a.Relation | Sort-Object) | Should -Be @('default', 'manager')
            ($a | Where-Object Relation -EQ 'manager').ValidTo | Should -Not -BeNullOrEmpty
        }

        It 'changes the validity of the manager assignment only' {
            if (-not $org) { Set-ItResult -Skipped -Because 'the test org is not found (see the warning above)'; return }
            $m = Get-midPointOrgAssignment $user -Org $org | Where-Object Relation -EQ 'manager'
            $m | Should -Not -BeNullOrEmpty -Because 'the manager assignment was added before'
            $a = $m | Set-midPointOrgAssignment -ClearValidTo -PassThru
            $a.AssignmentId | Should -Be $m.AssignmentId
            $a.ValidTo | Should -BeNullOrEmpty
        }

        It 'removes only the manager assignment' {
            if (-not $org) { Set-ItResult -Skipped -Because 'the test org is not found (see the warning above)'; return }
            Get-midPointOrgAssignment $user -Org $org | Where-Object Relation -EQ 'manager' | Remove-midPointOrgAssignment -Confirm:$false
            @(Get-midPointOrgAssignment $user -Org $org).Relation | Should -Be @('default')
        }

        It 'removes the org' {
            if (-not $org) { Set-ItResult -Skipped -Because 'the test org is not found (see the warning above)'; return }
            Remove-midPointOrgAssignment $user -Org $org -Confirm:$false
            Get-midPointOrgAssignment $user -Org $org | Should -BeNullOrEmpty
        }
    }

    Context 'Role assignment' -Skip:(-not $hasRole) {
        It 'assigns the role with validTo' {
            # -Relation default sends targetRef { type: 'c:RoleType', relation: 'org:default' } (prefixed QNames).
            $a = Add-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE -Relation default -ValidTo (Get-Date).AddDays(30) -PassThru
            @($a).Count | Should -Be 1
            $a.ValidTo | Should -Not -BeNullOrEmpty
        }

        It 'reads the assignment with resolveNames and prefixed references' {
            $a = Get-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE
            Write-Host "Assignment targetRef as midPoint returns it: $(Format-Json (Get-ModuleProperty $a.Raw 'targetRef'))"
            $a.Relation | Should -Be 'default'
            $a.Role | Should -Be (Get-midPointRole $env:MIDPOINT_TEST_ROLE).Name -Because 'resolveNames fills targetRef.targetName'
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

        It 'reads the account with resolveNames and shows the raw attributes' -Skip:(-not $hasResource) {
            foreach ($noFetch in $false, $true) {
                $s = Get-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -NoFetch:$noFetch
                Write-Host "Shadow$(if ($noFetch) { ' (noFetch)' }): resourceRef $(Format-Json (Get-ModuleProperty $s.Raw 'resourceRef'))"
                Write-Host "Shadow$(if ($noFetch) { ' (noFetch)' }): attributes $(Format-Json (Get-ModuleProperty $s.Raw 'attributes'))"
                $s.Resource | Should -Be $resourceName -Because 'resolveNames fills resourceRef.targetName'
                # With noFetch the attributes are midPoint's cache, which may be empty.
                if (-not $noFetch) { $s.Attributes.Count | Should -BeGreaterThan 0 }
            }
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
            $script:accountState = $state
            $state | Should -Not -BeNullOrEmpty -Because 'midPoint deletes or disables the account when the role is removed'
        }

        It 'keeps the deleted account as a dead shadow (Get-midPointShadow -IncludeDead)' -Skip:(-not $hasResource) {
            if ($accountState -ne 'deleted') { Set-ItResult -Skipped -Because "the account was not deleted ($accountState)"; return }
            $u = Get-midPointUser -Oid $user.Oid
            Write-Host "linkRef of the user after the delete: $(Format-Json @(Get-ModuleProperty $u.Raw 'linkRef'))"
            $all = @(Get-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -IncludeDead -NoFetch)
            foreach ($s in $all) {
                $raw = $s.Raw
                Write-Host "Shadow $($s.Oid): dead=$(Get-ModuleProperty $raw 'dead'), exists=$(Get-ModuleProperty $raw 'exists'), pending=$(Format-Json @(Get-ModuleProperty $raw 'pendingOperation' | ForEach-Object { [ordered]@{ executionStatus = (Get-ModuleProperty $_ 'executionStatus'); resultStatus = (Get-ModuleProperty $_ 'resultStatus'); changeType = (Get-ModuleProperty (Get-ModuleProperty $_ 'delta') 'changeType') } }))"
            }
            if ($all.Count -eq 0) {
                Set-ItResult -Inconclusive -Because 'midPoint no longer links a shadow of the deleted account to the user'
                return
            }
            @($all | Where-Object Dead).Count | Should -BeGreaterThan 0 -Because 'the deleted account is kept as a dead shadow'
            @(Get-midPointShadow $user -Resource $env:MIDPOINT_TEST_RESOURCE -NoFetch) | Should -BeNullOrEmpty -Because 'without -IncludeDead dead shadows are skipped'
        }
    }

    Context 'Recompute' {
        It 'recomputes the user (Invoke-midPointRecompute, PATCH with options=reconcile)' {
            $u = Invoke-midPointRecompute $user -PassThru
            $u.Oid | Should -Be $user.Oid
        }

        It 'accepts an empty modification without reconcile (printed)' {
            # Not offered as a cmdlet option (yet): shows whether midPoint accepts it at all.
            $r = & (Get-Module midPointTools) { param($o) Invoke-midPointRestMethod -Method PATCH -Path "users/$o" -Body ([ordered]@{ objectModification = [ordered]@{} }) } $user.Oid
            Write-Host "PATCH users/<oid> with an empty modification, no options: HTTP $($r.StatusCode)$(if ($r.Body) { ", body $(Format-Json $r.Body)" })"
            [int]$r.StatusCode | Should -BeLessThan 300
        }
    }

    Context 'Recompute applies an assignment that became valid' -Skip:(-not $hasResource) {
        # An account cannot be deleted while it is assigned (run 12: HTTP 409 "... while it is assigned violates an
        # assignment policy"). Instead: the role is assigned with validFrom a few seconds ahead; when that time has
        # passed, only a recompute (or midPoint's validity scanner task) creates the account.
        BeforeAll {
            $script:rcNames = @("$name-RCA", "$name-RCB")
            $script:rcValidFrom = (Get-Date).AddSeconds(20)
            $script:rcUsers = foreach ($n in $rcNames) {
                $u = New-midPointUser -Name $n -GivenName 'Test' -FamilyName 'Recompute' -EmailAddress "$n@example.com" -PassThru
                Add-midPointRoleAssignment $u -Role $env:MIDPOINT_TEST_ROLE -ValidFrom $rcValidFrom
                $u
            }

            function Test-RcAccount {
                # True when midPoint has started to create the account: an open case (manual resource) or a shadow.
                param([string] $Account, [object] $User, [int] $TimeoutSeconds = 15)
                if ($manual) { return (Wait-TestCase -Account $Account -TimeoutSeconds $TimeoutSeconds) }
                @(Get-midPointShadow $User -Resource $env:MIDPOINT_TEST_RESOURCE -NoFetch).Count -gt 0
            }
        }

        AfterAll {
            for ($i = 0; $i -lt @($script:rcUsers).Count; $i++) {
                try {
                    if ($manual) { $null = Complete-TestCase -Account $rcNames[$i] -Comment 'midPointTools integration test cleanup' }
                    $rcUsers[$i] | Remove-midPointUser -Confirm:$false
                    if ($manual) {
                        $null = Complete-TestCase -Account $rcNames[$i] -Comment 'midPointTools integration test cleanup'
                        $null = Remove-TestCase -Account $rcNames[$i]
                    }
                }
                catch { Write-Warning "Cleanup of $($rcNames[$i]) failed: $_" }
            }
        }

        It 'has no account while the assignment is not yet valid' {
            for ($i = 0; $i -lt $rcUsers.Count; $i++) {
                $s = @(Get-midPointShadow $rcUsers[$i] -Resource $env:MIDPOINT_TEST_RESOURCE -NoFetch)
                $c = @(if ($manual) { Get-TestCase -Account $rcNames[$i] })
                Write-Host "$($rcNames[$i]) before validFrom: $($s.Count) shadow(s), $($c.Count) case(s)"
                $s.Count + $c.Count | Should -Be 0 -Because 'an assignment that is not yet valid gives no account'
            }
        }

        It 'empty modification without reconcile (printed: does it create the account?)' {
            $sleep = [int][Math]::Ceiling(($rcValidFrom - (Get-Date)).TotalSeconds) + 2
            if ($sleep -gt 0) { Start-Sleep -Seconds $sleep }
            $r = & (Get-Module midPointTools) { param($o) Invoke-midPointRestMethod -Method PATCH -Path "users/$o" -Body ([ordered]@{ objectModification = [ordered]@{} }) } $rcUsers[0].Oid
            $created = Test-RcAccount -Account $rcNames[0] -User $rcUsers[0]
            Write-Host "Without reconcile ($($rcNames[0])): HTTP $($r.StatusCode), account requested: $created"
            [int]$r.StatusCode | Should -BeLessThan 300
        }

        It 'creates the account with Invoke-midPointRecompute (reconcile)' {
            if (Test-RcAccount -Account $rcNames[1] -User $rcUsers[1] -TimeoutSeconds 0) {
                Set-ItResult -Inconclusive -Because "the account of $($rcNames[1]) was requested before the recompute (validity scanner task?)"
                return
            }
            Invoke-midPointRecompute $rcUsers[1]
            Test-RcAccount -Account $rcNames[1] -User $rcUsers[1] -TimeoutSeconds 30 | Should -BeTrue -Because 'the recompute evaluates the assignment that is now valid'
            if ($manual) { $null = Complete-TestCase -Account $rcNames[1] -Comment 'midPointTools integration test' }
            $s = Wait-midPointShadow $rcUsers[1] -Resource $env:MIDPOINT_TEST_RESOURCE -TimeoutSeconds $wait
            Write-Host "Account after the recompute: $($s.Name) exists=$($s.Exists)"
            $s.Exists | Should -BeTrue
        }
    }
}
