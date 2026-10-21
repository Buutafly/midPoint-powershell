# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Orgs: `Get-midPointOrg`, `Get-` / `Add-` / `Set-` / `Remove-midPointOrgAssignment` (membership as member, manager or
  another relation, with assignment status and validity).
- Example org `midPointTools Test Org` for the integration tests; the example API role may assign it.
- `Extension` property on user objects: the user's extension items by name (`$u.Extension.costCenter`).
- `Invoke-midPointRecompute`: recomputes a user with reconciliation (`PATCH users/<oid>?options=reconcile` with an
  empty modification), like the recompute task: mappings and provisioning run, provisioning errors are reported.
  `-NoReconcile` skips the reconciliation (the resources are not read).
- `Remove-midPointShadow`: deletes an account on its resource (`DELETE shadows/<oid>`, like "delete projection"),
  from Get-midPointShadow objects or shadow OIDs; other objects are refused. A shadow that is already gone (404) or
  dead is a warning; an account that is still assigned (409, assignment policy) is an error.

## [0.1.0] - 2026-10-18

First prototype.

### Added
- `Connect-midPoint`, `Disconnect-midPoint`, `Get-midPointSession`: session with HTTP Basic authentication.
- Users: `Get-`, `New-`, `Set-`, `Remove-midPointUser`.
- Activation: `Enable-`, `Disable-`, `Unlock-midPointUser`, `Get-` / `Set-midPointUserActivation` (administrative status, validFrom, validTo).
- Roles: `Get-midPointRole`, `Get-` / `Add-` / `Set-` / `Remove-midPointRoleAssignment` (relation, assignment status and validity).
- Test helpers: `Get-`, `Test-`, `Wait-midPointShadow`.
- Cases: `Get-`, `Complete-`, `Remove-midPointCase` (e.g. the cases of a manual resource).
- `Get-midPointResource` with the connector type (recognises manual resources).
- Role assignments without a relation show `Relation` `default` (midPoint's default relation).
- Example midPoint objects for the integration tests (manual resource, test role, API user with limited rights).

[Unreleased]: https://github.com/Buutafly/midPoint-powershell/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Buutafly/midPoint-powershell/releases/tag/v0.1.0
