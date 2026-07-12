# Created by Cosmy.
# DAoC Loading Speed Fix Defender helper for Windows 10 and Windows 11.
#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Apply', 'Remove')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Version = '1.0.2'
$script:Author = 'Cosmy'
$script:CoreFileNames = @(
    'game.dll',
    'libxml2.dll',
    'login.dll',
    'mss16.dll',
    'mss32.dll',
    'patchui.dll',
    'patchui_win.dll'
)
$script:ProcessExclusionName = 'game.dll'

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function ConvertTo-ComparablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()
    }
    catch {
        return $Path.Trim().TrimEnd('\').ToLowerInvariant()
    }
}

function ConvertTo-ComparableProcess {
    param([Parameter(Mandatory = $true)][string]$ProcessName)

    return $ProcessName.Trim().ToLowerInvariant()
}

function Resolve-ValidatedProcessExclusion {
    param([Parameter(Mandatory = $true)][string]$ProcessName)

    if ([string]::IsNullOrWhiteSpace($ProcessName)) {
        throw 'An empty process exclusion was supplied.'
    }

    $normalized = $ProcessName.Trim()
    if (-not $normalized.Equals($script:ProcessExclusionName, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsupported process exclusion: $ProcessName"
    }

    return $script:ProcessExclusionName
}

function Test-IsSameOrChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    try {
        $candidatePath = [IO.Path]::GetFullPath($Candidate).TrimEnd('\')
        $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
    }
    catch {
        return $false
    }

    if ($candidatePath.Equals($parentPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $candidatePath.StartsWith($parentPath + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-ReparseAncestor {
    param([Parameter(Mandatory = $true)][string]$Path)

    $cursor = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $cursor) {
        $cursor = (Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).FullName
    }

    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $true
            }
        }

        $root = [IO.Path]::GetPathRoot($cursor)
        if ($cursor.TrimEnd('\').Equals($root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) {
            break
        }
        $cursor = $parent.FullName
    }

    return $false
}

function Resolve-SafeLocalPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$MustExist
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'An empty path was supplied.'
    }
    if ($Path.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw "Network paths are not accepted: $Path"
    }

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not [IO.Path]::IsPathRooted($fullPath)) {
        throw "The path is not absolute: $Path"
    }

    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw "A drive root cannot be used: $fullPath"
    }

    $driveInfo = New-Object IO.DriveInfo -ArgumentList $root
    if (-not $driveInfo.IsReady -or $driveInfo.DriveType -ne [IO.DriveType]::Fixed) {
        throw "The path is not on a ready local fixed drive: $fullPath"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WINDIR) -and
        (Test-IsSameOrChildPath -Candidate $fullPath -Parent $env:WINDIR)) {
        throw "A Windows system path cannot be used: $fullPath"
    }

    foreach ($protectedName in @('$Recycle.Bin', 'System Volume Information', 'Recovery')) {
        $protectedPath = Join-Path $root $protectedName
        if (Test-IsSameOrChildPath -Candidate $fullPath -Parent $protectedPath) {
            throw "A protected system path cannot be used: $fullPath"
        }
    }

    if ($MustExist -and -not (Test-Path -LiteralPath $fullPath)) {
        throw "The path does not exist: $fullPath"
    }

    if (Test-ReparseAncestor -Path $fullPath) {
        throw "A reparse point was found in the path: $fullPath"
    }

    return $fullPath
}

function Resolve-ValidatedInstallation {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Resolve-SafeLocalPath -Path $Path -MustExist $true
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "The installation path is not a folder: $fullPath"
    }

    $gameDll = Join-Path $fullPath 'game.dll'
    if (-not (Test-Path -LiteralPath $gameDll -PathType Leaf)) {
        throw "The folder does not contain game.dll: $fullPath"
    }

    $companionNames = @('camelot.exe', 'login.dll', 'mss32.dll', 'patchui.dll', 'libxml2.dll')
    $companionCount = 0
    foreach ($name in $companionNames) {
        if (Test-Path -LiteralPath (Join-Path $fullPath $name) -PathType Leaf) {
            $companionCount++
        }
    }

    $identitySignal = $fullPath -match '(?i)dark age of camelot|\bdaoc\b|camelot|mythic|broadsword|electronic arts|ea games|eden|uthgard|opendaoc'
    if (-not $identitySignal) {
        try {
            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($gameDll)
            $identitySignal = (([string]$versionInfo.ProductName) -match '(?i)dark age|camelot') -or
                              (([string]$versionInfo.CompanyName) -match '(?i)mythic|electronic arts|broadsword')
        }
        catch {
            $identitySignal = $false
        }
    }

    if ($companionCount -lt 2 -or -not $identitySignal) {
        throw "The folder did not pass the DAoC identity check: $fullPath"
    }

    return $fullPath
}

