function Get-midPointAttributeMismatch {
    # Returns one text per expected attribute that does not match the shadow (empty = all match).
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [object] $Shadow,
        [hashtable] $Expected
    )

    if (-not $Expected) { return }
    foreach ($name in $Expected.Keys) {
        $want = @($Expected[$name] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        $haveRaw = if ($Shadow.Attributes.ContainsKey($name)) { $Shadow.Attributes[$name] } else { $null }
        $have = @($haveRaw | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })

        $ok = if ($want.Count -eq 0) {
            $have.Count -eq 0
        }
        else {
            @($want | Where-Object { $have -notcontains $_ }).Count -eq 0
        }
        if (-not $ok) {
            "$name is '$($have -join ', ')', expected '$($want -join ', ')'"
        }
    }
}
