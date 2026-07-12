# Created by Cosmy.
#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$requiredFiles = @(
    'DAoC-Loading-Speed-Fix.ps1',
    'DAoC-Loading-Speed-Fix-Helper.ps1',
    'Run-DAoC-Loading-Speed-Fix.cmd',
    'README.md',
    'AUTHOR.txt',
    'VERSION',
    'LICENSE',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'Assets\AppBanner.png',
    'Assets\AppIcon.ico'
)

$errors = New-Object System.Collections.ArrayList
function Add-Failure([string]$Message) { [void]$errors.Add($Message) }

foreach ($relative in $requiredFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing required file: $relative"
    }
}

$parseFiles = @('DAoC-Loading-Speed-Fix.ps1', 'DAoC-Loading-Speed-Fix-Helper.ps1')
foreach ($relative in $parseFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        Add-Failure "$relative parser error: $($parseError.Message) at $($parseError.Extent.StartLineNumber):$($parseError.Extent.StartColumnNumber)"
    }
}

$asciiCrLfFiles = @(
    'DAoC-Loading-Speed-Fix.ps1',
    'DAoC-Loading-Speed-Fix-Helper.ps1',
    'Run-DAoC-Loading-Speed-Fix.cmd',
    'README.md',
    'AUTHOR.txt',
    'VERSION',
    'LICENSE',
    'SECURITY.md',
    'CONTRIBUTING.md'
)
foreach ($relative in $asciiCrLfFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $bytes = [IO.File]::ReadAllBytes($path)
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
        Add-Failure "$relative contains non-ASCII bytes."
    }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    if ($text -match '(?<!\r)\n') {
        Add-Failure "$relative contains non-CRLF line endings."
    }
    if ($text -notmatch [regex]::Escape('Created by Cosmy.')) {
        Add-Failure "$relative does not contain the required attribution."
    }
}

$mainPath = Join-Path $root 'DAoC-Loading-Speed-Fix.ps1'
$helperPath = Join-Path $root 'DAoC-Loading-Speed-Fix-Helper.ps1'
if ((Test-Path $mainPath) -and (Test-Path $helperPath)) {
    $mainText = Get-Content -LiteralPath $mainPath -Raw
    $helperHash = (Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($mainText -notmatch [regex]::Escape("ExpectedHelperSha256 = '$helperHash'")) {
        Add-Failure 'The helper SHA-256 embedded in the main application does not match the helper file.'
    }
    if ($mainText -notmatch [regex]::Escape('Title="DAoC Loading Speed Fix - By Cosmy"')) {
        Add-Failure 'The production window title is missing.'
    }
    if ($mainText -notmatch [regex]::Escape('WindowState="Maximized"')) {
        Add-Failure 'The application is not configured to open maximized.'
    }
    if ($mainText -notmatch [regex]::Escape('Text="DAoC Loading Speed Fix - By Cosmy"')) {
        Add-Failure 'The visible application title is missing.'
    }

    try {
        $startMarker = "[xml]`$xaml = @'"
        $start = $mainText.IndexOf($startMarker, [StringComparison]::Ordinal)
        if ($start -lt 0) {
            Add-Failure 'Embedded WPF XAML was not found.'
        }
        else {
            $contentStart = $mainText.IndexOf("`n", $start)
            $end = $mainText.IndexOf("`n'@", $contentStart + 1, [StringComparison]::Ordinal)
            if ($contentStart -lt 0 -or $end -lt 0) {
                Add-Failure 'Embedded WPF XAML boundaries were not found.'
            }
            else {
                $xamlText = $mainText.Substring($contentStart + 1, $end - $contentStart - 1)
                [void][xml]$xamlText
            }
        }
    }
    catch {
        Add-Failure "Embedded WPF XAML is invalid: $($_.Exception.Message)"
    }
}

$allTextFiles = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { ($_.Extension -in @('.ps1','.cmd','.md','.txt','.yml','.yaml') -or $_.Name -in @('VERSION','LICENSE','.gitignore','.gitattributes')) -and $_.FullName -ne $PSCommandPath }
$forbiddenPatterns = @(
    'Add-MpPreference',
    'Remove-MpPreference',
    'Set-MpPreference',
    'EncodedCommand',
    'FromBase64String',
    'AmsiUtils',
    'amsiInitFailed',
    'VirtualProtect',
    'DisableRealtimeMonitoring',
    'DisableScriptScanning',
    'DisableTamperProtection'
)
foreach ($file in $allTextFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $forbiddenPatterns) {
        if ($text -match [regex]::Escape($pattern)) {
            Add-Failure "$($file.FullName.Substring($root.Length + 1)) contains forbidden text: $pattern"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host "Validation failed with $($errors.Count) issue(s):" -ForegroundColor Red
    foreach ($failure in $errors) { Write-Host " - $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Validation passed.' -ForegroundColor Green
Write-Host 'Created by Cosmy.'
exit 0
