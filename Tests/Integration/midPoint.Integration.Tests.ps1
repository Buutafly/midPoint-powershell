# Integration tests against a real midPoint test instance. Not run in CI.
#
# Required environment variables (set them locally, never commit values):
#   MIDPOINT_URI       e.g. https://midpoint.example.com/midpoint
#   MIDPOINT_USER      a midPoint user with REST authorizations
#   MIDPOINT_PASSWORD
# Optional:
#   MIDPOINT_SKIP_CERT_CHECK = 1   for self-signed test certificates
#   MIDPOINT_TIMEOUT_SEC           request timeout in seconds (default 30 here)
#   MIDPOINT_TEST_ROLE             a role name to assign / unassign
#   MIDPOINT_TEST_RESOURCE         a resource the role provisions to (needs MIDPOINT_TEST_ROLE)
#   MIDPOINT_TEST_RESOURCE_MANUAL = 1   the resource is a manual resource: the account is only requested
#                                       (open case), so the test accepts a pending account and does not fetch
#   MIDPOINT_SHADOW_TIMEOUT_SEC    how long to wait for the account (default 180)
#
# Run: Invoke-Pester ./Tests/Integration -Tag Integration -Output Detailed
# Creates one user named MPTEST-<random> and deletes it at the end.

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
        Connect-midPoint -Uri $env:MIDPOINT_URI -Credential $cred -SkipCertificateCheck:($env:MIDPOINT_SKIP_CERT_CHECK -eq '1') -TimeoutSec $timeout
        $script:name = 'MPTEST-{0}' -f (Get-Random -Minimum 100000 -Maximum 999999)
    }

    AfterAll {
        Get-midPointUser $script:name | Remove-midPointUser -Confirm:$false
        Disconnect-midPoint
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
            $manual = $env:MIDPOINT_TEST_RESOURCE_MANUAL -eq '1'
            $wait = if ($env:MIDPOINT_SHADOW_TIMEOUT_SEC) { [int]$env:MIDPOINT_SHADOW_TIMEOUT_SEC } else { 180 }
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

        It 'changes the assignment validity' {
            $a = Set-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE -ClearValidTo -PassThru
            $a.ValidTo | Should -BeNullOrEmpty
        }

        It 'removes the role' {
            Remove-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE -Confirm:$false
            Get-midPointRoleAssignment $user -Role $env:MIDPOINT_TEST_ROLE | Should -BeNullOrEmpty
        }
    }
}
