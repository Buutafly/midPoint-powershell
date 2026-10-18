function Complete-midPointCase {
    <#
    .SYNOPSIS
    Completes the open work items of a midPoint case.

    .DESCRIPTION
    Completes each open work item of the case with the given outcome, as an operator or approver
    would in the GUI. For a manual resource, Success means the requested change was done (midPoint
    then treats the account as created, changed or deleted), Failure that it could not be done.
    The connected user must be allowed to complete the work items, usually by being their assignee
    (for a manual resource: the operator in the resource's business configuration).

    .PARAMETER Case
    The case: OID, or an object from Get-midPointCase.

    .PARAMETER Outcome
    Success (default) or Failure.

    .PARAMETER Comment
    A comment stored with the work item.

    .PARAMETER WorkItemId
    Only this work item (its container id); by default all open work items of the case.

    .PARAMETER PassThru
    Returns the case after the change.

    .EXAMPLE
    Get-midPointCase -Resource 'Manual Resource' -Account jack -State Open | Complete-midPointCase

    .EXAMPLE
    Complete-midPointCase $caseOid -Outcome Failure -Comment 'Account could not be created'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('midPointTools.Case')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object] $Case,

        [ValidateSet('Success', 'Failure')]
        [string] $Outcome = 'Success',

        [string] $Comment,

        [Nullable[long]] $WorkItemId,

        [switch] $PassThru
    )

    process {
        $oid = Resolve-midPointObjectOid -InputObject $Case -Type cases
        $label = Get-midPointIdentityLabel $Case
        $raw = Get-midPointObjectByOid -Type cases -Oid $oid
        $open = @(Get-midPointOpenWorkItem -Case $raw)
        if ($null -ne $WorkItemId) {
            $open = @($open | Where-Object { [long](Get-midPointContainerId $_) -eq $WorkItemId })
        }
        if ($open.Count -eq 0) {
            Write-Warning "Case '$label' has no open work item$(if ($null -ne $WorkItemId) { " with id $WorkItemId" }). Nothing completed."
        }

        foreach ($item in $open) {
            $id = Get-midPointContainerId $item
            if ($null -eq $id) { throw [System.InvalidOperationException]::new("A work item of case '$label' has no container id.") }
            if (-not $PSCmdlet.ShouldProcess("$label ($oid)", "Complete work item $id with outcome $Outcome")) { continue }

            $output = [ordered]@{
                '@type' = 'c:AbstractWorkItemOutputType'
                outcome = $script:midPointOutcomeUri[$Outcome]
            }
            if ($Comment) { $output.comment = $Comment }
            $path = 'cases/{0}/workItems/{1}/complete' -f [uri]::EscapeDataString($oid), $id
            $null = Invoke-midPointRestMethod -Method POST -Path $path -Body ([ordered]@{ output = $output })
        }

        if ($PassThru) {
            Get-midPointObjectByOid -Type cases -Oid $oid -Options resolveNames | ConvertTo-midPointCaseObject
        }
    }
}
