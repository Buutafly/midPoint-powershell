# Working notes

Handover notes for the next working session. Last update: 2026-10-18.
REST details and the verification checklist are in [docs/rest-notes.md](docs/rest-notes.md).

## Status

- Prototype **0.1.0** of `midPointTools`, not yet released. 24 cmdlets: session, users, activation, role assignments,
  resources, shadows (accounts), cases. Unit tests (Pester, mocked HTTP) and PSScriptAnalyzer pass locally and in CI (Ubuntu + Windows).
- Integration tests against a midPoint **4.10** test instance:
  - Run 1: all user and activation tests green (create, search, change, enable / disable, validity, 404 handling).
  - Run 2 (with a test role): adding the role assignment with `validTo` works. The account check hung because the
    test resource is a **manual resource** (the account is only requested, as a case) and the resource name lookup hit a
    250 partial error. Fixed afterwards (commit "Shadows: noFetch name lookup, pending accounts, wait progress"),
    **not yet re-tested**.

- Run 3 (2026-10-18), new dedicated REST test user: blocked by authorizations before any test ran. 401 (password),
  then HTTP 500 "Access denied" on `GET /self`: `authorization-model-3#all` is not a wildcard on 4.10. Role example
  with single model actions in `docs/rest-notes.md`. Module now shows error bodies without `message` and explains 401.

- Run 3, second attempt: connect, users, activation and adding the role with `validTo` green. Failed: the
  account check (no shadow linked after 180 s, being analysed), `Set-` / `Remove-midPointRoleAssignment`
  (container id is `@id` in JSON; fixed, not yet re-tested).

- Case cmdlets (`Get-` / `Complete-` / `Remove-midPointCase`) and an example test configuration
  (`Tests/Integration/midpoint/`, guide `docs/integration-tests.md`): manual test resource whose operator is the API
  user, test role, API role limited to the test objects. The integration test recognises a manual resource by its
  connector type (`Get-midPointResource`), completes its own cases and deletes them.
  Not yet run against the instance.

## Next steps

1. Import the example objects (`docs/integration-tests.md`), set the API user's password, create
   `Tests/Integration/settings.local.ps1`, run `./build/Invoke-Tests.ps1 -Integration -SkipAnalyzer`.
   Not verified yet: the API role's filters, the case flow (complete add / delete case), `@id` fix for
   `Set-` / `Remove-midPointRoleAssignment`, shadow attribute format.
2. Fix what the run finds, tick off the TODO list in `docs/rest-notes.md`.
3. Optionally also run against a resource with a real connector (shadow attribute format).
4. Not covered by any test yet: extension attributes (`-Property @{ 'extension/...' = ... }`) and the initial
   password on `New-midPointUser`. Add integration tests if needed.
5. Release 0.1.0, see "Release 0.1.0" below.

## Release 0.1.0

1. Integration run green on 4.10 (next steps 1 and 2). Items that cannot be confirmed yet stay in the TODO list
   of `docs/rest-notes.md`; they are fine for 0.1.0 as long as no test fails.
2. One-time setup: PowerShell Gallery account, API key scoped to `midPointTools` (push new packages and versions),
   GitHub environment `psgallery` (Settings > Environments, optionally with a required reviewer) with the secret
   `PSGALLERY_API_KEY`.
3. In `CHANGELOG.md`, replace `unreleased` in `## [0.1.0] - unreleased` with the release date; commit, push, CI green.
4. Tag and push: `git tag v0.1.0 && git push origin v0.1.0`. The release workflow tests, publishes and creates the
   GitHub release.
5. Check: `Find-Module midPointTools`, then `Install-Module midPointTools -Scope CurrentUser` in a fresh session.
   A published version cannot be replaced on the Gallery (only unlisted); a fix becomes 0.1.1.

## Road to 1.0.0

- All items in the TODO list of `docs/rest-notes.md` confirmed; integration tests green on 4.10 and on 4.8 (the
  minimum the README claims), also against a resource with a real connector.
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
