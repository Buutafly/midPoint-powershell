function New-midPointUser {
    <#
    .SYNOPSIS
    Creates a midPoint user.

    .DESCRIPTION
    Creates a user with POST /users. midPoint then runs its normal processing (object template,
    roles, provisioning), as it would for a user created in the GUI.

    .PARAMETER Name
    The user name (midPoint 'name'), must be unique.

    .PARAMETER GivenName
    The given name.

    .PARAMETER FamilyName
    The family name.

    .PARAMETER FullName
    The full name. midPoint's object template often computes it from given and family name.

    .PARAMETER EmailAddress
    The e-mail address.

    .PARAMETER Description
    A free-text description.

    .PARAMETER Property
    Further items as path = value, e.g. @{ telephoneNumber = '+41 00 000 00 00'; 'extension/costCenter' = '4711' }.
    A path with '/' creates the nested containers.

    .PARAMETER Password
    The initial password.

    .PARAMETER AdministrativeStatus
    Enabled, Disabled or Archived. Without it midPoint decides (usually enabled).

    .PARAMETER ValidFrom
    The user is active from this point in time.

    .PARAMETER ValidTo
    The user is active until this point in time.

    .PARAMETER PassThru
    Returns the created user (read back from midPoint).

    .EXAMPLE
    New-midPointUser -Name jack -GivenName Jack -FamilyName Sparrow -EmailAddress jack@example.com

    .EXAMPLE
    $u = New-midPointUser -Name "MPTEST-$(Get-Random)" -ValidTo (Get-Date).AddDays(1) -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.User')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [string] $GivenName,
        [string] $FamilyName,
        [string] $FullName,
        [string] $EmailAddress,
        [string] $Description,

        [hashtable] $Property,

        [securestring] $Password,

        [ValidateSet('Enabled', 'Disabled', 'Archived')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,

        [switch] $PassThru
    )

    $user = [ordered]@{ name = $Name }
    foreach ($pair in @(
            @('GivenName', 'givenName'), @('FamilyName', 'familyName'), @('FullName', 'fullName'),
            @('EmailAddress', 'emailAddress'), @('Description', 'description'))) {
        if ($PSBoundParameters.ContainsKey($pair[0])) { $user[$pair[1]] = $PSBoundParameters[$pair[0]] }
    }
    if ($Property) {
        foreach ($key in $Property.Keys) {
            Set-midPointNestedValue -Target $user -Path $key -Value $Property[$key]
        }
    }
    if ($AdministrativeStatus) { Set-midPointNestedValue -Target $user -Path 'activation/administrativeStatus' -Value (ConvertTo-midPointActivationStatus $AdministrativeStatus) }
    if ($PSBoundParameters.ContainsKey('ValidFrom')) { Set-midPointNestedValue -Target $user -Path 'activation/validFrom' -Value (ConvertTo-midPointDateTime $ValidFrom) }
    if ($PSBoundParameters.ContainsKey('ValidTo')) { Set-midPointNestedValue -Target $user -Path 'activation/validTo' -Value (ConvertTo-midPointDateTime $ValidTo) }
    if ($Password) {
        $clear = [System.Net.NetworkCredential]::new('', $Password).Password
        Set-midPointNestedValue -Target $user -Path 'credentials/password/value' -Value ([ordered]@{ clearValue = $clear })
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Create midPoint user')) { return }

    $response = Invoke-midPointRestMethod -Method POST -Path 'users' -Body ([ordered]@{ user = $user })

    # 201 Created, the new OID is the last segment of the Location header (midPoint REST create operation).
    $location = $response.Headers.Location | Select-Object -First 1
    $oid = if ($location) { ([string]$location).TrimEnd('/').Split('/')[-1] } else { $null }
    if ($PassThru) {
        if ($oid) {
            Get-midPointUser -Oid $oid
        }
        else {
            Write-Verbose "midPoint returned no Location header for '$Name'; looking the user up by name."
            Get-midPointUser -Name $Name
        }
    }
}
