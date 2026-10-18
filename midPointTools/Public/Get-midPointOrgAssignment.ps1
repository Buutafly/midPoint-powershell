function Get-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Lists the org assignments (memberships) of a midPoint user.

    .DESCRIPTION
    Returns the user's direct org assignments with relation (member = default, manager, ...), assignment id,
    status and validity. Parent orgs of these orgs are not listed.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Org
    Only assignments of this org: name, OID, or an object from Get-midPointOrg.

    .EXAMPLE
    Get-midPointOrgAssignment jack

    .EXAMPLE
    Get-midPointOrgAssignment jack -Org 'Some Org' | Select-Object Org, Relation, ValidTo, EffectiveStatus
    #>
    [CmdletBinding()]
    [OutputType('midPointTools.OrgAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [Parameter(Position = 1)]
        [object] $Org
    )

    process {
        $target = if ($PSBoundParameters.ContainsKey('Org')) { $Org } else { $null }
        Get-midPointAssignmentList -Kind Org -Identity $Identity -Target $target
    }
}
