# Copy to settings.local.ps1 (git ignores *.local.ps1) and fill in your test instance.
# ./build/Invoke-Tests.ps1 -Integration loads it before the tests run.
$env:MIDPOINT_URI = 'https://midpoint.example.com/midpoint'
$env:MIDPOINT_USER = 'midpointtools-api'
$env:MIDPOINT_PASSWORD = ''          # never commit a password
# $env:MIDPOINT_SKIP_CERT_CHECK = '1'

# With the example objects from Tests/Integration/midpoint (docs/integration-tests.md):
$env:MIDPOINT_TEST_ROLE = 'midPointTools Test Role'
$env:MIDPOINT_TEST_RESOURCE = 'midPointTools Test Resource'   # a manual resource is detected by its connector
