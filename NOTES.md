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
- midPoint may send JSON keys with a namespace prefix (`"t:oid"` in a reference with a filter);
  `Get-midPointProperty` falls back to `<prefix>:<name>` when the plain key is missing.
- The integration test keeps the fallback "pending account with an open case = manual resource" for REST users that
  cannot read connectors, and clears `MPTEST-` leftovers at the start (Ctrl+C skips AfterAll).
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
  (see the header of `Tests/Integration/midPoint.Integration.Tests.ps1`). A cloud session cannot reach the test
  instance: it prepares the tests, the user runs `./build/Invoke-Tests.ps1 -Integration -SkipAnalyzer` and pastes the
  output. That output contains the test instance's hostname: never copy it into the repository.
- Diagnostics the user cannot easily see (e.g. `-Verbose` lines, raw JSON) are printed by the integration test itself
  with `Write-Host` / `Write-Warning`, so one run answers the question.
- Changed example objects in `Tests/Integration/midpoint/` must be re-imported by the user (overwrite); say so.

## Later

Password reset, start tasks, import / reconciliation on a resource, test a resource connection, generic
`Get-midPointObject`, bearer token / OIDC login, a least-privilege REST role for production,
possibly use the module in other test scripts.

## Prompt for the next session

```text
We are working on the PowerShell module midPointTools in the repo Buutafly/midPoint-powershell.
First read NOTES.md and docs/rest-notes.md on the main branch – they contain the status, decisions and next steps.
Follow "How we work" in NOTES.md (public repo: no hostnames or secrets; commits authored by Buutafly with
Co-Authored-By: Claude, no session link; run ./build/Invoke-Tests.ps1 before every push; keep main in sync).
The integration tests (all green in run 7) run only on my machine; prepare them so that one run answers the
open questions, I run them and paste the output.

1. Close the open items of the TODO list in docs/rest-notes.md that the test instance can answer: let the
   integration test check or print `resolveNames` (targetRef.targetName of the assignment, resourceRef.targetName
   of the shadow), the raw JSON of the shadow `attributes`, the dead shadow after the account is deleted
   (`Get-midPointShadow -IncludeDead`: still in linkRef, `dead: true`), and the prefixes `c:RoleType` / `org:default`
   in references. Fix what the run turns up and tick off the items.
2. Add integration tests for the initial password on New-midPointUser (`password/value/clearValue`; check that the
   user can log in with it, e.g. Connect-midPoint as that user needs REST rights – otherwise only check that midPoint
   accepts it) and for extension attributes (`-Property @{ 'extension/...' = ... }`) – only if the test instance has
   a suitable extension item; ask me first which one.
3. Prepare the release 0.1.0: check CHANGELOG.md, README and the manifest, and list what I have to do on the
   PowerShell Gallery and in GitHub (environment `psgallery`, secret `PSGALLERY_API_KEY`, tag `v0.1.0`).
```

