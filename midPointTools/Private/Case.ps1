# Work item outcomes midPoint understands when a case is completed (REST: POST cases/<oid>/workItems/<id>/complete).
# For manual provisioning cases 'approve' means the operator did the change, 'reject' that it failed.
$script:midPointOutcomeUri = @{
    Success = 'http://midpoint.evolveum.com/xml/ns/public/model/approval/outcome#approve'
    Failure = 'http://midpoint.evolveum.com/xml/ns/public/model/approval/outcome#reject'
}

function Get-midPointOpenWorkItem {
    # Work items of a raw case that are not closed yet.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Case)

    @(Get-midPointProperty $Case 'workItem') | Where-Object {
        $null -ne $_ -and $null -eq (Get-midPointProperty $_ 'closeTimestamp')
    }
}

function ConvertTo-midPointCaseObject {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [object] $InputObject)

    process {
        $objectRef = Get-midPointProperty $InputObject 'objectRef'
        $targetRef = Get-midPointProperty $InputObject 'targetRef'
        $workItems = @(Get-midPointProperty $InputObject 'workItem' | Where-Object { $null -ne $_ } | ForEach-Object {
                [pscustomobject]@{
                    Id       = Get-midPointContainerId $_
                    Name     = ConvertFrom-midPointPolyString (Get-midPointProperty $_ 'name')
                    Assignee = @(Get-midPointProperty $_ 'assigneeRef' | ForEach-Object {
                            $n = ConvertFrom-midPointPolyString (Get-midPointProperty $_ 'targetName')
                            if ($n) { $n } else { [string](Get-midPointProperty $_ 'oid') }
                        } | Where-Object { $_ })
                    IsOpen   = $null -eq (Get-midPointProperty $_ 'closeTimestamp')
                    Outcome  = ConvertFrom-midPointQName (Get-midPointProperty (Get-midPointProperty $_ 'output') 'outcome')
                }
            })
        [pscustomobject]@{
            PSTypeName     = 'midPointTools.Case'
            Oid            = [string](Get-midPointProperty $InputObject 'oid')
            Name           = ConvertFrom-midPointPolyString (Get-midPointProperty $InputObject 'name')
            State          = Get-midPointProperty $InputObject 'state'
            Outcome        = ConvertFrom-midPointQName (Get-midPointProperty $InputObject 'outcome')
            Object         = ConvertFrom-midPointPolyString (Get-midPointProperty $objectRef 'targetName')
            ObjectOid      = [string](Get-midPointProperty $objectRef 'oid')
            Target         = ConvertFrom-midPointPolyString (Get-midPointProperty $targetRef 'targetName')
            TargetOid      = [string](Get-midPointProperty $targetRef 'oid')
            OpenWorkItems  = @($workItems | Where-Object IsOpen).Count
            WorkItem       = $workItems
            CloseTimestamp = ConvertFrom-midPointDateTime (Get-midPointProperty $InputObject 'closeTimestamp')
            Raw            = $InputObject
        }
    }
}
