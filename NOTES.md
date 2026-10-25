# Working notes

Handover notes for the next working session. Last update: 2026-10-25.
REST details and the verification checklist are in [docs/rest-notes.md](docs/rest-notes.md).

## Status

- **0.1.0** of `midPointTools` released on the PowerShell Gallery (2026-10-18, tag `v0.1.0`). 24 cmdlets: session, users, activation, role assignments,
  resources, shadows (accounts), cases. Unit tests (Pester, mocked HTTP) and PSScriptAnalyzer pass locally and in CI.
- **0.2.0** prepared on `release/0.2.0` (2026-10-25): all four gaps of the consumer test script merged
  (Buutafly/midPoint-powershell#4 to #7), 32 cmdlets. Open: integration run on the release branch, merge, tag `v0.2.0`
  (user), then step 5 of "Release 0.1.0" below.
- Integration tests against a midPoint **4.10** test instance (details in `docs/rest-notes.md`):
  - With a real resource (ConnId connector) and a REST user with unrestricted single model actions: **all green**
    (users, activation, role assignment add / change / remove, account appears, account disabled after unassign).
  - With the example objects from `Tests/Integration/midpoint/` (manual resource, API role limited to test objects),
    run as `midpointtools-api`: **all green** (run 7, 2026-10-18), including the case flow through REST (complete the
    add case, account exists; complete the delete case, account gone) and the cleanup of cases.
  - Fixed on the way (runs 5-7): `connectorRef` imported with a filter comes with prefixed keys (`"t:oid"`), so the
    connector type was never read (`Get-midPointProperty` now finds `<prefix>:<name>`); deleting a case needs
    `authorization-model-3#cancelCase` (added to `030-role-api.xml`).
- Run 8 (2026-10-18): **all green**, all TODO items of `docs/rest-notes.md` confirmed: `resolveNames` on assignment
  and shadow, raw shadow `attributes`, the dead shadow after the delete, `c:RoleType` / `org:default` in references,
  the initial password (user `MPTEST-…-PW`) and an extension item (`MIDPOINT_TEST_EXTENSION_ITEM`, user
  `MPTEST-…-EXT`).
- The integration test deletes leftovers of aborted runs at the start (`MPTEST-` users, cases of `MPTEST-` accounts).
  If the connector type cannot be read, it still recognises a manual resource by the pending account with an open case.

## Next steps

1. 0.2.0, one branch each (see "How we work"):
   - `feature/org-assignments`: `Get-midPointOrg`, `Get-` / `Add-` / `Set-` / `Remove-midPointOrgAssignment`
     (shared code with the role assignments in `Private/Assignment.ps1`). Done: unit tests and integration run 11
     green (example org `050-org-test.xml`, `MIDPOINT_TEST_ORG`); merged (Buutafly/midPoint-powershell#1).
   - `feature/user-extension`: `Extension` property on user objects (`$u.Extension.costCenter`), plain keys as in
     run 8. Done, unit tests green; the integration test's extension check reads `Extension` too (next run).
   - `feature/user-password`: `Set-midPointUserPassword -Identity -NewPassword [-ForceChange]` in the style of
     `Set-ADAccountPassword -Reset`. Creating users without a password stays possible (`-Password` is optional).
   - OIDC / bearer token login: in a separate session, on its own branch.
   - Gaps found by a consumer test script that still called private functions (2026-10-21), one branch and pull
     request each, in this order (all merged by 2026-10-25); then `release/0.2.0` once an integration run is green:
     - `feature/recompute`: `Invoke-midPointRecompute -Identity [-NoReconcile] [-PassThru]`
       (`PATCH users/<oid>?options=reconcile`, empty modification). Runs 13 and 16 green: with and without reconcile
       an assignment whose `validFrom` has passed is provisioned, hence `-NoReconcile`.
     - `feature/assignment-batch`: `-Role` / `-Org` take several targets (one PATCH); `Move-midPointOrgAssignment
       -From -To [-Relation]` (one PATCH). Integration run 15 green (`060-org-test-2.xml`, `MIDPOINT_TEST_ORG2`).
     - `feature/remove-shadow`: `Remove-midPointShadow` (`DELETE shadows/<oid>`; only shadow objects or OIDs;
       404 or dead shadow = warning, 409 = error because midPoint also answers 409 for an assigned account).
       Run 18 green; a DELETE of a dead shadow opened another case, so dead shadows are now skipped
       (run 20 green: a dead shadow only warns, no new case).
     - `feature/org-extension`: `Extension` on org objects (same converter as users). Integration run 19
       green: GET and search both return the extension (`MIDPOINT_TEST_ORG_EXTENSION_ITEM`, value on Test Org 2).
2. Open from run 3: on a manual resource the user once had no linked shadow 180 s after the assignment (not seen
   since run 6).

## Release 0.1.0 (done 2026-10-18; the steps also apply to later versions)

1. Integration tests green on 4.10: done (runs 4, 7 and 8); the TODO list in `docs/rest-notes.md` is done (run 8).
2. One-time setup: PowerShell Gallery account, API key scoped to `midPointTools` (push new packages and versions),
   GitHub environment `psgallery` (Settings > Environments, optionally with a required reviewer) with the secret
   `PSGALLERY_API_KEY`. If the environment limits deployment branches and tags, it must allow the tags `v*`.
   Done 2026-10-18.
3. On a branch `release/<version>`: in `CHANGELOG.md`, replace `unreleased` with the release date (and bump
   `ModuleVersion` in the manifest for later versions); pull request, CI green, the user merges.
4. The user tags the merge commit on `main` and pushes the tag: `git tag v0.1.0 && git push origin v0.1.0`
   (a cloud session cannot push tags, HTTP 403). The release workflow tests, publishes and creates the
   GitHub release.
5. Check: `Find-Module midPointTools`, then `Install-Module midPointTools -Scope CurrentUser` in a fresh session.
   A published version cannot be replaced on the Gallery (only unlisted); a fix becomes 0.1.1.

## Road to 1.0.0

- Integration tests also on 4.8 (the minimum the README claims); the TODO list of `docs/rest-notes.md` is done on
  4.10 (run 8).
- Output objects and parameter sets stable over a few 0.x releases of real use.
- Decide whether bearer token / OIDC login comes before 1.0 or can be added later without breaking changes.

## Decisions

- Module name `midPointTools` (free on the Gallery on 2026-10-17); cmdlet nouns `midPoint…` (lowercase m).
- One module (no split like Az): cases live in midPointTools; code grouped by area so a later split stays possible.
- Integration tests use a dedicated manual resource; the test completes its cases like an operator and deletes them.
- The extension item for the integration test comes from `MIDPOINT_TEST_EXTENSION_ITEM` (the instance's schema stays
  out of the public repo). A role assignment without relation shows `Relation` `default`.
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
- Branches (from 2026-10-19): `main` changes only through pull requests; nothing is pushed to `main` directly.
  - One branch per piece of work, named after it so the user sees what happens where: `feature/<topic>` (new
    function), `fix/<topic>` (bug fix), `docs/<topic>` (notes, docs only), `release/<version>` (release date in
    CHANGELOG). Several sessions can work in parallel, each on its own branch.
  - A cloud session's own `claude/...` branch is only a scratch branch: it pushes its work to the named branch
    (`git push origin HEAD:feature/<topic>`) and opens the pull request from there.
  - Pull request into `main` when the work is done and `./build/Invoke-Tests.ps1` passes; CI must be green.
    The user reviews and merges (squash merge: one commit per piece of work on `main`).
  - Branch behind `main` or in conflict: merge `main` into the branch (no rebase, no force push), test, push.
  - `NOTES.md`: each branch changes only the lines of its own work (status, next steps) to keep conflicts small.
  - Tags (`v<version>`) are pushed by the user after the release pull request is merged; a cloud session cannot
    push tags (HTTP 403).
  - Pushing to the session's branches without asking is fine.
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
Co-Authored-By: Claude, no session link; run ./build/Invoke-Tests.ps1 before every push; one branch per piece of
work, pull request into main, never push to main directly).
The integration tests (all green in run 8) run only on my machine; I run them and paste the output.

<the task, e.g. one item of "Next steps" in NOTES.md; name its branch>
```
