function Get-midPointCase {
    <#
    .SYNOPSIS
    Gets midPoint cases, e.g. the requests a manual resource creates for its operators.

    .DESCRIPTION
    Gets cases by OID or searches them. A manual resource opens one case per requested change
    (create, modify, delete an account); the case's object is the resource and its target the account
    (shadow). -Resource returns the cases of one resource, -Account narrows them to one account name.
    -State selects open (not yet closed) or closed cases; by default all are returned.

    .PARAMETER Oid
    The case's OID.

    .PARAMETER Resource
    Only cases about this resource: name, OID, or an object with an Oid property.

    .PARAMETER Account
    Only cases for this account name. Matches the name midPoint's manual connector gives its cases
    ("Request to add '<account>' on '<resource>'"); the comparison is done after the search.

    .PARAMETER State
    Open (not closed), Closed, or All (default).

    .PARAMETER Filter
    An additional Axiom query filter, combined with -Resource and -State by 'and'.

    .PARAMETER MaxResults
    The maximum number of cases the search returns.

    .EXAMPLE
    Get-midPointCase -Resource 'Manual Resource' -State Open

    .EXAMPLE
    Get-midPointCase -Resource 'Manual Resource' -Account jack -State Open | Complete-midPointCase
    #>
    [CmdletBinding(DefaultParameterSetName = 'Search')]
    [OutputType('midPointTools.Case')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Oid', ValueFromPipelineByPropertyName)]
        [string[]] $Oid,

        [Parameter(ParameterSetName = 'Search', Position = 0)]
        [object] $Resource,

        [Parameter(ParameterSetName = 'Search')]
        [string] $Account,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateSet('Open', 'Closed', 'All')]
        [string] $State = 'All',

        [Parameter(ParameterSetName = 'Search')]
        [string] $Filter,

        [Parameter(ParameterSetName = 'Search')]
        [int] $MaxResults
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Oid') {
            foreach ($o in $Oid) { Get-midPointObjectByOid -Type cases -Oid $o -Options resolveNames | ConvertTo-midPointCaseObject }
            return
        }

        $clauses = [System.Collections.Generic.List[string]]::new()
        if ($PSBoundParameters.ContainsKey('Resource')) {
            $resourceOid = Resolve-midPointObjectOid -InputObject $Resource -Type resources
            $clauses.Add('objectRef matches (oid = {0})' -f (ConvertTo-midPointAxiomString $resourceOid))
        }
        if ($State -eq 'Closed') { $clauses.Add('state = "closed"') }
        if ($Filter) { $clauses.Add("($Filter)") }

        $cases = Find-midPointObject -Type cases -Filter ($clauses -join ' and ') -MaxResults $MaxResults -Options resolveNames |
            ConvertTo-midPointCaseObject
        if ($State -eq 'Open') { $cases = $cases | Where-Object State -NE 'closed' }
        if ($Account) { $cases = $cases | Where-Object { $_.Name -like "*'$([WildcardPattern]::Escape($Account))'*" } }
        $cases
    }
}
