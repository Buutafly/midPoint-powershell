function Get-midPointOrg {
    <#
    .SYNOPSIS
    Gets midPoint orgs (organizational units).

    .DESCRIPTION
    Gets orgs by name, by OID, by an Axiom query filter, or all orgs.
    -Name returns nothing when no org has that name; -Oid stops with an error when the OID does not exist.
    The org's extension items are in the Extension property, by name without namespace
    ($org.Extension.costCenter); single values are unwrapped.

    .PARAMETER Name
    The exact org name.

    .PARAMETER Oid
    The org's OID.

    .PARAMETER Filter
    An Axiom query filter, e.g. 'name startsWith "OU "'.

    .PARAMETER All
    Returns all orgs.

    .PARAMETER MaxResults
    The maximum number of orgs returned by -Filter or -All.

    .EXAMPLE
    Get-midPointOrg 'Some Org'

    .EXAMPLE
    Get-midPointOrg -Filter 'name startsWith "OU "' | Select-Object Name, Identifier, Oid

    .EXAMPLE
    (Get-midPointOrg 'Some Org').Extension.costCenter
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All', Justification = 'Selects the parameter set.')]
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('midPointTools.Org')]
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
                    Find-midPointObject -Type orgs -Filter ('name = {0}' -f (ConvertTo-midPointAxiomString $n)) | ConvertTo-midPointOrgObject
                }
            }
            'Oid' {
                foreach ($o in $Oid) { Get-midPointObjectByOid -Type orgs -Oid $o | ConvertTo-midPointOrgObject }
            }
            'Filter' { Find-midPointObject -Type orgs -Filter $Filter -MaxResults $MaxResults | ConvertTo-midPointOrgObject }
            'All' { Find-midPointObject -Type orgs -MaxResults $MaxResults | ConvertTo-midPointOrgObject }
        }
    }
}
