function ConvertTo-midPointUserObject {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [object] $InputObject)

    process {
        $activation = Get-midPointProperty $InputObject 'activation'
        [pscustomobject]@{
            PSTypeName           = 'midPointTools.User'
            Oid                  = [string](Get-midPointProperty $InputObject 'oid')
            Name                 = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'name')
            FullName             = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'fullName')
            GivenName            = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'givenName')
            FamilyName           = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'familyName')
            EmailAddress         = Get-midPointProperty $InputObject 'emailAddress'
            Description          = Get-midPointProperty $InputObject 'description'
            AdministrativeStatus = Get-midPointProperty $activation 'administrativeStatus'
            EffectiveStatus      = Get-midPointProperty $activation 'effectiveStatus'
            ValidFrom            = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'validFrom')
            ValidTo              = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'validTo')
            Raw                  = $InputObject
        }
    }
}

function ConvertTo-midPointActivationObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $InputObject)

    $activation = Get-midPointProperty $InputObject 'activation'
    [pscustomobject]@{
        PSTypeName           = 'midPointTools.Activation'
        Oid                  = [string](Get-midPointProperty $InputObject 'oid')
        Name                 = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'name')
        AdministrativeStatus = Get-midPointProperty $activation 'administrativeStatus'
        EffectiveStatus      = Get-midPointProperty $activation 'effectiveStatus'
        ValidityStatus       = Get-midPointProperty $activation 'validityStatus'
        ValidFrom            = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'validFrom')
        ValidTo              = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'validTo')
        DisableReason        = ConvertFrom-midPointQName (Get-midPointProperty $activation 'disableReason')
        DisableTimestamp     = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'disableTimestamp')
        EnableTimestamp      = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'enableTimestamp')
        LockoutStatus        = Get-midPointProperty $activation 'lockoutStatus'
        Raw                  = $activation
    }
}

function ConvertTo-midPointRoleObject {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [object] $InputObject)

    process {
        [pscustomobject]@{
            PSTypeName  = 'midPointTools.Role'
            Oid         = [string](Get-midPointProperty $InputObject 'oid')
            Name        = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'name')
            DisplayName = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'displayName')
            Description = Get-midPointProperty $InputObject 'description'
            Raw         = $InputObject
        }
    }
}

function ConvertTo-midPointAssignmentObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Assignment,
        [Parameter(Mandatory)] [object] $User
    )

    $targetRef = Get-midPointProperty $Assignment 'targetRef'
    $activation = Get-midPointProperty $Assignment 'activation'
    [pscustomobject]@{
        PSTypeName           = 'midPointTools.RoleAssignment'
        User                 = ConvertFrom-midPointPolyString (Get-midPointProperty $User 'name')
        UserOid              = [string](Get-midPointProperty $User 'oid')
        Role                 = ConvertFrom-midPointPolyString (Get-midPointProperty $targetRef 'targetName')
        RoleOid              = [string](Get-midPointProperty $targetRef 'oid')
        Relation             = ConvertFrom-midPointQName (Get-midPointProperty $targetRef 'relation')
        AssignmentId         = Get-midPointProperty $Assignment 'id'
        AdministrativeStatus = Get-midPointProperty $activation 'administrativeStatus'
        EffectiveStatus      = Get-midPointProperty $activation 'effectiveStatus'
        ValidFrom            = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'validFrom')
        ValidTo              = ConvertFrom-midPointDateTime (Get-midPointProperty $activation 'validTo')
        Raw                  = $Assignment
    }
}

function ConvertFrom-midPointAttributeContainer {
    # Shadow 'attributes' -> hashtable. Keys lose their namespace prefix ('ri:mail' -> 'mail'),
    # single-element arrays become scalars.
    # TODO(verify): key format of shadow attributes in 4.10 JSON (prefixed or with @ns).
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowNull()] [object] $Attributes)

    $result = @{}
    if ($null -eq $Attributes) { return $result }
    foreach ($p in $Attributes.PSObject.Properties) {
        if ($p.Name.StartsWith('@')) { continue }
        $key = ($p.Name -split ':')[-1]
        $value = $p.Value
        if ($value -is [array] -and $value.Count -eq 1) { $value = $value[0] }
        $result[$key] = $value
    }
    $result
}

function ConvertTo-midPointShadowObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $InputObject,
        [object] $User
    )

    $resourceRef = Get-midPointProperty $InputObject 'resourceRef'
    $exists = Get-midPointProperty $InputObject 'exists'
    [pscustomobject]@{
        PSTypeName           = 'midPointTools.Shadow'
        Oid                  = [string](Get-midPointProperty $InputObject 'oid')
        Name                 = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'name')
        User                 = ConvertFrom-midPointPolyString (Get-midPointProperty $User 'name')
        UserOid              = [string](Get-midPointProperty $User 'oid')
        Resource             = ConvertFrom-midPointPolyString (Get-midPointProperty $resourceRef 'targetName')
        ResourceOid          = [string](Get-midPointProperty $resourceRef 'oid')
        Kind                 = Get-midPointProperty $InputObject 'kind'
        Intent               = Get-midPointProperty $InputObject 'intent'
        ObjectClass          = ConvertFrom-midPointQName (Get-midPointProperty $InputObject 'objectClass')
        Situation            = Get-midPointProperty $InputObject 'synchronizationSituation'
        Exists               = if ($null -eq $exists) { $true } else { [bool]$exists }
        Dead                 = [bool](Get-midPointProperty $InputObject 'dead')
        AdministrativeStatus = Get-midPointProperty (Get-midPointProperty $InputObject 'activation') 'administrativeStatus'
        Attributes           = ConvertFrom-midPointAttributeContainer (Get-midPointProperty $InputObject 'attributes')
        Raw                  = $InputObject
    }
}
