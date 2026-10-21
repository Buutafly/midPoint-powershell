function Add-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Makes a midPoint user a member (or e.g. manager) of one or more orgs.

    .DESCRIPTION
    Adds an assignment with targetRef to each org, optionally with its own status and validity.
    midPoint then adds the orgs to the user's parentOrgRef and provisions what the orgs induce, as for an
    assignment made in the GUI. Several orgs in -Org go into one modification (one PATCH).
    To switch a user from one org to another in one modification, use Move-midPointOrgAssignment.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Org
    One or more orgs: name, OID, or an object from Get-midPointOrg. All of them are assigned in one
    modification, with the same relation, status and validity.

    .PARAMETER Relation
    The relation, e.g. manager. Without it midPoint uses the default relation (member).

    .PARAMETER AdministrativeStatus
    Enabled or Disabled for this assignment only.

    .PARAMETER ValidFrom
    The assignment is active from this point in time.

    .PARAMETER ValidTo
    The assignment is active until this point in time.

    .PARAMETER PassThru
    Returns the user's assignments of these orgs.

    .EXAMPLE
    Add-midPointOrgAssignment jack -Org 'Some Org'

    .EXAMPLE
    Add-midPointOrgAssignment jack -Org 'Some Org' -ValidTo (Get-Date).AddDays(30) -PassThru

    .EXAMPLE
    Add-midPointOrgAssignment jack -Org 'Some Org', 'Other Org'

    Makes jack a member of both orgs in one modification.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.OrgAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1)]
        [object[]] $Org,

        [string] $Relation,

        [ValidateSet('Enabled', 'Disabled')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,

        [switch] $PassThru
    )

    begin {
        $orgOids = @(foreach ($t in $Org) { Resolve-midPointObjectOid -InputObject $t -Type orgs })
    }

    process {
        Add-midPointAssignment -Kind Org -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Org -TargetOid $orgOids
    }
}
