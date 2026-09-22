$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $repoRoot "dist"
$licenses = Join-Path $dist "licenses"
$developerTools = Join-Path $dist "developer-tools"
$assetBuild = Join-Path ([System.IO.Path]::GetTempPath()) "deadspace-1-kr-patch-assets"

if (-not (Test-Path -LiteralPath (Join-Path $dist "ds1k_utf8.dll")) -or
    -not (Test-Path -LiteralPath (Join-Path $dist "xinput1_3.dll")) -or
    -not (Test-Path -LiteralPath (Join-Path $dist "SDL3.dll"))) {
    throw "Native build output is incomplete. Run build.cmd first."
}

New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot "config\DeadSpaceFixes.ini") -Destination $dist -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "docs\INSTALL_KO.txt") -Destination (Join-Path $dist "README_KO.txt") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "THIRD_PARTY_NOTICES.txt") -Destination $dist -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "third_party\DeadSpace2008Fixes\LICENSE") -Destination (Join-Path $licenses "DeadSpace2008Fixes-MIT.txt") -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "third_party\licenses\DSOpt-MIT.txt") -Destination $licenses -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "third_party\licenses\MinHook-BSD-2-Clause.txt") -Destination $licenses -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "third_party\licenses\SDL3-zlib.txt") -Destination $licenses -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "third_party\NanumBarunGothic\OFL-1.1.txt") -Destination (Join-Path $licenses "NanumBarunGothic-OFL-1.1.txt") -Force

$toolNames = @("BuildPocAssets.exe", "GenerateTranslationCsv.exe")
foreach ($toolName in $toolNames) {
    $tool = Join-Path $assetBuild $toolName
    if (Test-Path -LiteralPath $tool) {
        New-Item -ItemType Directory -Path $developerTools -Force | Out-Null
        Copy-Item -LiteralPath $tool -Destination $developerTools -Force
    }
}

$distFull = (Resolve-Path -LiteralPath $dist).Path.TrimEnd("\")
$hashLines = Get-ChildItem -LiteralPath $dist -Recurse -File |
    Where-Object { $_.Name -ne "SHA256SUMS.txt" } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($distFull.Length).TrimStart("\") -replace "\\", "/"
        "{0} *{1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant(), $relative
    }
$hashLines | Set-Content -LiteralPath (Join-Path $dist "SHA256SUMS.txt") -Encoding ASCII
Write-Host "Staged dist and generated SHA256SUMS.txt."
