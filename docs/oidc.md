# Token login (OIDC client credentials)

`Connect-midPoint` can log in with an access token from an identity provider (IdP, e.g. Entra ID or Keycloak)
instead of a midPoint password: the OAuth 2.0 **client credentials** flow, for scripts and scheduled jobs that run
as a service principal / service account.

Status 2026-10-19: built on branch `feature/oidc-login` (unit tests green); the integration run against a real
midPoint and IdP is still open (see "Open questions" below).

## Usage

```powershell
# Client ID as user name, client secret as password (like Connect-AzAccount -ServicePrincipal)
$client = Get-Credential -Message 'Client ID and secret'

# Keycloak: issuer of the realm (the token URL is read by OIDC discovery)
Connect-midPoint -Uri https://midpoint.example.com/midpoint -Issuer https://idp.example.com/realms/example -ClientCredential $client

# Entra ID: v2.0 issuer of the tenant, token for the midPoint app registration
Connect-midPoint -Uri https://midpoint.example.com/midpoint -Issuer https://login.microsoftonline.com/<tenant>/v2.0 `
    -ClientCredential $client -Scope 'api://<midPoint app ID>/.default'

# Without discovery: the token URL itself
Connect-midPoint -Uri https://midpoint.example.com/midpoint -TokenEndpoint https://idp.example.com/realms/example/protocol/openid-connect/token -ClientCredential $client

Get-midPointSession   # AuthType Bearer, TokenExpiresAt
```

- The cmdlet requests a token (`grant_type=client_credentials`, client ID and secret in the form body), then checks
  it with `GET /self` like the Basic login. On failure the previous session stays.
- Every request carries `Authorization: Bearer <token>`. A token that expires within 60 s is renewed before the
  request; when midPoint answers HTTP 401 to a token that was not just issued, the cmdlet renews it once and repeats
  the request.
- The access token and the client secret stay in memory (SecureString) until `Disconnect-midPoint`; nothing is
  written to disk. Neither appears in `-Verbose` / `-Debug` output, in errors or in `Get-midPointSession`.
- `-SkipCertificateCheck` applies to midPoint only; the IdP's certificate is always checked.
- Errors of the IdP show its `error` and `error_description` (e.g. `invalid_client: ...` for a wrong secret).
  HTTP 401 from midPoint with a fresh token shows midPoint's `WWW-Authenticate` header: midPoint does not accept
  tokens of this IdP, or no midPoint user is named after the token's user name claim.
- No extra module is needed (plain `Invoke-RestMethod`).

## Setup

On the identity provider:

- **Keycloak:** a confidential client with *Client authentication* and *Service accounts roles* enabled. Its tokens
  carry `preferred_username` = `service-account-<client ID>`. Issuer: `https://<host>/realms/<realm>`.
- **Entra ID:** an app registration for midPoint with *Expose an API* (Application ID URI `api://<app ID>`), and a
  client app with a client secret (can be the same app). Request the scope `api://<midPoint app ID>/.default`.
  Client credentials tokens have no `preferred_username`; the client ID is in `azp` (v2 tokens) or `appid` (v1).

In midPoint: an `oidc` authentication module with `resourceServer` in the security policy, used by a sequence on the
REST channel (draft below), and a midPoint **user** named after the claim value (`nameOfUsernameClaim`), with the
REST and model authorizations it needs (for the integration tests: the role `midPointTools API (test)`).
midPoint creates no user from a token.

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

## midPoint 4.10 (from the documentation, to be confirmed by the integration run)

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

`Tests/Integration/midPoint.Token.Integration.Tests.ps1` prints the answers; the test names in brackets.

1. Is the claim value matched against the user's `name`? ("midPoint accepts the token": prints which claims equal
   the name of the user `GET /self` returns.)
2. Basic and OIDC together: one sequence with both modules (module chosen by the header scheme) or a separate
   sequence selected by `urlSuffix` (and what URL then)? ("Basic still works next to the token" on the same URL;
   with `MIDPOINT_TOKEN_URL_SUFFIX` the test tries the candidate URLs.)
3. Answer to an expired / garbled token: status, body, `WWW-Authenticate`. ("answers bad tokens with 401": no
   header, garbled token, real token with a wrong signature. A really expired token is not part of the run; the
   forced renewal covers expiry on the module side.)
4. Is `aud` checked at all (a token for another API of the same issuer)? (`MIDPOINT_TOKEN_OTHER_SCOPE`.)
5. Does the API role work unchanged for the token's user? ("the API role works for the token user": creates,
   finds and deletes `MPTEST-<random>-TOK`.)

## Decisions (user, 2026-10-18)

- IdP not decided yet: build generic OIDC (issuer discovery or explicit token endpoint), examples for Entra ID and
  Keycloak in the docs.
- Flow in this piece of work: **client credentials only**. `-AccessToken`, device code or browser login can be added
  later without breaking changes.
- The client secret may stay in memory (SecureString, never on disk) to renew the token automatically.
- New module dependencies (e.g. MSAL.PS) only as optional ones: not in `RequiredModules`; the parameter set that
  needs one loads it on first use (`Import-Module ... -ErrorAction Stop`) with an install hint. Client credentials
  needs none (plain `Invoke-RestMethod`).

## Built (2026-10-19)

- `Connect-midPoint`: parameter sets `Credential` (default, unchanged), `Issuer` and `TokenEndpoint` with
  `-ClientCredential` and `-Scope`; warns on http for midPoint and for the IdP.
- `midPointTools/Private/OAuth.ps1`: `Invoke-midPointTokenRequest` (mockable wrapper, logs nothing),
  `Get-midPointTokenEndpoint` (discovery), `Get-midPointAccessToken` (token as SecureString, expiry from
  `expires_in`, else from the JWT's `exp`), `ConvertFrom-midPointJwt` (claims only, no signature check),
  `Request-midPointSessionToken` (renewal), `Get-midPointAuthorizationHeader` (Basic or Bearer).
- Session: `AuthType = 'Bearer'`, `AccessToken`, `TokenExpiresAt` (UTC), `TokenSource` (issuer, endpoint, client
  credential, scope); `Credential` is `$null`. The first request (`GET /self`) gets the token, so a 401 there is not
  retried.
- `Get-midPointSession`: `TokenExpiresAt` (local time; shown for Bearer only).
- Unit tests: `Tests/Public/OAuth.Tests.ps1`. Integration test: `Tests/Integration/midPoint.Token.Integration.Tests.ps1`
  (variables in its header and in `Tests/Integration/settings.example.ps1`).
- Client authentication at the IdP is `client_secret_post` (secret in the body); Entra ID and Keycloak accept it.
  `client_secret_basic`, `-AccessToken`, certificates, device code or browser login can be added later without
  breaking changes.
