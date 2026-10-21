# Integration tests: setting up a midPoint test instance

The unit tests need no server. The integration tests in `Tests/Integration` run the cmdlets against a real midPoint.
This page shows how to prepare a midPoint **test instance** so that the tests touch nothing but their own objects.

## What gets imported

Five example objects in [`Tests/Integration/midpoint/`](../Tests/Integration/midpoint/), all named
`midPointTools …` so they are easy to find and to delete again:

| File | Object | Purpose |
|---|---|---|
| `010-resource-test-manual.xml` | Resource `midPointTools Test Resource` | Manual resource (built-in manual connector, no external system). Each account change becomes a case assigned to the API user. |
| `020-role-test.xml` | Role `midPointTools Test Role` | The role the tests assign: an account on the test resource, nothing else. |
| `030-role-api.xml` | Role `midPointTools API (test)` | The rights of the API user, limited to the test objects (see below). |
| `040-user-api.xml` | User `midpointtools-api` | The user the tests log in as. No password in the file. |
| `050-org-test.xml` | Org `midPointTools Test Org` | The org the tests assign (as member and as manager). Induces nothing. |

The objects reference each other by OID. The OIDs in the files are made up (`6d707400-0000-4000-8000-00000000000n`);
keep them as they are.

### Rights of the API user

`midPointTools API (test)` allows only what the tests do:

- use the REST API and read itself (`Connect-midPoint` calls `GET /self`),
- read, create, change and delete users whose name starts with `MPTEST-`,
- assign and unassign the test role (and no other role), read the test role,
- assign and unassign the test org as member or manager (and no other org), read the test org,
- read the test resource, and read connectors (to recognise a manual resource by its connector type),
- read, create, change and delete shadows (accounts) on the test resource,
- read and delete (`#delete` plus `#cancelCase`) the cases of the test resource, and complete the work items assigned
  to the API user.

Everything else on the instance is invisible to it. Model actions are listed one by one on purpose:
`authorization-model-3#all` is not a wildcard (see [rest-notes.md](rest-notes.md)).

## Setup

Tested with midPoint 4.10. You need an administrator account on the test instance once.

1. **Import the five files** in the order of their numbers: *Import object* in the GUI (or the `ninja` tool), with
   *Overwrite existing object* if you import them again.
2. **Set a password** for `midpointtools-api` in the GUI (*Users* → `midpointtools-api` → *Password*). Keep it out of
   the repository.
3. **Check the resource:** *Resources* → `midPointTools Test Resource` → *Test connection* should succeed.
4. **Create your local settings:** copy `Tests/Integration/settings.example.ps1` to
   `Tests/Integration/settings.local.ps1` (git ignores `*.local.ps1`) and fill in the URL and the password.
5. **Run the tests:**

   ```powershell
   ./build/Invoke-Tests.ps1 -Integration -SkipAnalyzer
   ```

   `Invoke-Tests.ps1 -Integration` loads `settings.local.ps1`; alternatively set the `MIDPOINT_*` environment
   variables yourself (listed in the header of `Tests/Integration/midPoint.Integration.Tests.ps1`).

## What a test run does

1. Logs in as `midpointtools-api` and creates the user `MPTEST-<random>`. Two short-lived users check the initial
   password (`MPTEST-<random>-PW`) and, with `MIDPOINT_TEST_EXTENSION_ITEM`, an extension item (`MPTEST-<random>-EXT`).
2. Changes it (description, status, validity) and searches it.
3. Assigns `midPointTools Test Role` with a `validTo` date. midPoint opens a case
   *"Request to add 'MPTEST-…' on 'midPointTools Test Resource'"* for the API user; the test sees the requested
   account (pending), completes the case like an operator and checks that the account now exists.
4. Changes the assignment's validity and removes the assignment. midPoint opens a case to delete the account;
   the test completes it, checks that the account is gone and that its shadow is kept as a dead shadow.
   Before that, `Remove-midPointShadow` on the still assigned account must fail with HTTP 409 (assignment policy).
5. Account delete: creates an account `MPTEST-<random>-SHD` without owner (`POST shadows`, add case completed),
   deletes it with `Remove-midPointShadow` (delete case completed), checks that the shadow is dead or gone, and prints
   what a second `Remove-midPointShadow` on it answers. An aborted run can leave this account on the test resource;
   the next run completes its open cases, a live leftover can be deleted in the GUI.
6. At the end (also after a failure) it completes any case of its account that is still open, deletes the user and
   deletes the cases of its account.

With `MIDPOINT_TEST_ORG` set, the test also assigns `midPointTools Test Org` as member and as manager, changes the
manager assignment, and removes both again.

Nothing else is changed: the role, the org, the resource and all other objects are only read.

## Troubleshooting

- **HTTP 401:** wrong user name or password, or the variables still point to another user (check `settings.local.ps1`
  and `$env:MIDPOINT_USER`).
- **HTTP 500 "Access denied"** or **403:** an authorization is missing. Set the logger
  `com.evolveum.midpoint.security` to `TRACE` (*System* → *Logging*), run the tests again and look in `idm.log` for
  lines with `midpointtools-api` and `DENY` or `NO COVERAGE`. Set the logger back afterwards.
- **No case / no account:** check that `midPointTools Test Role` has the inducement for the test resource and that the
  resource's *business* configuration names `midpointtools-api` as operator.
- **Leftovers after an aborted run:** delete them as administrator:

  ```powershell
  Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Remove-midPointUser -Confirm:$false
  Get-midPointCase -Resource 'midPointTools Test Resource' -State Open | Complete-midPointCase
  Get-midPointCase -Resource 'midPointTools Test Resource' | Remove-midPointCase -Confirm:$false
  ```

## Using your own role and resource

The tests also run against an existing role and resource: set `MIDPOINT_TEST_ROLE` and `MIDPOINT_TEST_RESOURCE` to
their names. The role must give an account on that resource. Keep in mind that midPoint really provisions: with a real
connector the test creates an account `MPTEST-<random>` in the target system, waits for it, and after removing the
role waits until midPoint has deleted or disabled it (deleting the test user at the end deprovisions it as configured).
The test recognises a manual (or semi-manual) resource by its connector type `ManualConnector` and then completes
the cases of its account, which only works when the test user is the resource's operator.

## Extension items

The extension test needs an extension item that exists on your instance, so it only runs when
`MIDPOINT_TEST_EXTENSION_ITEM` names one: a single-valued string item of `UserType`, given by its local name
(e.g. `costCenter`, no namespace). The test sets it with `New-midPointUser -Property @{ 'extension/<item>' = ... }`,
changes and clears it with `Set-midPointUser -Replace`. The example API role already allows this (no item limits).
