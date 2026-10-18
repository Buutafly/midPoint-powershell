# midPoint REST API notes

What the module relies on, where it comes from, and what still needs confirmation on a live midPoint 4.10.
Reference: [midPoint REST API](https://docs.evolveum.com/midpoint/reference/interfaces/rest/).

## Confirmed from the documentation

| Topic | Behaviour | Used in |
|---|---|---|
| Base URL | `<midPoint URL>/ws/rest`, e.g. `https://midpoint.example.com/midpoint/ws/rest` | `Connect-midPoint` |
| Auth | HTTP Basic | `Invoke-midPointRestMethod` |
| Format | XML by default; `Accept: application/json` and `Content-Type: application/json` for JSON | `Invoke-midPointRestMethod` |
| Self | `GET /self` | `Connect-midPoint` |
| Get | `GET /users/{oid}` returns `{ "user": { ... } }` | `Get-midPointUser -Oid` |
| Search | `POST /users/search` with `{ "query": { "filter": { "text": "name startsWith \"a\"" } } }`; result `{ "object": { "@type": "...ObjectListType", "object": [ ... ] } }` | `Find-midPointObject` |
| Create | `POST /users` with `{ "user": { ... } }` → 201, no body, `Location` header with the new object URL | `New-midPointUser` |
| Modify | `PATCH /users/{oid}` with `{ "objectModification": { "itemDelta": { "modificationType", "path", "value" } } }` → 204 | `Invoke-midPointModify` |
| Delete | `DELETE /users/{oid}` → 204 | `Remove-midPointUser` |
| Options | `?options=raw&options=resolveNames` (repeated parameter) | `Invoke-midPointRestMethod -Query` |
| Cases | `POST /cases/search`, `GET` / `DELETE /cases/{oid}`; complete a work item with `POST /cases/{oid}/workItems/{id}/complete` and `{ "output": { "@type": "c:AbstractWorkItemOutputType", "outcome": "...approval/outcome#approve", "comment": "..." } }` | `Get-` / `Complete-` / `Remove-midPointCase` |
| Status codes | 240 handled error, 250 partial error (both with an OperationResult); 4xx usually with an OperationResult | `Invoke-midPointRestMethod` (250 → warning) |

## Confirmed on midPoint 4.10 (integration tests, 2026-10-17)

- `GET /self`, create with the OID in the `Location` header, get by OID, delete.
- Search with `{ "query": { "filter": { "text": "name = \"...\"" } } }` and `name startsWith`; an empty result returns nothing.
- 404 for a missing OID, with a message the module can show.
- `itemDelta` as an **array** (several changes in one PATCH).
- `replace` without `value` clears an item (`-ClearValidTo`, `-AdministrativeStatus None`).
- `effectiveStatus` / `validityStatus` are returned by a plain `GET /users/{oid}`; `validTo` in the past gives `disabled` / `after`.
- Adding a role assignment with `activation/validTo` (`Add-midPointRoleAssignment -PassThru` reads it back).
- A search over `resources` without `options=noFetch` makes midPoint complete schema and capabilities of every
  resource; one broken resource (e.g. a manual connector configuration) turns the search into a 250 partial error.
  Name lookups of resources and shadows therefore use `noFetch`.
- The REST user needs the REST authorization (`authorization-rest-3#all` or single operations) and the model authorizations; without them midPoint answers "Not authorized".
- `authorization-model-3#all` is **not** a wildcard (authorization trace, 2026-10-18): it is "not applicable" to
  `model-3#read` / `#get` (the same user works with Superuser, i.e. `authorization-3#all`). `authorization-rest-3#all` only works because the REST layer checks that exact URL.
  Without a read authorization, `GET /self` passes the REST check and then fails with **HTTP 500, body
  `Access denied`** (`AuthorizationException` in `DataAccessProcessor.applyReadConstraints`), not with 403.
- Wrong password: HTTP 401 without a body.
- Run 4 (2026-10-18, real resource with a ConnId connector, dedicated REST user): all integration tests green.
  `Set-midPointRoleAssignment` with `assignment[id]/...`, `Remove-midPointRoleAssignment` deleting by `{ "@id": n }`,
  shadow read with attributes (fetch), account disabled (not deleted) after unassigning on that resource.
- An item path with a container id is written `assignment[3]/activation/validTo` (no `/` before `[`); with
  `assignment/[3]/...` midPoint answers HTTP 500 "doesn't contain definition for path assignment//[3]/..." (run 3).
- Container ids (e.g. of assignments) are `@id` in JSON, not `id` (run 3: reading `id` gave an empty id and
  `PATCH` failed with HTTP 400 "For input string: \"\""). The module reads `@id` (falls back to `id`) and deletes
  assignments with `{ "@id": n }`.
- A reference that carries a filter (e.g. a resource's `connectorRef` imported with a filter) comes with prefixed
  keys: `{ "t:oid": "...", "t:relation": "org:default", "t:type": "c:ConnectorType", "filter": { ... } }` (run 6).
  `Get-midPointProperty` therefore finds `oid` also as `<prefix>:oid`. Before that, `Get-midPointResource` saw no
  connector OID and never read the connector.
- Run 6 (manual resource, as `midpointtools-api`): case search with `objectRef matches (oid = "...")`, completing
  the work item through REST with outcome `approve` (shadow exists afterwards, `refreshOnRead`), the delete case
  after unassigning (account gone). Deleting a case (`DELETE cases/{oid}`) needs `authorization-model-3#cancelCase`
  in addition to `#delete`, else HTTP 403.
- Run 7 (2026-10-18, as `midpointtools-api` with the example objects): **all green**. Connector type
  `ManualConnector` read through `GET /connectors/{oid}` (the `connectors-read` authorization is enough), leftover
  cases deleted, the full case flow and the cleanup of the run's own cases work.
- Run 8 (2026-10-18, as `midpointtools-api` with the example objects): **all green**.
  - A reference written as `{ "type": "c:RoleType", "relation": "org:default" }` is accepted and comes back the same
    way: `{ "oid", "relation": "org:default", "type": "c:RoleType", "targetName": ... }` (with `resolveNames`).
    Shadow `resourceRef` likewise: `"type": "c:ResourceType"`, `targetName` filled by `resolveNames`.
  - Shadow `attributes` (fetched and with `noFetch`): plain keys with an `@ns` entry, single values as scalars:
    `{ "@ns": "http://midpoint.evolveum.com/xml/ns/public/resource/instance-3", "username": "...", "mail": "..." }`.
  - Extension items without namespace: `-Property @{ 'extension/<item>' = ... }` on create, `-Replace` with a value
    and with `''` (clears) work; `extension` comes back with plain keys (`{ "<item>": "..." }`).
  - Initial password with `credentials/password/value/clearValue` is accepted; reading the user returns
    `credentials.password` with `@metadata` and `value.encryptedData` (no clear value).
  - After the account is deleted (manual resource, case completed) the shadow stays linked with
    `"relation": "org:related"` and has `dead: true`, `exists: false`, both pending operations `completed` /
    `success`. `Get-midPointShadow` hides it, `-IncludeDead` returns it.
- Run 3 on a manual resource: 180 s after assigning the role, the user had no linked shadow on that resource
  (neither live nor pending). Still to be analysed.

## REST user for the integration tests

A role for a test instance (full access to the model, so not for production). Assign it to a user with a password;
the integration tests log in as that user. Confirmed on 4.10: `GET /self` (read); add / modify / delete / assign
still to be confirmed by a full integration run.

```xml
<role xmlns="http://midpoint.evolveum.com/xml/ns/public/common/common-3">
    <name>REST API test user (midPointTools)</name>
    <description>Test instance only: REST and model access for the midPointTools integration tests.</description>
    <authorization>
        <name>rest-all</name>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-rest-3#all</action>
    </authorization>
    <authorization>
        <name>model-crud</name>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-model-3#read</action>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-model-3#add</action>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-model-3#modify</action>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-model-3#delete</action>
    </authorization>
    <authorization>
        <name>model-assign</name>
        <phase>request</phase>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-model-3#assign</action>
        <action>http://midpoint.evolveum.com/xml/ns/public/security/authorization-model-3#unassign</action>
    </authorization>
</role>
```

Troubleshooting: set the logger `com.evolveum.midpoint.security` to `TRACE`; `idm.log` then lists every evaluated
authorization (`AUTZ.n> Evaluating authorization ...`) with its decision.

## Manual resources and cases (from the midPoint 4.10 sources)

- The manual connector opens one case per change: `objectRef` = the resource, `targetRef` = the shadow, archetype
  "Manual provisioning case" (`...0340`), name `Request to <operation> '<account>' on '<resource>'`.
- Assignees: `business/operatorRef` of the resource, else the connector setting `defaultAssignee` (a user name).
- When the case is closed, the case outcome decides: `approve` (or `success`) means the operator did the change;
  `reject` means it failed. Completing the work item through REST closes the case.
- With `consistency/refreshOnRead` the shadow picks up the closed case the next time it is read.

## To verify on midPoint 4.10 (TODO)

Run `Tests/Integration` with `MIDPOINT_TEST_ROLE` and `MIDPOINT_TEST_RESOURCE` set for the remaining items
(`MIDPOINT_TEST_EXTENSION_ITEM` for the extension item). The integration test prints the raw JSON of each item.

- [x] Reference type `c:RoleType` and relation `org:default` prefixes are resolved in JSON (run 8, the test assigns
      with `-Relation default`). `org:manager` is covered by the unit tests only.
- [x] Extension items via `-Property @{ 'extension/costCenter' = ... }` without namespace (create, replace, clear;
      run 8).
- [x] `resolveNames` fills `targetRef.targetName` for assignments and `resourceRef.targetName` for shadows (run 8).
- [x] Raw shape of shadow `attributes` in JSON: plain keys plus `@ns`, scalars for single values (run 8).
- [x] Dead shadows are still in `linkRef` (relation `org:related`) and carry `dead: true` (run 8).
- [x] Pending operations on shadows of a manual resource: `pendingOperation[].executionStatus`, `delta.changeType`,
      `delta.objectToAdd.attributes`, and `exists: false` until the case is closed (run 7: `exists=False`,
      pending `add` with the requested `mail` / `username`).
- [x] Shape of the OperationResult on 4xx (the module searches for the first `message`): works for 403 and 404
      (run 6: "User 'midpointtools-api' not authorized for operation ...#cancelCase on case:...").
- [x] `password/value/clearValue` for the initial password on create (run 8: stored as `encryptedData`).
- [ ] Org assignments as member and manager (`targetRef` type `c:OrgType`), with the `relation` items in the
      example API role's `test-org-assign` authorization; the user gets `parentOrgRef`.
- [x] The example API role (`Tests/Integration/midpoint/030-role-api.xml`) is enough for a full run (run 7, with
      `#cancelCase` added): filters `name startsWith "MPTEST-"`, `q:inOid`, `q:ref`, and the work item
      authorization with `assignee/special=self`.

## Not in scope (yet)

- A free-text reason for status changes: midPoint has no such item on users. `activation/disableReason`
  is a URI set by midPoint (explicit, mapped, deprovision, ...) and only read by the module.
- Bearer token / OIDC authentication, password reset, tasks, import / reconciliation.