function Get-EntriesForInstallation {
    param([Parameter(Mandatory = $true)][string]$FolderPath)

    $entries = New-Object System.Collections.ArrayList
    [void]$entries.Add($FolderPath)
    foreach ($name in $script:CoreFileNames) {
        $filePath = Join-Path $FolderPath $name
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            [void]$entries.Add([IO.Path]::GetFullPath($filePath))
        }
    }
    return @($entries)
}

function Get-DefenderPreferences {
    return Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' -ClassName 'MSFT_MpPreference' -ErrorAction Stop
}

function Test-PathEntryPresent {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expected = ConvertTo-ComparablePath -Path $Path
    $preferences = Get-DefenderPreferences
    foreach ($entry in @($preferences.ExclusionPath)) {
        if ($null -eq $entry) {
            continue
        }
        if ((ConvertTo-ComparablePath -Path ([string]$entry)) -eq $expected) {
            return $true
        }
    }
    return $false
}

function Test-ProcessEntryPresent {
    param([Parameter(Mandatory = $true)][string]$ProcessName)

    $expected = ConvertTo-ComparableProcess -ProcessName $ProcessName
    $preferences = Get-DefenderPreferences
    foreach ($entry in @($preferences.ExclusionProcess)) {
        if ($null -eq $entry) {
            continue
        }
        if ((ConvertTo-ComparableProcess -ProcessName ([string]$entry)) -eq $expected) {
            return $true
        }
    }
    return $false
}

