param(
    [Parameter(Mandatory = $true)][string]$FontDirectory,
    [Parameter(Mandatory = $true)][string]$OriginalFontDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
[xml]$archive = Get-Content -LiteralPath (Join-Path $FontDirectory "@archive.xml") -Raw
$names = @("russellsquare32", "briemakademistdsemibold32", "eurostileltstdbold32",
           "rotissansserif32", "serpentinebold32", "timesrussian32", "timesczhupl32")
$identities = [Collections.Generic.HashSet[uint32]]::new()

foreach ($name in $names) {
    $entries = @($archive.streams.stream | Where-Object {
        $_.type_name -eq "tg4h" -and $_.base_name -eq $name
    })
    if ($entries.Count -ne 1) { throw "Expected one TG4H for $name" }
    $relative = $entries[0].InnerText
    $header = [IO.File]::ReadAllBytes((Join-Path $FontDirectory $relative))
    $original = [IO.File]::ReadAllBytes((Join-Path $OriginalFontDirectory $relative))
    $identity = [BitConverter]::ToUInt32($header, 0x14)
    if ($identity -ne [Convert]::ToUInt32($entries[0].u18, 16) -or
        -not $identities.Add($identity)) { throw "Duplicate/mismatched identity: $name" }
    if ($header.Length -ne $original.Length) { throw "Changed identity/name layout: $name" }
    $descriptor = [BitConverter]::ToUInt32($header, 0x2C)
    $mutable = @(0x1C..0x23) + @(0x26) + @(($descriptor + 11)..($descriptor + 14))
    for ($offset = 0; $offset -lt $header.Length; ++$offset) {
        if ($offset -notin $mutable -and $header[$offset] -ne $original[$offset]) {
            throw "Identity/metadata changed at offset $offset in $name"
        }
    }
    $dataEntry = @($archive.streams.stream | Where-Object {
        $_.type_name -eq "tg4d" -and $_.base_name -eq $name
    })
    if ($dataEntry.Count -ne 1) { throw "Expected one TG4D for $name" }
    $dataLength = (Get-Item -LiteralPath (Join-Path $FontDirectory $dataEntry[0].InnerText)).Length
    if ([BitConverter]::ToUInt32($header, 0x1C) -ne $dataLength -or
        [BitConverter]::ToUInt32($header, ($descriptor + 11)) -ne $dataLength -or
        [BitConverter]::ToUInt16($header, 0x20) -ne 2048 -or
        [BitConverter]::ToUInt16($header, 0x22) -ne 1024 -or $header[0x26] -ne 10) {
        throw "Atlas layout/data length mismatch: $name"
    }
    Write-Host "PASS $name texture identity, original metadata, atlas layout"
}
