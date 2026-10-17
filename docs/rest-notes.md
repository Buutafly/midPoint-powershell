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
| Status codes | 240 handled error, 250 partial error (both with an OperationResult); 4xx usually with an OperationResult | `Invoke-midPointRestMethod` (250 → warning) |

## Confirmed on midPoint 4.10 (integration tests, 2026-10-17)

- `GET /self`, create with the OID in the `Location` header, get by OID, delete.
- Search with `{ "query": { "filter": { "text": "name = \"...\"" } } }` and `name startsWith`; an empty result returns nothing.
- 404 for a missing OID, with a message the module can show.
- `itemDelta` as an **array** (several changes in one PATCH).
- `replace` without `value` clears an item (`-ClearValidTo`, `-AdministrativeStatus None`).
- `effectiveStatus` / `validityStatus` are returned by a plain `GET /users/{oid}`; `validTo` in the past gives `disabled` / `after`.
- The REST user needs the REST authorization (`authorization-rest-3#all` or single operations) and the model authorizations; without them midPoint answers "Not authorized".

## To verify on midPoint 4.10 (TODO)

Run `Tests/Integration` with `MIDPOINT_TEST_ROLE` and `MIDPOINT_TEST_RESOURCE` set for the remaining items.

- [ ] Path with container id, `assignment/[3]/activation/validTo` (`Set-midPointRoleAssignment`).
- [ ] Delete of an assignment by `{ "id": 3 }` only (`Remove-midPointRoleAssignment`).
- [ ] Reference type `c:RoleType` and relation `org:manager` prefixes are resolved in JSON.
- [ ] Extension items via `-Property @{ 'extension/costCenter' = ... }` without namespace.
- [ ] `resolveNames` fills `targetRef.targetName` for assignments and `resourceRef.targetName` for shadows.
- [ ] Shape of shadow `attributes` in JSON (keys `ri:mail` or `mail`; values as arrays).
- [ ] Dead shadows are still in `linkRef` (relation `related`) and carry `dead: true`.
- [ ] Shape of the OperationResult on 4xx (the module searches for the first `message`).
- [ ] `password/value/clearValue` for the initial password on create.

## Not in scope (yet)

- A free-text reason for status changes: midPoint has no such item on users. `activation/disableReason`
  is a URI set by midPoint (explicit, mapped, deprovision, ...) and only read by the module.
- Bearer token / OIDC authentication, password reset, tasks, import / reconciliation.
