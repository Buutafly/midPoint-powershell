function Get-midPointResource {
    <#
    .SYNOPSIS
    Gets midPoint resources and the type of their connector.

    .DESCRIPTION
    Gets resources by name or OID without contacting their connectors (noFetch), so it also works
    when a resource is down. ConnectorType is read from the resource's connector object, e.g.
    'ManualConnector' for a manual or semi-manual resource; it stays empty when the connector cannot
    be read (the connected user needs read access to connectors).

    .PARAMETER Name
    The exact resource name.

    .PARAMETER Oid
    The resource's OID.

    .EXAMPLE
    Get-midPointResource 'Some Resource'

    .EXAMPLE
    if ((Get-midPointResource 'Some Resource').IsManual) { 'Accounts are created through cases' }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    [OutputType('midPointTools.Resource')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Name', ValueFromPipeline)]
        [string[]] $Name,

        [Parameter(Mandatory, ParameterSetName = 'Oid', ValueFromPipelineByPropertyName)]
        [string[]] $Oid
    )

    process {
        $raw = if ($PSCmdlet.ParameterSetName -eq 'Name') {
            foreach ($n in $Name) {
                Find-midPointObject -Type resources -Filter ('name = {0}' -f (ConvertTo-midPointAxiomString $n)) -Options noFetch
            }
        }
        else {
            foreach ($o in $Oid) { Get-midPointObjectByOid -Type resources -Oid $o -Options noFetch }
        }

        foreach ($r in @($raw)) {
            if ($null -eq $r) { continue }
            $connectorOid = [string](Get-midPointProperty (Get-midPointProperty $r 'connectorRef') 'oid')
            $connector = $null
            if ($connectorOid) {
                try { $connector = Get-midPointObjectByOid -Type connectors -Oid $connectorOid }
                catch { Write-Verbose "Connector $connectorOid of resource $(Get-midPointProperty $r 'oid') is not readable: $($_.Exception.Message)" }
            }
            ConvertTo-midPointResourceObject -InputObject $r -Connector $connector
        }
    }
}
