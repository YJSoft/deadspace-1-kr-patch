param(
    [string]$Version = "3.12",
    [string]$ExpectedSha256 = "56581F90DB321581C5381193D796FFFCF2D24B2F8FED2160A6C6A3BAA67F2C4F"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ds1k-nsis-{0}-{1}" -f $Version, [guid]::NewGuid().ToString("N"))
$archive = Join-Path $workRoot ("nsis-{0}.zip" -f $Version)
$url = "https://sourceforge.net/projects/nsis/files/NSIS%203/$Version/nsis-$Version.zip/download"

New-Item -ItemType Directory -Path $workRoot | Out-Null
Invoke-WebRequest -Uri $url -OutFile $archive

$actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
if ($actualSha256 -ne $ExpectedSha256) {
    throw "NSIS archive checksum mismatch. Expected $ExpectedSha256, got $actualSha256."
}

Expand-Archive -LiteralPath $archive -DestinationPath $workRoot
$nsisRoot = Join-Path $workRoot ("nsis-{0}" -f $Version)
$makeNsis = Join-Path $nsisRoot "makensis.exe"
$genPat = Join-Path $nsisRoot "Bin\GenPat.exe"
$vpatch = Join-Path $nsisRoot "Plugins\x86-unicode\VPatch.dll"

foreach ($required in @($makeNsis, $genPat, $vpatch)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "The verified NSIS archive is missing: $required"
    }
}

Write-Host "Prepared verified NSIS $Version at $nsisRoot"
Write-Output $nsisRoot
