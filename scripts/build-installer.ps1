param(
    [Parameter(Mandatory = $true)]
    [string]$NsisRoot,
    [string]$GitHash,
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GitHash)) {
    $GitHash = (& git -C $repoRoot rev-parse --short=8 HEAD).Trim()
}
if ($GitHash -notmatch "^(dev|[0-9a-fA-F]{7,40})$") {
    throw "GitHash contains unsupported filename characters: $GitHash"
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "dist"
}

$makeNsis = Join-Path $NsisRoot "makensis.exe"
$script = Join-Path $repoRoot "packaging\installer.nsi"
$patch = Join-Path $repoRoot "packaging\patches\deadspace1-kr-v0.3.1.pat"
$required = @(
    $makeNsis,
    $script,
    $patch,
    (Join-Path $repoRoot "dist\ds1k_utf8.dll"),
    (Join-Path $repoRoot "dist\xinput1_3.dll"),
    (Join-Path $repoRoot "dist\SDL3.dll"),
    (Join-Path $repoRoot "dist\DeadSpaceFixes.ini"),
    (Join-Path $repoRoot "docs\INSTALL_KO.txt"),
    (Join-Path $repoRoot "THIRD_PARTY_NOTICES.txt"),
    (Join-Path $repoRoot "third_party\licenses\NSIS-COPYING.txt"),
    (Join-Path $repoRoot "third_party\licenses\VPatch-zlib.txt")
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Installer input is missing: $path"
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputFull = (Resolve-Path -LiteralPath $OutputDirectory).Path
& $makeNsis /INPUTCHARSET UTF8 "/DGIT_HASH=$GitHash" "/DOUTPUT_DIR=$outputFull" $script
if ($LASTEXITCODE -ne 0) {
    throw "makensis failed with exit code $LASTEXITCODE."
}

$installer = Join-Path $outputFull "DeadSpace1-KR-0.3.1.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    throw "makensis did not create the expected installer: $installer"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash
Write-Host "Built $installer"
Write-Host "SHA256=$hash"
Write-Output $installer
