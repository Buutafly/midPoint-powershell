# Working notes

Handover notes for the next working session. Last update: 2026-10-18.
REST details and the verification checklist are in [docs/rest-notes.md](docs/rest-notes.md).

## Status

- Prototype **0.1.0** of `midPointTools`, not yet released. 24 cmdlets: session, users, activation, role assignments,
  resources, shadows (accounts), cases. Unit tests (Pester, mocked HTTP) and PSScriptAnalyzer pass locally and in CI.
- Integration tests against a midPoint **4.10** test instance (details in `docs/rest-notes.md`):
  - With a real resource (ConnId connector) and a REST user with unrestricted single model actions: **all green**
    (users, activation, role assignment add / change / remove, account appears, account disabled after unassign).
  - With the example objects from `Tests/Integration/midpoint/` (manual resource, API role limited to test objects),
    run as `midpointtools-api`: **all green** (run 7, 2026-10-18), including the case flow through REST (complete the
    add case, account exists; complete the delete case, account gone) and the cleanup of cases.
  - Fixed on the way (runs 5-7): `connectorRef` imported with a filter comes with prefixed keys (`"t:oid"`), so the
    connector type was never read (`Get-midPointProperty` now finds `<prefix>:<name>`); deleting a case needs
    `authorization-model-3#cancelCase` (added to `030-role-api.xml`).
- The integration test deletes leftovers of aborted runs at the start (`MPTEST-` users, cases of `MPTEST-` accounts).
  If the connector type cannot be read, it still recognises a manual resource by the pending account with an open case.

## Next steps

1. Remaining items of the TODO list in `docs/rest-notes.md` (prefixes of references, `resolveNames`, raw shadow
   attributes, dead shadows).
2. Not covered by any test yet: extension attributes (`-Property @{ 'extension/...' = ... }`) and the initial
   password on `New-midPointUser`. Add integration tests if needed.
3. Release 0.1.0, see "Release 0.1.0" below. Steps 1 and 2 are not needed for it.

## Release 0.1.0

1. Integration tests green on 4.10: done (runs 4 and 7). Open TODO items in `docs/rest-notes.md` do not block 0.1.0.
2. One-time setup: PowerShell Gallery account, API key scoped to `midPointTools` (push new packages and versions),
   GitHub environment `psgallery` (Settings > Environments, optionally with a required reviewer) with the secret
   `PSGALLERY_API_KEY`.
3. In `CHANGELOG.md`, replace `unreleased` in `## [0.1.0] - unreleased` with the release date; commit, push, CI green.
4. Tag and push: `git tag v0.1.0 && git push origin v0.1.0`. The release workflow tests, publishes and creates the
   GitHub release.
5. Check: `Find-Module midPointTools`, then `Install-Module midPointTools -Scope CurrentUser` in a fresh session.
   A published version cannot be replaced on the Gallery (only unlisted); a fix becomes 0.1.1.

## Road to 1.0.0

- All items in the TODO list of `docs/rest-notes.md` confirmed; integration tests also on 4.8 (the minimum the
  README claims).
- Integration tests for extension attributes and the initial password.
- Output objects and parameter sets stable over a few 0.x releases of real use.
- Decide whether bearer token / OIDC login comes before 1.0 or can be added later without breaking changes.

## Decisions

- Module name `midPointTools` (free on the Gallery on 2026-10-17); cmdlet nouns `midPoint…` (lowercase m).
- One module (no split like Az): cases live in midPointTools; code grouped by area so a later split stays possible.
- Integration tests use a dedicated manual resource; the test completes its cases like an operator and deletes them.
- Auth: HTTP Basic with a `PSCredential`; session in memory only. Bearer tokens later (`AuthType` field exists).
- PowerShell 7.2+, midPoint 4.8+ (developed against 4.10), REST endpoint `<base>/ws/rest`, JSON.
- No "reason" parameter for status changes: midPoint has no such field on users, and the module must work out of
  the box. midPoint's own `disableReason` is only read.
- Validity (`validFrom` / `validTo`) and status for users **and** role assignments.
- Name lookups of resources / shadows use `options=noFetch` (no connector access).
- The REST user needs `authorization-rest-3#all` (or single REST operations) plus single model authorizations
  (`model-3#read`, `#add`, `#modify`, `#delete`, `#assign`, `#unassign`); `model-3#all` does not work. Runs 1 and 2
  used an administrator / Superuser; from run 3 on a dedicated test user (role in `docs/rest-notes.md`).

## How we work

- Public repo: no hostnames, URLs (except example / docs hosts), user names, OIDs or secrets. A Pester test checks URLs.
  Exception: the made-up OIDs `6d707400-0000-4000-8000-00000000000n` of the example objects in `Tests/Integration/midpoint/`.
  Local settings go into `Tests/Integration/settings.local.ps1` (git-ignored).
- Commits: author `Buutafly` (GitHub noreply address), trailer `Co-Authored-By: Claude`, no session links.
- Branches: `main` is the default branch. Work happens on the working branch; every push also fast-forwards `main`.
  Pushing without asking is fine.
- Before each push: `./build/Invoke-Tests.ps1` (lint + unit tests). CI runs the same.
- Integration tests run only on the user's machine; they read `MIDPOINT_*` environment variables
  (see the header of `Tests/Integration/midPoint.Integration.Tests.ps1`).

## Later

Password reset, start tasks, import / reconciliation on a resource, test a resource connection, generic
`Get-midPointObject`, bearer token / OIDC login, a least-privilege REST role for production,
possibly use the module in other test scripts.
