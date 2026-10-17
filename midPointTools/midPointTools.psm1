# midPointTools - PowerShell cmdlets for the Evolveum midPoint REST API.

$script:midPointSession = $null

foreach ($folder in 'Private', 'Public') {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' -File -ErrorAction SilentlyContinue) {
        . $file.FullName
    }
}

Export-ModuleMember -Function (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File).BaseName
