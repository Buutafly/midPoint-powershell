function Get-midPointRole {
    <#
    .SYNOPSIS
    Gets midPoint roles.

    .DESCRIPTION
    Gets roles by name, by OID, by an Axiom query filter, or all roles.
    -Name returns nothing when no role has that name; -Oid stops with an error when the OID does not exist.

    .PARAMETER Name
    The exact role name.

    .PARAMETER Oid
    The role's OID.

    .PARAMETER Filter
    An Axiom query filter, e.g. 'name startsWith "App "'.

    .PARAMETER All
    Returns all roles.

    .PARAMETER MaxResults
    The maximum number of roles returned by -Filter or -All.

    .EXAMPLE
    Get-midPointRole 'Some Role'

    .EXAMPLE
    Get-midPointRole -Filter 'name startsWith "App "' | Select-Object Name, Oid
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All', Justification = 'Selects the parameter set.')]
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('midPointTools.Role')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name', ValueFromPipeline)]
        [string[]] $Name,

        [Parameter(Mandatory, ParameterSetName = 'Oid', ValueFromPipelineByPropertyName)]
        [string[]] $Oid,

        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [string] $Filter,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch] $All,

        [Parameter(ParameterSetName = 'Filter')]
        [Parameter(ParameterSetName = 'All')]
        [int] $MaxResults
    )

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Name' {
                foreach ($n in $Name) {
                    Find-midPointObject -Type roles -Filter ('name = {0}' -f (ConvertTo-midPointAxiomString $n)) | ConvertTo-midPointRoleObject
                }
            }
            'Oid' {
                foreach ($o in $Oid) { Get-midPointObjectByOid -Type roles -Oid $o | ConvertTo-midPointRoleObject }
            }
            'Filter' { Find-midPointObject -Type roles -Filter $Filter -MaxResults $MaxResults | ConvertTo-midPointRoleObject }
            'All' { Find-midPointObject -Type roles -MaxResults $MaxResults | ConvertTo-midPointRoleObject }
        }
    }
}
