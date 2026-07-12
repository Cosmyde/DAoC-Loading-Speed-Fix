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
    'Assets\AppIcon.ico',
    '.gitattributes',
    '.gitignore',
    '.github\workflows\validate.yml',
    '.github\ISSUE_TEMPLATE\bug_report.yml',
    'SHA256SUMS.txt'
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

$versionPath = Join-Path $root 'VERSION'
$authorPath = Join-Path $root 'AUTHOR.txt'
$workflowPath = Join-Path $root '.github\workflows\validate.yml'
$versionLines = @()
if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
    $versionLines = @(Get-Content -LiteralPath $versionPath | Where-Object { $_ -match '^\d+\.\d+\.\d+$' })
    if ($versionLines.Count -ne 1) {
        Add-Failure 'VERSION must contain exactly one semantic version line.'
    }
}

$mainPath = Join-Path $root 'DAoC-Loading-Speed-Fix.ps1'
$helperPath = Join-Path $root 'DAoC-Loading-Speed-Fix-Helper.ps1'
if ((Test-Path $mainPath) -and (Test-Path $helperPath)) {
    $mainText = Get-Content -LiteralPath $mainPath -Raw
    $helperText = Get-Content -LiteralPath $helperPath -Raw
    $helperHash = (Get-FileHash -LiteralPath $helperPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($versionLines.Count -eq 1) {
        $version = [string]$versionLines[0]
        if ($mainText -notmatch [regex]::Escape("AppVersion = '$version'")) {
            Add-Failure "The main application version does not match VERSION ($version)."
        }
        if ($mainText -notmatch [regex]::Escape(('Text="VERSION {0}"' -f $version))) {
            Add-Failure "The visible UI version does not match VERSION ($version)."
        }
        if ($helperText -notmatch [regex]::Escape("Version = '$version'")) {
            Add-Failure "The helper version does not match VERSION ($version)."
        }
        if ((Test-Path -LiteralPath $authorPath -PathType Leaf) -and ((Get-Content -LiteralPath $authorPath -Raw) -notmatch [regex]::Escape("Version $version"))) {
            Add-Failure "AUTHOR.txt does not match VERSION ($version)."
        }
    }
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
    if ($mainText -notmatch [regex]::Escape("ProcessExclusionName = 'game.dll'")) {
        Add-Failure 'The main application does not request the game.dll process exclusion.'
    }
    if ($mainText -notmatch [regex]::Escape('Invoke-HelperOperation -Mode ''Apply'' -Paths $targets -Processes @($script:ProcessExclusionName)')) {
        Add-Failure 'The automatic apply operation does not pass game.dll to the helper process exclusion list.'
    }
    if ($mainText -notmatch [regex]::Escape("RestartNotice = 'Fully close and restart Dark Age of Camelot for the fix to take effect.'")) {
        Add-Failure 'The required post-apply Dark Age of Camelot restart notice is missing.'
    }
    if ($mainText -notmatch [regex]::Escape('IMPORTANT: $($script:RestartNotice)')) {
        Add-Failure 'The completion dialog does not display the restart notice.'
    }
    if ($helperText -notmatch [regex]::Escape('ExclusionProcess = [string[]]@($ProcessName)')) {
        Add-Failure 'The helper does not configure Defender ExclusionProcess through WMI.'
    }
    if ($helperText -notmatch [regex]::Escape("ProcessExclusionName = 'game.dll'")) {
        Add-Failure 'The helper process exclusion value is not game.dll.'
    }
    if ($mainText -notmatch [regex]::Escape('AddedProcesses')) {
        Add-Failure 'The main application does not track process exclusions for rollback.'
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

$readmePath = Join-Path $root 'README.md'
if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    if ($readmeText -notmatch [regex]::Escape('fully close and restart Dark Age of Camelot')) {
        Add-Failure 'README.md does not include the required post-apply restart instruction.'
    }
    if ($readmeText -notmatch [regex]::Escape('game.dll` process exclusion')) {
        Add-Failure 'README.md does not document the game.dll process exclusion.'
    }
}

if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
    $workflowText = Get-Content -LiteralPath $workflowPath -Raw
    if ($workflowText -notmatch [regex]::Escape('uses: actions/checkout@v7')) {
        Add-Failure 'The validation workflow must use actions/checkout@v7.'
    }
}

$launcherPath = Join-Path $root 'Run-DAoC-Loading-Speed-Fix.cmd'
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $launcherText = Get-Content -LiteralPath $launcherPath -Raw
    if ($launcherText -notmatch [regex]::Escape('setlocal EnableExtensions DisableDelayedExpansion')) {
        Add-Failure 'The launcher must disable delayed expansion for path safety.'
    }
    if ($launcherText -notmatch [regex]::Escape('if exist "%SCRIPT%" goto :run')) {
        Add-Failure 'The launcher does not use the path-safe label-based start flow.'
    }
    if ($launcherText -match '(?im)^\s*if\b.*\(\s*$') {
        Add-Failure 'The launcher contains a parenthesized IF block that can break paths containing parentheses.'
    }
    if ($launcherText -match [regex]::Escape('echo %SCRIPT%')) {
        Add-Failure 'The launcher expands the script path into command syntax.'
    }

    $launcherTestRoot = Join-Path ([IO.Path]::GetTempPath()) 'DAoC Loading Speed Fix Launcher (2)'
    try {
        if (Test-Path -LiteralPath $launcherTestRoot) {
            Remove-Item -LiteralPath $launcherTestRoot -Recurse -Force
        }
        [void](New-Item -ItemType Directory -Path $launcherTestRoot -Force)
        Copy-Item -LiteralPath $launcherPath -Destination (Join-Path $launcherTestRoot 'Run-DAoC-Loading-Speed-Fix.cmd') -Force
        [IO.File]::WriteAllText(
            (Join-Path $launcherTestRoot 'DAoC-Loading-Speed-Fix.ps1'),
            "# Created by Cosmy.`r`n",
            [Text.Encoding]::ASCII
        )
        & (Join-Path $launcherTestRoot 'Run-DAoC-Loading-Speed-Fix.cmd') --launcher-test
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "The launcher failed from a path containing parentheses. Exit code: $LASTEXITCODE"
        }
    }
    catch {
        Add-Failure "The launcher path compatibility test failed: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $launcherTestRoot) {
            Remove-Item -LiteralPath $launcherTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$manifestPath = Join-Path $root 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifestEntries = @{}
    foreach ($line in @(Get-Content -LiteralPath $manifestPath)) {
        if ($line -match '^([0-9A-Fa-f]{64})  (.+)$') {
            $expectedHash = $matches[1].ToUpperInvariant()
            $relativePath = $matches[2].Replace('/', '\')
            if ($manifestEntries.ContainsKey($relativePath)) {
                Add-Failure "SHA256SUMS.txt contains a duplicate entry: $relativePath"
                continue
            }
            $manifestEntries[$relativePath] = $expectedHash
            $targetPath = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                Add-Failure "SHA256SUMS.txt references a missing file: $relativePath"
                continue
            }
            $actualHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($actualHash -ne $expectedHash) {
                Add-Failure "SHA-256 mismatch for $relativePath."
            }
        }
    }

    if ($manifestEntries.Count -eq 0) {
        Add-Failure 'SHA256SUMS.txt contains no file entries.'
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File)) {
        if ($file.FullName -eq $manifestPath) { continue }
        $relativePath = $file.FullName.Substring($root.Length + 1)
        if ($relativePath.StartsWith('.git\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($relativePath.StartsWith('dist\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not $manifestEntries.ContainsKey($relativePath)) {
            Add-Failure "SHA256SUMS.txt is missing a file entry: $relativePath"
        }
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
