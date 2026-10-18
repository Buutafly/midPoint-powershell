# Working notes

Handover notes for the next working session. Last update: 2026-10-18.
REST details and the verification checklist are in [docs/rest-notes.md](docs/rest-notes.md).

## Status

- Prototype **0.1.0** of `midPointTools`, not yet released. 20 cmdlets: session, users, activation, role assignments,
  shadows (accounts). Unit tests (Pester, mocked HTTP) and PSScriptAnalyzer pass locally and in CI (Ubuntu + Windows).
- Integration tests against a midPoint **4.10** test instance:
  - Run 1: all user and activation tests green (create, search, change, enable / disable, validity, 404 handling).
  - Run 2 (with a test role): adding the role assignment with `validTo` works. The account check hung because the
    test resource is a **manual resource** (the account is only requested, as a case) and the resource name lookup hit a
    250 partial error. Fixed afterwards (commit "Shadows: noFetch name lookup, pending accounts, wait progress"),
    **not yet re-tested**.

- Run 3 (2026-10-18), new dedicated REST test user: blocked by authorizations before any test ran. 401 (password),
  then HTTP 500 "Access denied" on `GET /self`: `authorization-model-3#all` is not a wildcard on 4.10. Role example
  with single model actions in `docs/rest-notes.md`. Module now shows error bodies without `message` and explains 401.

## Next steps

1. Clean up leftovers from the interrupted run 2: the `MPTEST-…` user (and its open case) on the test instance:
   `Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Remove-midPointUser`.
2. Run 3: `$env:MIDPOINT_TEST_RESOURCE_MANUAL = '1'` plus `MIDPOINT_TEST_ROLE` / `MIDPOINT_TEST_RESOURCE`, then
   `./build/Invoke-Tests.ps1 -Integration -SkipAnalyzer`. Checks pending accounts, `Set-` / `Remove-midPointRoleAssignment`.
   Optionally also with a resource that has a real connector (shadow attribute format).
3. Fix what run 3 finds, tick off the TODO list in `docs/rest-notes.md`.
4. Not covered by any test yet: extension attributes (`-Property @{ 'extension/...' = ... }`) and the initial
   password on `New-midPointUser`. Add integration tests if needed.
5. Release: PowerShell Gallery account, GitHub environment `psgallery` with secret `PSGALLERY_API_KEY`,
   update `CHANGELOG.md`, push tag `v0.1.0`.

## Decisions

- Module name `midPointTools` (free on the Gallery on 2026-10-17); cmdlet nouns `midPoint…` (lowercase m).
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
