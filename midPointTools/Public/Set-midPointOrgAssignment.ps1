function Set-midPointOrgAssignment {
    <#
    .SYNOPSIS
    Changes the status or validity of an existing org assignment.

    .DESCRIPTION
    Changes assignment[id]/activation of the user's assignment of the org without removing it,
    e.g. to extend validTo or to suspend the assignment. If the user has the org assigned more
    than once (e.g. with different relations), select one with -AssignmentId.

    .PARAMETER Identity
    The user: name, OID, or an object from Get-midPointUser.

    .PARAMETER Org
    The org: name, OID, or an object from Get-midPointOrg.

    .PARAMETER AssignmentId
    The assignment's container id (see Get-midPointOrgAssignment).

    .PARAMETER AdministrativeStatus
    Enabled, Disabled, or None. None removes the explicit status, so the validity dates decide again.

    .PARAMETER ValidFrom
    The assignment is active from this point in time.

    .PARAMETER ValidTo
    The assignment is active until this point in time.

    .PARAMETER ClearValidFrom
    Removes validFrom.

    .PARAMETER ClearValidTo
    Removes validTo.

    .PARAMETER PassThru
    Returns the assignment after the change.

    .EXAMPLE
    Set-midPointOrgAssignment jack -Org 'Some Org' -ValidTo (Get-Date).AddMonths(6)

    .EXAMPLE
    Set-midPointOrgAssignment jack -Org 'Some Org' -AdministrativeStatus Disabled
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The shared assignment code calls ShouldProcess on this cmdlet.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.OrgAssignment')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('UserOid', 'Oid')]
        [object] $Identity,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [Alias('OrgOid')]
        [object] $Org,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Nullable[long]] $AssignmentId,

        [ValidateSet('Enabled', 'Disabled', 'None')]
        [string] $AdministrativeStatus,

        [datetime] $ValidFrom,
        [datetime] $ValidTo,
        [switch] $ClearValidFrom,
        [switch] $ClearValidTo,

        [switch] $PassThru
    )

    process {
        Set-midPointAssignment -Kind Org -Cmdlet $PSCmdlet -Parameters $PSBoundParameters -Target $Org
    }
}
