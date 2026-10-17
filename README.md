# midPointTools

PowerShell cmdlets for the [Evolveum midPoint](https://evolveum.com/midpoint/) REST API.

midPointTools gives security admins verb-noun cmdlets in the style of the ActiveDirectory and Az modules:
connect once, then create, change, enable / disable and delete users, manage role assignments with their
validity, and check the accounts a user has on the resources. The account checks are also meant to make test scripts
for midPoint configurations short.

> **Status: prototype (0.1.0).** The cmdlets are covered by unit tests against a mocked midPoint.
> A few REST details still need confirmation on a real midPoint 4.10 instance, see [docs/rest-notes.md](docs/rest-notes.md).

This is a community project, not affiliated with Evolveum.

## Requirements

- PowerShell 7.2 or later (Windows, Linux, macOS)
- midPoint 4.8 or later (developed against 4.10) with the REST API enabled
- A midPoint user with the REST authorizations for the operations you want to run

## Install

From the PowerShell Gallery (once published):

```powershell
Install-Module midPointTools -Scope CurrentUser
```

From source:

```powershell
git clone https://github.com/Buutafly/midPoint-powershell.git
Import-Module ./midPoint-powershell/midPointTools/midPointTools.psd1
```

## Quick start

```powershell
Connect-midPoint -Uri https://midpoint.example.com/midpoint -Credential (Get-Credential)

Get-midPointUser jack
New-midPointUser -Name jdoe -GivenName John -FamilyName Doe -EmailAddress jdoe@example.com
Set-midPointUser jdoe -Replace @{ telephoneNumber = '+41 00 000 00 00' }

Disable-midPointUser jdoe
Enable-midPointUser jdoe -ValidTo (Get-Date).AddMonths(6)
Get-midPointUserActivation jdoe

Add-midPointRoleAssignment jdoe -Role 'Some Role' -ValidTo (Get-Date).AddDays(30)
Get-midPointRoleAssignment jdoe
Set-midPointRoleAssignment jdoe -Role 'Some Role' -ClearValidTo
Remove-midPointRoleAssignment jdoe -Role 'Some Role'

Get-midPointShadow jdoe -Resource 'Some Resource'
Remove-midPointUser jdoe
```

`-Identity`, `-User` and `-Role` accept a name, an OID, or an object from a `Get-` cmdlet, so the
cmdlets work in the pipeline:

```powershell
Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Remove-midPointUser -Confirm:$false
```

Every cmdlet has help: `Get-Help Add-midPointRoleAssignment -Full`.

## Use in test scripts

```powershell
Connect-midPoint -Uri $env:MIDPOINT_URI -Credential $cred

$u = New-midPointUser -Name "MPTEST-$(Get-Random)" -GivenName Test -FamilyName User -EmailAddress 'test@example.com' -PassThru
Add-midPointRoleAssignment $u -Role 'Some Role'

# Waits until the account exists on the resource with the expected values, or fails after the timeout.
$account = Wait-midPointShadow $u -Resource 'Some Resource' -Attribute @{ mail = 'test@example.com' } -TimeoutSeconds 180
$account.Attributes

Remove-midPointUser $u -Confirm:$false
```

## Cmdlets

| Area | Cmdlets |
|---|---|
| Session | `Connect-midPoint`, `Disconnect-midPoint`, `Get-midPointSession` |
| Users | `Get-midPointUser`, `New-midPointUser`, `Set-midPointUser`, `Remove-midPointUser` |
| Activation | `Enable-midPointUser`, `Disable-midPointUser`, `Unlock-midPointUser`, `Get-midPointUserActivation`, `Set-midPointUserActivation` |
| Roles | `Get-midPointRole`, `Get-midPointRoleAssignment`, `Add-midPointRoleAssignment`, `Set-midPointRoleAssignment`, `Remove-midPointRoleAssignment` |
| Accounts | `Get-midPointShadow`, `Test-midPointShadow`, `Wait-midPointShadow` |

### Status and validity

midPoint decides whether a user or an assignment is active from three values in `activation`:

- `AdministrativeStatus`: set explicitly by an admin (`Enabled`, `Disabled`, `Archived`). It always wins.
- `ValidFrom` / `ValidTo`: used when no administrative status is set.
- `EffectiveStatus`: the result, computed by midPoint (read only).

`Set-midPointUserActivation -AdministrativeStatus None` removes the explicit status, so the dates decide again.
`Enable-midPointUser` warns when a user stays effectively disabled, e.g. because `ValidTo` is in the past.
Role assignments have their own status and validity (`Add-` / `Set-midPointRoleAssignment`).

## Authentication and security

- `Connect-midPoint` uses HTTP Basic authentication, midPoint's default for the REST API. Use https.
- The credential is only kept in memory for the current PowerShell session; nothing is written to disk.
  `Disconnect-midPoint` removes it.
- `-SkipCertificateCheck` is meant for test systems with self-signed certificates only.
- `-Verbose` shows method and URL of each request, never headers. `-Debug` also shows request bodies,
  with password values masked.

## Development

```powershell
./build/Invoke-Tests.ps1                # PSScriptAnalyzer + Pester unit tests (as in CI)
./build/Invoke-Tests.ps1 -Integration   # also against a midPoint test instance, see below
```

The unit tests mock the HTTP layer and need no server. The integration tests in `Tests/Integration` run
against a real midPoint when these environment variables are set: `MIDPOINT_URI`, `MIDPOINT_USER`,
`MIDPOINT_PASSWORD`, optionally `MIDPOINT_SKIP_CERT_CHECK=1`, `MIDPOINT_TEST_ROLE`, `MIDPOINT_TEST_RESOURCE`.
They create one `MPTEST-…` user and delete it at the end.

## Releases

1. Update `ModuleVersion` in `midPointTools/midPointTools.psd1` and `CHANGELOG.md`.
2. Push a tag `v<ModuleVersion>`, e.g. `v0.1.0`.
3. The release workflow runs the tests, checks that the tag matches the module version, publishes to the
   PowerShell Gallery with `Publish-Module`, and creates a GitHub release.

One-time setup: create a GitHub environment `psgallery` (optionally with required reviewers) and add the
PowerShell Gallery API key to it as the secret `PSGALLERY_API_KEY`.

## License

[MIT](LICENSE)
