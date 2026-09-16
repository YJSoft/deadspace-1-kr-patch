param(
    [Parameter(Mandatory = $true)]
    [string]$NsisRoot,
    [Parameter(Mandatory = $true)]
    [string]$OriginalTextAssets,
    [Parameter(Mandatory = $true)]
    [string]$OriginalLocalization,
    [string]$TargetTextAssets,
    [string]$TargetLocalization,
    [string]$OutputPatch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TargetTextAssets)) {
    $TargetTextAssets = Join-Path $repoRoot "dist\text_assets\text_assets_global.str"
}
if ([string]::IsNullOrWhiteSpace($TargetLocalization)) {
    $TargetLocalization = Join-Path $repoRoot "dist\text_assets\text\D8CBB618.str"
}
if ([string]::IsNullOrWhiteSpace($OutputPatch)) {
    $OutputPatch = Join-Path $repoRoot "packaging\patches\deadspace1-kr-v0.1.pat"
}

$expectedOriginals = @{
    $OriginalTextAssets = "CCB906F6AC651E0E1C3E85E247C94CA11D96CA03F1B53A88B6EF679C2A32F3E1"
    $OriginalLocalization = "30159AA3748058AC639839DEFB9CC233DBE7158CA0B09538CDC5DBC27BABE0BC"
}
foreach ($entry in $expectedOriginals.GetEnumerator()) {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($actual -ne $entry.Value) {
        throw "Not a supported clean Steam original: $($entry.Key) (SHA256=$actual)"
    }
}

$genPat = Join-Path $NsisRoot "Bin\GenPat.exe"
if (-not (Test-Path -LiteralPath $genPat)) {
    throw "GenPat.exe was not found under $NsisRoot."
}
foreach ($path in @($TargetTextAssets, $TargetLocalization)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Target STR is missing: $path"
    }
}

$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ds1k-vpatch-{0}" -f [guid]::NewGuid().ToString("N"))
$workPatch = Join-Path $workRoot "deadspace1-kr-v0.1.pat"
New-Item -ItemType Directory -Path $workRoot | Out-Null

try {
    Push-Location $workRoot
    try {
        & $genPat $OriginalTextAssets $TargetTextAssets (Split-Path -Leaf $workPatch) /B=64
        if ($LASTEXITCODE -ne 0) { throw "GenPat failed for text_assets_global.str: $LASTEXITCODE" }
        & $genPat $OriginalLocalization $TargetLocalization (Split-Path -Leaf $workPatch) /B=64
        if ($LASTEXITCODE -ne 0) { throw "GenPat failed for D8CBB618.str: $LASTEXITCODE" }
    }
    finally {
        Pop-Location
    }

    $outputDirectory = Split-Path -Parent $OutputPatch
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Copy-Item -LiteralPath $workPatch -Destination $OutputPatch -Force

    $manifest = [ordered]@{
        format = 1
        patch = [ordered]@{
            file = "deadspace1-kr-v0.1.pat"
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPatch).Hash
        }
        inputs = @(
            [ordered]@{ file = "text_assets/text_assets_global.str"; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OriginalTextAssets).Hash },
            [ordered]@{ file = "text_assets/text/D8CBB618.str"; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OriginalLocalization).Hash }
        )
        outputs = @(
            [ordered]@{ file = "text_assets/text_assets_global.str"; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetTextAssets).Hash },
            [ordered]@{ file = "text_assets/text/D8CBB618.str"; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetLocalization).Hash }
        )
    }
    $manifestPath = Join-Path $outputDirectory "manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Host "Generated $OutputPatch and $manifestPath"
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
