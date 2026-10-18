function Add-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Makes a midPoint user a member (or e.g. manager) of an org.

    .DESCRIPTION
    Adds an assignment with targetRef to the org, optionally with its own status and validity.
    midPoint then adds the org to the user's parentOrgRef and provisions what the org induces, as for an
    assignment made in the GUI.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Org
    The org: name, OID, or an object from Get-midPointOrg.

    .PARAMETER Relation
    The relation, e.g. manager. Without it midPoint uses the default relation (member).

    .PARAMETER AdministrativeStatus
    Enabled or Disabled for this assignment only.

    .PARAMETER ValidFrom
    The assignment is active from this point in time.

    .PARAMETER ValidTo
    The assignment is active until this point in time.

    .PARAMETER PassThru
    Returns the user's assignments of this org.

    .EXAMPLE
    Add-midPointOrgAssignment jack -Org 'Some Org'

    .EXAMPLE
    Add-midPointOrgAssignment jack -Org 'Some Org' -ValidTo (Get-Date).AddDays(30) -PassThru
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.OrgAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1)]
        [object] $Org,

        [string] $Relation,

        [ValidateSet('Enabled', 'Disabled')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,

        [switch] $PassThru
    )

    begin {
        $orgOid = Resolve-midPointObjectOid -InputObject $Org -Type orgs
    }

    process {
        Add-midPointAssignment -Kind Org -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Org -TargetOid $orgOid
    }
}
