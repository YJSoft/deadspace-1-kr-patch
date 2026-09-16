param(
    [Parameter(Mandatory = $true)]
    [string]$NsisRoot,
    [Parameter(Mandatory = $true)]
    [string]$OriginalTextAssets,
    [Parameter(Mandatory = $true)]
    [string]$OriginalLocalization,
    [string]$EaTextAssets,
    [string]$EaLocalization,
    [string]$LegacyTextAssets,
    [string]$LegacyLocalization,
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

$sources = @(
    [ordered]@{
        Path = $OriginalTextAssets
        ExpectedHash = "85F9474ABA01FAA369EF60494EBC1988D04149DD54BD1D4D5DC9B073E335986F"
        File = "text_assets/text_assets_global.str"
        Target = $TargetTextAssets
        Kind = "steam"
    },
    [ordered]@{
        Path = $OriginalLocalization
        ExpectedHash = "5DA12D429E6918ADAA9F68381F27170F92C9236BF36D6D192B37D7CF641B0B47"
        File = "text_assets/text/12F4D5F8.str"
        Target = $TargetLocalization
        Kind = "steam"
    }
)

if ([string]::IsNullOrWhiteSpace($EaTextAssets) -xor
    [string]::IsNullOrWhiteSpace($EaLocalization)) {
    throw "EaTextAssets and EaLocalization must be supplied together."
}
if (-not [string]::IsNullOrWhiteSpace($EaTextAssets)) {
    $sources += @(
        [ordered]@{
            Path = $EaTextAssets
            ExpectedHash = "B68298A64BFD0F173BE7DA0427874A15823C32BE446919FD9818FB1812A947A8"
            File = "text_assets/text_assets_global.str"
            Target = $TargetTextAssets
            Kind = "ea-app"
        },
        [ordered]@{
            Path = $EaLocalization
            ExpectedHash = "C27FD36F4416AEF63E17DC3A5803BDB72418A702C277BF8BC31A26298C12BDF0"
            File = "text_assets/text/D8CBB618.str"
            Target = $TargetLocalization
            Kind = "ea-app"
        }
    )
}

if ([string]::IsNullOrWhiteSpace($LegacyTextAssets) -xor
    [string]::IsNullOrWhiteSpace($LegacyLocalization)) {
    throw "LegacyTextAssets and LegacyLocalization must be supplied together."
}
if (-not [string]::IsNullOrWhiteSpace($LegacyTextAssets)) {
    $sources += @(
        [ordered]@{
            Path = $LegacyTextAssets
            ExpectedHash = "CCB906F6AC651E0E1C3E85E247C94CA11D96CA03F1B53A88B6EF679C2A32F3E1"
            File = "text_assets/text_assets_global.str"
            Target = $TargetTextAssets
            Kind = "legacy-upgrade"
        },
        [ordered]@{
            Path = $LegacyLocalization
            ExpectedHash = "30159AA3748058AC639839DEFB9CC233DBE7158CA0B09538CDC5DBC27BABE0BC"
            File = "text_assets/text/D8CBB618.str"
            Target = $TargetLocalization
            Kind = "legacy-upgrade"
        }
    )
}

foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath $source.Path)) {
        throw "VPatch source is missing: $($source.Path)"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $source.Path).Hash
    if ($actual -ne $source.ExpectedHash) {
        throw "Not a supported source: $($source.Path) (SHA256=$actual)"
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
        foreach ($source in $sources) {
            & $genPat $source.Path $source.Target (Split-Path -Leaf $workPatch) /B=64
            if ($LASTEXITCODE -ne 0) {
                throw "GenPat failed for $($source.File) ($($source.Kind)): $LASTEXITCODE"
            }
        }
    }
    finally {
        Pop-Location
    }

    $outputDirectory = Split-Path -Parent $OutputPatch
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Copy-Item -LiteralPath $workPatch -Destination $OutputPatch -Force

    $manifest = [ordered]@{
        format = 2
        patch = [ordered]@{
            file = "deadspace1-kr-v0.1.pat"
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPatch).Hash
        }
        inputs = @($sources | ForEach-Object {
            [ordered]@{
                file = $_.File
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.Path).Hash
                kind = $_.Kind
            }
        })
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
