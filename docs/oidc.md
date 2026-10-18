# Bearer token / OIDC login (work in progress, branch `feature/oidc-login`)

Status 2026-10-18: research done, design agreed with the user, **nothing built yet**. This file becomes the user
documentation once the feature is built; until then it holds the research and the plan.

## How it works

- HTTP Basic (today): every request carries `Authorization: Basic base64(user:password)`; midPoint checks the password.
- Bearer token: an identity provider (IdP, e.g. Entra ID or Keycloak) issues an access token; every request carries
  `Authorization: Bearer <token>`. midPoint never sees a password, it only checks the token.
- The token is a JWT (`header.payload.signature`) with claims such as `iss` (issuer), `aud` (audience), `exp`
  (expiry, typically 60-90 minutes), `sub`, `preferred_username`, `azp` (client ID). The IdP signs it; midPoint
  checks signature and expiry with the IdP's public keys (JWKS), without calling the IdP per request.
- OIDC discovery: `<issuer>/.well-known/openid-configuration` lists the token endpoint and the JWKS URL.
- Client credentials flow (scripts, service principal): `POST` to the token endpoint with
  `grant_type=client_credentials`, client ID, secret and (Entra) `scope=api://<app>/.default`. No refresh token;
  a new token is requested with the secret.

## midPoint 4.10 (from the documentation, to be confirmed on the test instance)

