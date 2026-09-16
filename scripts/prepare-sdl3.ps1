param(
    [string]$Version = "3.2.8",
    [string]$ExpectedSha256 = "A674C6A6C7ECE82227CEEB879C35FD4716E351752FF8B030F8629D832D028FA7"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $repoRoot "third_party\DeadSpace2008Fixes\DeadSpaceFixes\lib\SDL3\x86"
$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ds1k-sdl-{0}-{1}" -f $Version, [guid]::NewGuid().ToString("N"))
$archive = Join-Path $workRoot ("SDL3-devel-{0}-VC.zip" -f $Version)
$expanded = Join-Path $workRoot "expanded"
$url = "https://github.com/libsdl-org/SDL/releases/download/release-$Version/SDL3-devel-$Version-VC.zip"

try {
    New-Item -ItemType Directory -Path $workRoot | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $archive

    $actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
    if ($actualSha256 -ne $ExpectedSha256) {
        throw "SDL3 archive checksum mismatch. Expected $ExpectedSha256, got $actualSha256."
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    $packageRoot = Join-Path $expanded ("SDL3-{0}" -f $Version)
    $source = Join-Path $packageRoot "lib\x86"
    $library = Join-Path $source "SDL3.lib"
    $runtime = Join-Path $source "SDL3.dll"

    if (-not (Test-Path -LiteralPath $library) -or -not (Test-Path -LiteralPath $runtime)) {
        throw "The SDL3 package does not contain the expected x86 library and runtime."
    }

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -LiteralPath $library -Destination (Join-Path $destination "SDL3.lib") -Force
    Copy-Item -LiteralPath $runtime -Destination (Join-Path $destination "SDL3.dll") -Force
    Write-Host "Prepared SDL $Version x86 from the verified official release archive."
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
