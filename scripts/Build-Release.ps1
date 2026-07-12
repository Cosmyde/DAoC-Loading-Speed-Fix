# Created by Cosmy.
#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Configuration = 'Release'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$versionLines = Get-Content -LiteralPath (Join-Path $root 'VERSION') | Where-Object { $_ -match '^\d+\.\d+\.\d+$' }
if (@($versionLines).Count -ne 1) {
    throw 'VERSION must contain exactly one semantic version line.'
}
$version = [string]$versionLines[0]

& (Join-Path $PSScriptRoot 'Test-Project.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$dist = Join-Path $root 'dist'
$packageName = "DAoC-Loading-Speed-Fix-v$version"
$stage = Join-Path $dist $packageName
$zipPath = Join-Path $dist ($packageName + '.zip')

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
[void](New-Item -ItemType Directory -Path (Join-Path $stage 'Assets') -Force)

$runtimeFiles = @(
    'DAoC-Loading-Speed-Fix.ps1',
    'DAoC-Loading-Speed-Fix-Helper.ps1',
    'Run-DAoC-Loading-Speed-Fix.cmd',
    'README.md',
    'AUTHOR.txt',
    'VERSION',
    'LICENSE',
    'Assets\AppBanner.png',
    'Assets\AppIcon.ico'
)
foreach ($relative in $runtimeFiles) {
    $source = Join-Path $root $relative
    $destination = Join-Path $stage $relative
    $parent = Split-Path -Parent $destination
    [void](New-Item -ItemType Directory -Path $parent -Force)
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$manifestPath = Join-Path $stage 'SHA256SUMS.txt'
$manifestLines = New-Object System.Collections.ArrayList
[void]$manifestLines.Add('# Created by Cosmy.')
[void]$manifestLines.Add("# SHA-256 manifest for DAoC Loading Speed Fix version $version")
[void]$manifestLines.Add('')
foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.FullName -ne $manifestPath } | Sort-Object FullName) {
    $relative = $file.FullName.Substring($stage.Length + 1).Replace('\\','/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    [void]$manifestLines.Add("$hash  $relative")
}
[void]$manifestLines.Add('')
[void]$manifestLines.Add('# Created by Cosmy.')
[IO.File]::WriteAllText($manifestPath, (($manifestLines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

Compress-Archive -LiteralPath $stage -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "Release created: $zipPath" -ForegroundColor Green
Write-Host 'Created by Cosmy.'
