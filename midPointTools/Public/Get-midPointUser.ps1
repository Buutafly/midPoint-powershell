function Get-midPointUser {
    <#
    .SYNOPSIS
    Gets midPoint users.

    .DESCRIPTION
    Gets users by name, by OID, by an Axiom query filter, or all users.
    -Name returns nothing when no user has that name; -Oid stops with an error when the OID does not exist.
    The full midPoint object is in the Raw property of each result.

    .PARAMETER Name
    The exact user name.

    .PARAMETER Oid
    The user's OID.

    .PARAMETER Filter
    An Axiom query filter, e.g. 'givenName = "Jack"' or 'name startsWith "MPTEST-"'.

    .PARAMETER All
    Returns all users. Combine with -MaxResults on large systems.

    .PARAMETER MaxResults
    The maximum number of users returned by -Filter or -All.

    .PARAMETER ResolveNames
    Asks midPoint to add the names of referenced objects (roles, orgs) to the Raw object.

    .EXAMPLE
    Get-midPointUser jack

    .EXAMPLE
    Get-midPointUser -Filter 'name startsWith "MPTEST-"' | Remove-midPointUser -Confirm:$false
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All', Justification = 'Selects the parameter set.')]
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('midPointTools.User')]
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
        [int] $MaxResults,

        [switch] $ResolveNames
    )

    process {
        $options = if ($ResolveNames) { @('resolveNames') } else { @() }
        switch ($PSCmdlet.ParameterSetName) {
            'Name' {
                foreach ($n in $Name) {
                    Find-midPointObject -Type users -Filter ('name = {0}' -f (ConvertTo-midPointAxiomString $n)) -Options $options |
                        ConvertTo-midPointUserObject
                }
            }
            'Oid' {
                foreach ($o in $Oid) {
                    Get-midPointObjectByOid -Type users -Oid $o -Options $options | ConvertTo-midPointUserObject
                }
            }
            'Filter' {
                Find-midPointObject -Type users -Filter $Filter -MaxResults $MaxResults -Options $options | ConvertTo-midPointUserObject
            }
            'All' {
                Find-midPointObject -Type users -MaxResults $MaxResults -Options $options | ConvertTo-midPointUserObject
            }
        }
    }
}