function Wait-PathEntryState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$ShouldExist,
        [int]$MaximumMilliseconds = 9000
    )

    $deadline = (Get-Date).AddMilliseconds([Math]::Max(500, $MaximumMilliseconds))
    do {
        if ((Test-PathEntryPresent -Path $Path) -eq $ShouldExist) {
            return $true
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Wait-ProcessEntryState {
    param(
        [Parameter(Mandatory = $true)][string]$ProcessName,
        [Parameter(Mandatory = $true)][bool]$ShouldExist,
        [int]$MaximumMilliseconds = 9000
    )

    $deadline = (Get-Date).AddMilliseconds([Math]::Max(500, $MaximumMilliseconds))
    do {
        if ((Test-ProcessEntryPresent -ProcessName $ProcessName) -eq $ShouldExist) {
            return $true
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Invoke-PreferenceMethod {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Add', 'Remove')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $arguments = @{
        ExclusionPath = [string[]]@($Path)
        Force = $true
    }

    $response = Invoke-CimMethod `
        -Namespace 'root/Microsoft/Windows/Defender' `
        -ClassName 'MSFT_MpPreference' `
        -MethodName $Method `
        -Arguments $arguments `
        -ErrorAction Stop

    if ($null -ne $response -and $response.PSObject.Properties.Name -contains 'ReturnValue') {
        $returnValue = [int]$response.ReturnValue
        if ($returnValue -ne 0) {
            throw "The Defender WMI provider returned code $returnValue for $Method."
        }
    }
}

function Invoke-ProcessPreferenceMethod {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Add', 'Remove')][string]$Method,
        [Parameter(Mandatory = $true)][string]$ProcessName
    )

    $arguments = @{
        ExclusionProcess = [string[]]@($ProcessName)
        Force = $true
    }

    $response = Invoke-CimMethod `
        -Namespace 'root/Microsoft/Windows/Defender' `
        -ClassName 'MSFT_MpPreference' `
        -MethodName $Method `
        -Arguments $arguments `
        -ErrorAction Stop

    if ($null -ne $response -and $response.PSObject.Properties.Name -contains 'ReturnValue') {
        $returnValue = [int]$response.ReturnValue
        if ($returnValue -ne 0) {
            throw "The Defender WMI provider returned code $returnValue for $Method process exclusion."
        }
    }
}

function Get-MpCmdRunPath {
    $candidates = New-Object System.Collections.ArrayList

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        $platformRoot = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
        if (Test-Path -LiteralPath $platformRoot -PathType Container) {
            try {
                foreach ($directory in @(Get-ChildItem -LiteralPath $platformRoot -Directory -Force -ErrorAction Stop | Sort-Object Name -Descending)) {
                    [void]$candidates.Add((Join-Path $directory.FullName 'MpCmdRun.exe'))
                }
            }
            catch {
                # The legacy path is checked below.
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        [void]$candidates.Add((Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath([string]$candidate)
        }
    }

    return $null
}

function Invoke-MpCmdRunCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][AllowNull()][string]$MpCmdRunPath
    )

    $check = [ordered]@{
        Path = $Path
        Available = $false
        State = $null
        ExitCode = $null
        Output = ''
        Error = $null
    }

    if ([string]::IsNullOrWhiteSpace($MpCmdRunPath)) {
        return [pscustomobject]$check
    }

    $check.Available = $true
    try {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $MpCmdRunPath
        $startInfo.Arguments = "-CheckExclusion -Path `"$Path`""
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            $check.Error = 'MpCmdRun.exe did not start.'
            return [pscustomobject]$check
        }

        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill() } catch { }
            $check.Error = 'MpCmdRun.exe timed out after 15 seconds.'
            return [pscustomobject]$check
        }

        $stdout = ([string]$process.StandardOutput.ReadToEnd()).Trim()
        $stderr = ([string]$process.StandardError.ReadToEnd()).Trim()
        $check.ExitCode = [int]$process.ExitCode
        $check.Output = ((@($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' | ')

        if ($process.ExitCode -eq 0) {
            $check.State = $true
        }
        elseif ($process.ExitCode -eq 1) {
            $check.State = $false
        }
        else {
            $check.Error = "MpCmdRun.exe returned unexpected exit code $($process.ExitCode)."
        }
    }
    catch {
        $check.Error = $_.Exception.Message
    }

    return [pscustomobject]$check
}

function Wait-EffectiveFolderState {
    param(
        [Parameter(Mandatory = $true)][string]$FolderPath,
        [Parameter(Mandatory = $false)][AllowNull()][string]$MpCmdRunPath,
        [int]$MaximumSeconds = 12
    )

    $gameDll = Join-Path $FolderPath 'game.dll'
    $testPaths = @($gameDll, $FolderPath)
    $last = $null
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $MaximumSeconds))
    $attempt = 0

    do {
        $attempt++
        foreach ($testPath in $testPaths) {
            if (-not (Test-Path -LiteralPath $testPath)) {
                continue
            }
            $last = Invoke-MpCmdRunCheck -Path $testPath -MpCmdRunPath $MpCmdRunPath
            if ($last.State -eq $true) {
                return [pscustomobject]@{
                    Folder = $FolderPath
                    State = $true
                    Attempts = $attempt
                    TestPath = $last.Path
                    ExitCode = $last.ExitCode
                    Output = $last.Output
                    Error = $last.Error
                }
            }
        }
        if ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 1000
        }
    } while ((Get-Date) -lt $deadline)

    if ($null -eq $last) {
        return [pscustomobject]@{
            Folder = $FolderPath
            State = $null
            Attempts = 0
            TestPath = $gameDll
            ExitCode = $null
            Output = ''
            Error = 'MpCmdRun.exe was not available or no test path existed.'
        }
    }

    return [pscustomobject]@{
        Folder = $FolderPath
        State = $last.State
        Attempts = $attempt
        TestPath = $last.Path
        ExitCode = $last.ExitCode
        Output = $last.Output
        Error = $last.Error
    }
}

$result = [ordered]@{
    Version = $script:Version
    Author = $script:Author
    Mode = $Mode
    Started = (Get-Date).ToString('o')
    Completed = $null
    Added = @()
    Existing = @()
    AddedProcesses = @()
    ExistingProcesses = @()
    EffectiveExisting = @()
    Removed = @()
    AlreadyAbsent = @()
    RemovedProcesses = @()
    ProcessesAlreadyAbsent = @()
    Failed = @()
    Warnings = @()
    VerificationTool = $null
    Verification = @()
    DisableLocalAdminMerge = $null
    DefenderStatus = $null
    FatalError = $null
}

try {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator rights are required.'
    }
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        throw "The request file was not found: $RequestPath"
    }

    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $requestedPaths = @()
    $requestedProcesses = @()
    if ($request.PSObject.Properties.Name -contains 'Paths') {
        $requestedPaths = @($request.Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($request.PSObject.Properties.Name -contains 'Processes') {
        $requestedProcesses = @($request.Processes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    if ($requestedPaths.Count -eq 0 -and $requestedProcesses.Count -eq 0) {
        throw 'The request contained no exclusion entries.'
    }

    $validatedFolders = New-Object System.Collections.ArrayList
    $folderSet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)

    foreach ($requestedPath in $requestedPaths) {
        try {
            if ($Mode -eq 'Apply') {
                $folder = Resolve-ValidatedInstallation -Path ([string]$requestedPath)
            }
            else {
                $folder = Resolve-SafeLocalPath -Path ([string]$requestedPath) -MustExist $false
            }
            if ($folderSet.Add($folder)) {
                [void]$validatedFolders.Add($folder)
            }
        }
        catch {
            $result.Failed += [pscustomobject]@{
                EntryType = 'Path'
                Path = [string]$requestedPath
                Error = $_.Exception.Message
            }
        }
    }

    $validatedProcesses = New-Object System.Collections.ArrayList
    $processSet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($requestedProcess in $requestedProcesses) {
        try {
            $processName = Resolve-ValidatedProcessExclusion -ProcessName ([string]$requestedProcess)
            if ($processSet.Add($processName)) {
                [void]$validatedProcesses.Add($processName)
            }
        }
        catch {
            $result.Failed += [pscustomobject]@{
                EntryType = 'Process'
                Path = [string]$requestedProcess
                Error = $_.Exception.Message
            }
        }
    }

    if ($validatedFolders.Count -eq 0 -and $validatedProcesses.Count -eq 0) {
        throw 'No request entry passed validation.'
    }

    try {
        $preferences = Get-DefenderPreferences
        if ($preferences.PSObject.Properties.Name -contains 'DisableLocalAdminMerge') {
            $result.DisableLocalAdminMerge = [bool]$preferences.DisableLocalAdminMerge
        }
    }
    catch {
        throw "Microsoft Defender preferences could not be read: $($_.Exception.Message)"
    }

    try {
        $status = Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' -ClassName 'MSFT_MpComputerStatus' -ErrorAction Stop
        $result.DefenderStatus = [pscustomobject]@{
            AMServiceEnabled = [bool]$status.AMServiceEnabled
            AntivirusEnabled = [bool]$status.AntivirusEnabled
            RealTimeProtectionEnabled = [bool]$status.RealTimeProtectionEnabled
        }
    }
    catch {
        $result.Warnings += "Defender status could not be read: $($_.Exception.Message)"
    }

    $mpCmdRunPath = Get-MpCmdRunPath
    $result.VerificationTool = $mpCmdRunPath
    if ([string]::IsNullOrWhiteSpace([string]$mpCmdRunPath)) {
        $result.Warnings += 'MpCmdRun.exe was not found. Exact preference-list verification is still enforced.'
    }

    if ($Mode -eq 'Apply') {
        $entrySet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
        $entries = New-Object System.Collections.ArrayList
        foreach ($folder in $validatedFolders) {
            foreach ($entry in @(Get-EntriesForInstallation -FolderPath ([string]$folder))) {
                if ($entrySet.Add([string]$entry)) {
                    [void]$entries.Add([string]$entry)
                }
            }
        }

        foreach ($entry in $entries) {
            try {
                if (Test-PathEntryPresent -Path $entry) {
                    $result.Existing += $entry
                    continue
                }

                Invoke-PreferenceMethod -Method 'Add' -Path $entry
                if (-not (Wait-PathEntryState -Path $entry -ShouldExist $true)) {
                    throw 'The provider call completed, but the exact path did not appear in the Defender exclusion list.'
                }
                $result.Added += $entry
            }
            catch {
                $result.Failed += [pscustomobject]@{
                    EntryType = 'Path'
                    Path = [string]$entry
                    Error = $_.Exception.Message
                }
            }
        }

        foreach ($processName in $validatedProcesses) {
            try {
                if (Test-ProcessEntryPresent -ProcessName ([string]$processName)) {
                    $result.ExistingProcesses += [string]$processName
                    continue
                }

                Invoke-ProcessPreferenceMethod -Method 'Add' -ProcessName ([string]$processName)
                if (-not (Wait-ProcessEntryState -ProcessName ([string]$processName) -ShouldExist $true)) {
                    throw 'The provider call completed, but the exact process did not appear in the Defender process exclusion list.'
                }
                $result.AddedProcesses += [string]$processName
            }
            catch {
                $result.Failed += [pscustomobject]@{
                    EntryType = 'Process'
                    Path = [string]$processName
                    Error = $_.Exception.Message
                }
            }
        }

        foreach ($folder in $validatedFolders) {
            $verification = Wait-EffectiveFolderState -FolderPath ([string]$folder) -MpCmdRunPath $mpCmdRunPath -MaximumSeconds 12
            $result.Verification += $verification
            if ($verification.State -eq $false) {
                $hint = if ($result.DisableLocalAdminMerge -eq $true) {
                    ' Local administrator exclusion merging is disabled by policy.'
                }
                else {
                    ''
                }
                $result.Warnings += "The exact exclusions are configured, but MpCmdRun did not report '$($verification.TestPath)' as effective.$hint"
            }
            elseif ($null -eq $verification.State) {
                $result.Warnings += "Effective verification was inconclusive for: $folder"
            }
        }
    }
    else {
        $removeEntries = @($validatedFolders | Sort-Object { ([string]$_).Length } -Descending)
        foreach ($entry in $removeEntries) {
            try {
                if (-not (Test-PathEntryPresent -Path $entry)) {
                    $result.AlreadyAbsent += $entry
                    continue
                }

                Invoke-PreferenceMethod -Method 'Remove' -Path $entry
                if (-not (Wait-PathEntryState -Path $entry -ShouldExist $false)) {
                    throw 'The provider call completed, but the exact path remained in the Defender exclusion list.'
                }
                $result.Removed += $entry
            }
            catch {
                $result.Failed += [pscustomobject]@{
                    EntryType = 'Path'
                    Path = [string]$entry
                    Error = $_.Exception.Message
                }
            }
        }

        foreach ($processName in $validatedProcesses) {
            try {
                if (-not (Test-ProcessEntryPresent -ProcessName ([string]$processName))) {
                    $result.ProcessesAlreadyAbsent += [string]$processName
                    continue
                }

                Invoke-ProcessPreferenceMethod -Method 'Remove' -ProcessName ([string]$processName)
                if (-not (Wait-ProcessEntryState -ProcessName ([string]$processName) -ShouldExist $false)) {
                    throw 'The provider call completed, but the exact process remained in the Defender process exclusion list.'
                }
                $result.RemovedProcesses += [string]$processName
            }
            catch {
                $result.Failed += [pscustomobject]@{
                    EntryType = 'Process'
                    Path = [string]$processName
                    Error = $_.Exception.Message
                }
            }
        }
    }
}
catch {
    $result.FatalError = $_.Exception.Message
}
finally {
    $result.Completed = (Get-Date).ToString('o')
    $json = $result | ConvertTo-Json -Depth 8
    $utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllText($ResultPath, $json, $utf8NoBom)
}

if (-not [string]::IsNullOrWhiteSpace([string]$result.FatalError)) {
    exit 1
}
if (@($result.Failed).Count -gt 0) {
    exit 2
}
exit 0
