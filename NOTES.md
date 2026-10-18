# Working notes

Handover notes for the next working session. Last update: 2026-10-18.
REST details and the verification checklist are in [docs/rest-notes.md](docs/rest-notes.md).

## Status

- Prototype **0.1.0** of `midPointTools`, not yet released. 24 cmdlets: session, users, activation, role assignments,
  resources, shadows (accounts), cases. Unit tests (Pester, mocked HTTP) and PSScriptAnalyzer pass locally and in CI.
- Integration tests against a midPoint **4.10** test instance (details in `docs/rest-notes.md`):
  - With a real resource (ConnId connector) and a REST user with unrestricted single model actions: **all green**
    (users, activation, role assignment add / change / remove, account appears, account disabled after unassign).
  - Example objects from `Tests/Integration/midpoint/` imported on the test instance, run as `midpointtools-api`
    (API role limited to test objects): users, activation and adding the test role **green**, so the narrow rights work
    up to there. Then the account wait hung (cancelled after 1 min): `Get-midPointResource` could not read the
    connector, even with the `connectors-read` authorization, so the test did not recognise the manual resource and
    waited for a real (not pending) account.
  - Leftovers of that cancelled run on the test instance: one `MPTEST-…` user and an open case on
    `midPointTools Test Resource` (Ctrl+C skips AfterAll).
- Never tested yet: the case flow (complete add / delete case, account exists afterwards), the cleanup of cases,
  the API role's rights for shadows / cases / work items.

## Next steps

1. Find out why `GET /connectors/{oid}` fails: run `Get-midPointResource 'midPointTools Test Resource' -Verbose` as
   `midpointtools-api` (build `$cred` from `settings.local.ps1`, see `docs/integration-tests.md`) and read the
   "Connector ... is not readable: ..." line. Possible fallback that needs no connector read: treat the resource as
   manual when the requested account is pending with an open case (`Wait-midPointShadow -AllowPending`, then
   `Get-midPointCase -Resource -Account`).
2. Clean up the leftovers (as administrator):
   `Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Remove-midPointUser -Confirm:$false`, then
   `Get-midPointCase -Resource 'midPointTools Test Resource' -State Open | Complete-midPointCase` and
   `Get-midPointCase -Resource 'midPointTools Test Resource' | Remove-midPointCase -Confirm:$false`.
3. Run the integration tests as `midpointtools-api` again; fix what the case flow and the API role need; tick off the
   TODO list in `docs/rest-notes.md`.
4. Not covered by any test yet: extension attributes (`-Property @{ 'extension/...' = ... }`) and the initial
   password on `New-midPointUser`. Add integration tests if needed.
5. Release: PowerShell Gallery account, GitHub environment `psgallery` with secret `PSGALLERY_API_KEY`,
   update `CHANGELOG.md`, push tag `v0.1.0`.

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
