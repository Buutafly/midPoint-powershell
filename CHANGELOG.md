# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - unreleased

First prototype.

### Added
- `Connect-midPoint`, `Disconnect-midPoint`, `Get-midPointSession`: session with HTTP Basic authentication.
- Users: `Get-`, `New-`, `Set-`, `Remove-midPointUser`.
- Activation: `Enable-`, `Disable-`, `Unlock-midPointUser`, `Get-` / `Set-midPointUserActivation` (administrative status, validFrom, validTo).
- Roles: `Get-midPointRole`, `Get-` / `Add-` / `Set-` / `Remove-midPointRoleAssignment` (relation, assignment status and validity).
- Test helpers: `Get-`, `Test-`, `Wait-midPointShadow`.
- Cases: `Get-`, `Complete-`, `Remove-midPointCase` (e.g. the cases of a manual resource).
- `Get-midPointResource` with the connector type (recognises manual resources).
- Example midPoint objects for the integration tests (manual resource, test role, API user with limited rights).