Sources: [OIDC module](https://docs.evolveum.com/midpoint/reference/support-4.10/security/authentication/flexible-authentication/modules/oidc/),
[OIDC for REST](https://docs.evolveum.com/midpoint/reference/support-4.10/security/authentication/flexible-authentication/modules/oidc/rest/).

- Security policy (flexible authentication): an `oidc` module with `resourceServer` (REST; `client` is the GUI
  login) and a sequence on the channel `http://midpoint.evolveum.com/xml/ns/public/common/channels-3#rest`.
- `resourceServer/jwt` (or `opaqueToken`): keys from `issuerUri` (discovery), `jwkSetUri`, a certificate or a key;
  `nameOfUsernameClaim` (default `sub`), `trustedAlgorithm`, `realm` (for `WWW-Authenticate`).
- The claim value names the midPoint **user** (`focusType`, default `UserType`); no user is created. Only that user's
  normal midPoint authorizations apply (as with Basic, e.g. `Tests/Integration/midpoint/030-role-api.xml`).
- Several REST sequences are allowed (e.g. Basic and OIDC), but only one OIDC sequence is used (the first).
- Typical claim per IdP: Keycloak client credentials `preferred_username` = `service-account-<clientId>`;
  Entra ID client credentials have no `preferred_username`, the client ID is in `azp` (v2 tokens) / `appid` (v1).
  Entra tokens must be requested for the midPoint app registration ("Expose an API"), not for Microsoft Graph.

Draft snippet (example hosts only; to be checked in the integration run):

```xml
<authentication>
    <modules>
        <httpBasic>
            <identifier>httpBasic</identifier>
        </httpBasic>
        <oidc>
            <identifier>oidcRest</identifier>
            <resourceServer>
                <jwt>
                    <issuerUri>https://idp.example.com/realms/example</issuerUri>
                    <nameOfUsernameClaim>preferred_username</nameOfUsernameClaim>
                </jwt>
            </resourceServer>
        </oidc>
    </modules>
    <sequence>
        <identifier>rest-default</identifier>
        <channel>
            <channelId>http://midpoint.evolveum.com/xml/ns/public/common/channels-3#rest</channelId>
            <default>true</default>
            <urlSuffix>rest-default</urlSuffix>
        </channel>
        <module>
            <identifier>httpBasic</identifier>
            <order>10</order>
            <necessity>sufficient</necessity>
        </module>
        <module>
            <identifier>oidcRest</identifier>
            <order>20</order>
            <necessity>sufficient</necessity>
        </module>
    </sequence>
</authentication>
```

## Open questions (the integration run must answer them)

1. Is the claim value matched against the user's `name`?
2. Basic and OIDC together: one sequence with both modules (module chosen by the header scheme) or a separate
   sequence selected by `urlSuffix` (and what URL then)?
3. Answer to an expired / garbled token: status, body, `WWW-Authenticate`.
4. Is `aud` checked at all (a token for another API of the same issuer)?
5. Does the API role work unchanged for the token's user?

## Decisions (user, 2026-10-18)

- IdP not decided yet: build generic OIDC (issuer discovery or explicit token endpoint), examples for Entra ID and
  Keycloak in the docs.
- Flow in this piece of work: **client credentials only**. `-AccessToken`, device code or browser login can be added
  later without breaking changes.
- The client secret may stay in memory (SecureString, never on disk) to renew the token automatically.
- New module dependencies (e.g. MSAL.PS) only as optional ones: not in `RequiredModules`; the parameter set that
  needs one loads it on first use (`Import-Module ... -ErrorAction Stop`) with an install hint. Client credentials
  needs none (plain `Invoke-RestMethod`).

## Plan

- `Connect-midPoint`: default set `Credential` unchanged; new set with `-Issuer <uri>` (discovery) or
  `-TokenEndpoint <uri>`, `-ClientCredential <PSCredential>` (user = client ID, password = secret, like
  `Connect-AzAccount -ServicePrincipal`), `-Scope <string[]>`; shared `-Uri`, `-SkipCertificateCheck` (midPoint
  only), `-TimeoutSec`, `-PassThru`. Warn on http.
- New `midPointTools/Private/OAuth.ps1`: `Invoke-midPointTokenRequest` (thin mockable wrapper around
  Invoke-RestMethod, logs neither body nor response), `Get-midPointTokenEndpoint` (discovery),
  `Get-midPointAccessToken` (token as SecureString + ExpiresAt from `expires_in`; IdP `error_description` in the
  error, never the secret), `ConvertFrom-midPointJwt` (claims only, for `exp` and diagnostics).
- Session: `AuthType = 'Bearer'`, `AccessToken` (SecureString), `TokenExpiresAt`, `TokenSource` (endpoint,
  client credential, scope) for renewal; `Credential = $null`.
- `Invoke-midPointRestMethod` stays the only place that builds `Authorization` (Basic or Bearer). Renew when the
  token expires within 60 s; on 401 renew once and retry; then a clear error ("access token expired at ..." /
  "no midPoint user named after the claim?"). Never log the token.
- `Get-midPointSession` (+ format file): `TokenExpiresAt`. `Disconnect-midPoint` drops token and client secret.
- Unit tests (mocked HTTP): parameter sets, discovery, token request body, Bearer header, masking (Verbose / Debug /
  output), renewal, 401 retry and expiry error, previous session kept on failure.
- Integration test: own `Describe`, skipped unless `MIDPOINT_TOKEN_CLIENT_ID`, `MIDPOINT_TOKEN_CLIENT_SECRET` and
  `MIDPOINT_TOKEN_ISSUER` or `MIDPOINT_TOKEN_ENDPOINT` are set (optional `MIDPOINT_TOKEN_SCOPE`,
  `MIDPOINT_TOKEN_EXPECTED_USER`, `MIDPOINT_TOKEN_URL_SUFFIX`). Prints the claims (never the token), `GET self`,
  a search, a forced renewal, the answer to a garbled token, Basic alongside. Document the variables in the test
  header, `settings.example.ps1` and `docs/integration-tests.md`.
- Docs: this file as user documentation, README "Authentication and security", CHANGELOG `[Unreleased]`, NOTES.md
  (own lines), `docs/rest-notes.md` after the run.
- On the user's side: an app registration (Entra ID) or client (Keycloak), the midPoint security policy, and a
  midPoint user named after the claim value with the API role.
