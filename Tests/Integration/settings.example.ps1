# Copy to settings.local.ps1 (git ignores *.local.ps1) and fill in your test instance.
# ./build/Invoke-Tests.ps1 -Integration loads it before the tests run.
$env:MIDPOINT_URI = 'https://midpoint.example.com/midpoint'
$env:MIDPOINT_USER = 'midpointtools-api'
$env:MIDPOINT_PASSWORD = ''          # never commit a password
# $env:MIDPOINT_SKIP_CERT_CHECK = '1'

# With the example objects from Tests/Integration/midpoint (docs/integration-tests.md):
$env:MIDPOINT_TEST_ROLE = 'midPointTools Test Role'
$env:MIDPOINT_TEST_RESOURCE = 'midPointTools Test Resource'   # a manual resource is detected by its connector
$env:MIDPOINT_TEST_ORG = 'midPointTools Test Org'

# Optional: a single-valued string extension item of UserType on your instance (local name, no namespace).
# $env:MIDPOINT_TEST_EXTENSION_ITEM = 'costCenter'

# Optional: token login (OIDC client credentials, docs/oidc.md). Tests/Integration/midPoint.Token.Integration.Tests.ps1
# runs when client ID, secret and issuer (or token endpoint) are set.
# $env:MIDPOINT_TOKEN_ISSUER = 'https://idp.example.com/realms/example'    # or https://login.microsoftonline.com/<tenant>/v2.0
# $env:MIDPOINT_TOKEN_ENDPOINT = ''        # instead of the issuer: the token URL
# $env:MIDPOINT_TOKEN_CLIENT_ID = ''
# $env:MIDPOINT_TOKEN_CLIENT_SECRET = ''   # never commit a secret
# $env:MIDPOINT_TOKEN_SCOPE = ''           # Entra ID: api://<midPoint app ID>/.default
# $env:MIDPOINT_TOKEN_EXPECTED_USER = 'midpointtools-api'
# $env:MIDPOINT_TOKEN_OTHER_SCOPE = ''     # e.g. the .default scope of Microsoft Graph: is aud checked?
# $env:MIDPOINT_TOKEN_URL_SUFFIX = ''      # urlSuffix of a separate REST sequence for the token
