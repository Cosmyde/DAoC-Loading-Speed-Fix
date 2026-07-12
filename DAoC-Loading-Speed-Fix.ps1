# Created by Cosmy.
# DAoC Loading Speed Fix for Windows 10 and Windows 11.
#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Elevated
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-IsWindows {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

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

function Get-NativePowerShellPath {
    $system32 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $sysnative = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $sysnative -PathType Leaf) {
            return $sysnative
        }
    }
    return $system32
}

if (-not (Test-IsWindows)) {
    throw 'Windows 10 or Windows 11 is required.'
}

if ([Environment]::OSVersion.Version.Major -lt 10) {
    throw 'Windows 10 or Windows 11 is required.'
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'A 64-bit installation of Windows 10 or Windows 11 is required.'
}

$needsDesktop = $PSVersionTable.PSEdition -ne 'Desktop'
$needs64Bit = -not [Environment]::Is64BitProcess
$needsSta = [Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA
$needsAdmin = -not (Test-IsAdministrator)

if ($needsDesktop -or $needs64Bit -or $needsSta -or $needsAdmin) {
    if ($Elevated) {
        throw 'The required 64-bit elevated Windows PowerShell 5.1 STA session could not be established.'
    }

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Save the script to a file before running it.'
    }

    $hostPath = Get-NativePowerShellPath
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`" -Elevated"
    $start = @{
        FilePath = $hostPath
        ArgumentList = $arguments
        PassThru = $true
    }
    if ($needsAdmin) {
        $start.Verb = 'RunAs'
    }

    try {
        [void](Start-Process @start)
        exit 0
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [void][System.Windows.Forms.MessageBox]::Show(
            "Administrator approval is required to apply the loading speed fix.`r`n`r`n$($_.Exception.Message)",
            'DAoC Loading Speed Fix - By Cosmy',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        exit 1
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

$script:AppVersion = '1.0.2'
$script:Author = 'Cosmy'
$script:ScriptRoot = Split-Path -Parent $PSCommandPath
$script:HelperPath = Join-Path $script:ScriptRoot 'DAoC-Loading-Speed-Fix-Helper.ps1'
$script:BrandImagePath = Join-Path $script:ScriptRoot 'Assets\AppBanner.png'
$script:AppIconPath = Join-Path $script:ScriptRoot 'Assets\AppIcon.ico'
$script:ExpectedHelperSha256 = '2349B570D4F710AA40003B9DA2070A6FD9C42D95344B435E261A50DCBBEF4B15'
$script:ProcessExclusionName = 'game.dll'
$script:RestartNotice = 'Fully close and restart Dark Age of Camelot for the fix to take effect.'
$script:CoreFileNames = @(
    'game.dll',
    'libxml2.dll',
    'login.dll',
    'mss16.dll',
    'mss32.dll',
    'patchui.dll',
    'patchui_win.dll'
)
$script:InstallRecords = New-Object System.Collections.ArrayList
$script:IsBusy = $false
$script:Window = $null
$script:ActivityBox = $null

$programData = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) {
    Join-Path $env:SystemDrive 'ProgramData'
}
else {
    $env:ProgramData
}

$script:DataRoot = Join-Path $programData 'DAoCLoadingSpeedFix'
$script:LogRoot = Join-Path $script:DataRoot 'Logs'
$script:WorkRoot = Join-Path $script:DataRoot 'Work'
$script:StatePath = Join-Path $script:DataRoot 'state.json'

foreach ($directory in @($script:DataRoot, $script:LogRoot, $script:WorkRoot)) {
    [void](New-Item -ItemType Directory -Path $directory -Force)
}

$script:LogPath = Join-Path $script:LogRoot (Get-Date -Format 'DAoC-Loading-Speed-Fix-yyyyMMdd-HHmmss.log')
$script:Utf8NoBom = New-Object Text.UTF8Encoding -ArgumentList $false
[IO.File]::WriteAllText(
    $script:LogPath,
    "DAoC Loading Speed Fix $($script:AppVersion) - Created by $($script:Author). Started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')`r`n",
    $script:Utf8NoBom
)

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level.ToUpperInvariant(), $Message
    try {
        [IO.File]::AppendAllText($script:LogPath, $line + "`r`n", $script:Utf8NoBom)
    }
    catch {
        # Logging must not stop the fix.
    }

    if ($null -ne $script:ActivityBox) {
        $script:ActivityBox.AppendText($line + "`r`n")
        $script:ActivityBox.ScrollToEnd()
    }
}

function Pump-Ui {
    try {
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        # Best effort.
    }
}

function Set-UiStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Detail,
        [ValidateSet('Idle', 'Working', 'Good', 'Warning', 'Error')][string]$State = 'Idle',
        [int]$Progress = -1
    )

    $script:StatusTitle.Text = $Title
    $script:StatusDetail.Text = $Detail

    switch ($State) {
        'Working' {
            $script:StatusPill.Background = '#C86A20'
            $script:StatusPillText.Text = 'WORKING'
        }
        'Good' {
            $script:StatusPill.Background = '#2F855A'
            $script:StatusPillText.Text = 'COMPLETE'
        }
        'Warning' {
            $script:StatusPill.Background = '#D97706'
            $script:StatusPillText.Text = 'ATTENTION'
        }
        'Error' {
            $script:StatusPill.Background = '#A61B1B'
            $script:StatusPillText.Text = 'FAILED'
        }
        default {
            $script:StatusPill.Background = '#6D3AA8'
            $script:StatusPillText.Text = 'READY'
        }
    }

    if ($Progress -lt 0) {
        $script:ProgressBar.IsIndeterminate = $State -eq 'Working'
    }
    else {
        $script:ProgressBar.IsIndeterminate = $false
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Progress))
    }
    Pump-Ui
}

function Set-BusyState {
    param([bool]$Busy)

    $script:IsBusy = $Busy
    $script:RunButton.IsEnabled = -not $Busy
    $script:CloseButton.IsEnabled = -not $Busy
    $script:RollbackButton.IsEnabled = (-not $Busy) -and (Get-StateEntryCount -gt 0)
    $script:OpenLogsButton.IsEnabled = $true
}

function Show-Dialog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Title,
        [ValidateSet('Information', 'Warning', 'Error')][string]$Kind = 'Information'
    )

    $icon = switch ($Kind) {
        'Warning' { [System.Windows.MessageBoxImage]::Warning }
        'Error' { [System.Windows.MessageBoxImage]::Error }
        default { [System.Windows.MessageBoxImage]::Information }
    }

    [void][System.Windows.MessageBox]::Show(
        $script:Window,
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::OK,
        $icon
    )
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

function Test-DaocDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Path) -or $Path.StartsWith('\\')) {
            return $null
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            return $null
        }

        $item = Get-Item -LiteralPath $Path -Force
        $fullPath = [IO.Path]::GetFullPath($item.FullName).TrimEnd('\')
        $root = [IO.Path]::GetPathRoot($fullPath)
        if ($fullPath.Equals($root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }

        $drive = New-Object IO.DriveInfo -ArgumentList $root
        if (-not $drive.IsReady -or $drive.DriveType -ne [IO.DriveType]::Fixed) {
            return $null
        }

        if (-not [string]::IsNullOrWhiteSpace($env:WINDIR) -and
            (Test-IsSameOrChildPath -Candidate $fullPath -Parent $env:WINDIR)) {
            return $null
        }

        foreach ($protected in @('$Recycle.Bin', 'System Volume Information', 'Recovery')) {
            if (Test-IsSameOrChildPath -Candidate $fullPath -Parent (Join-Path $root $protected)) {
                return $null
            }
        }

        if (Test-ReparseAncestor -Path $fullPath) {
            return $null
        }

        $gameDll = Join-Path $fullPath 'game.dll'
        if (-not (Test-Path -LiteralPath $gameDll -PathType Leaf)) {
            return $null
        }

        $markerNames = @('camelot.exe', 'login.dll', 'mss32.dll', 'patchui.dll', 'libxml2.dll')
        $markers = New-Object System.Collections.ArrayList
        foreach ($marker in $markerNames) {
            if (Test-Path -LiteralPath (Join-Path $fullPath $marker) -PathType Leaf) {
                [void]$markers.Add($marker)
            }
        }

        $product = ''
        $company = ''
        $fileVersion = ''
        try {
            $versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($gameDll)
            $product = [string]$versionInfo.ProductName
            $company = [string]$versionInfo.CompanyName
            $fileVersion = [string]$versionInfo.FileVersion
        }
        catch {
            # Older or modified clients may not have version resources.
        }

        $pathSignal = $fullPath -match '(?i)dark age of camelot|\bdaoc\b|camelot|mythic|broadsword|electronic arts|ea games|eden|uthgard|opendaoc'
        $metadataSignal = ($product -match '(?i)dark age|camelot') -or ($company -match '(?i)mythic|electronic arts|broadsword')
        $accepted = ($markers.Count -ge 2 -and ($pathSignal -or $metadataSignal)) -or ($markers.Count -ge 4)
        if (-not $accepted) {
            return $null
        }

        $coreCount = 0
        foreach ($name in $script:CoreFileNames) {
            if (Test-Path -LiteralPath (Join-Path $fullPath $name) -PathType Leaf) {
                $coreCount++
            }
        }

        $confidence = if ($markers.Count -ge 3 -and ($pathSignal -or $metadataSignal)) { 'High' } else { 'Medium' }
        if ([string]::IsNullOrWhiteSpace($fileVersion)) {
            $fileVersion = 'Unknown'
        }

        $hash = ''
        try {
            $hash = (Get-FileHash -LiteralPath $gameDll -Algorithm SHA256).Hash
        }
        catch {
            $hash = 'Unavailable'
        }

        return [pscustomobject]@{
            Path = $fullPath
            Confidence = $confidence
            Version = $fileVersion
            CoreFiles = $coreCount
            Markers = ($markers -join ', ')
            Source = $Source
            GameHash = $hash
        }
    }
    catch {
        Write-Log -Level 'WARN' -Message "Candidate validation failed for '$Path': $($_.Exception.Message)"
        return $null
    }
}

function Add-CandidateRecord {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Index,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $record = Test-DaocDirectory -Path $Path -Source $Source
    if ($null -eq $record) {
        return
    }

    $key = $record.Path.ToLowerInvariant()
    if (-not $Index.ContainsKey($key)) {
        $Index[$key] = $record
        [void]$script:InstallRecords.Add($record)
        Write-Log -Level 'OK' -Message "Validated DAoC installation [$($record.Confidence)]: $($record.Path)"
        Write-Log -Level 'INFO' -Message "game.dll SHA-256 [$($record.Path)]: $($record.GameHash)"
    }
}

function Get-FixedDriveRoots {
    return @([IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and $_.DriveType -eq [IO.DriveType]::Fixed
    } | ForEach-Object {
        $_.RootDirectory.FullName.TrimEnd('\')
    })
}

function Get-RegistryCandidatePaths {
    $paths = New-Object System.Collections.ArrayList

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($registryRoot in $uninstallRoots) {
        try {
            foreach ($entry in @(Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue)) {
                if (-not ($entry.PSObject.Properties.Name -contains 'DisplayName')) {
                    continue
                }

                $displayName = [string]$entry.PSObject.Properties['DisplayName'].Value
                if ([string]::IsNullOrWhiteSpace($displayName) -or
                    $displayName -notmatch '(?i)dark age of camelot|\bdaoc\b|eden.*camelot|uthgard|opendaoc') {
                    continue
                }

                foreach ($propertyName in @('InstallLocation', 'InstallSource')) {
                    if (-not ($entry.PSObject.Properties.Name -contains $propertyName)) {
                        continue
                    }
                    $value = [string]$entry.PSObject.Properties[$propertyName].Value
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        [void]$paths.Add([pscustomobject]@{ Path = $value.Trim('"'); Source = "Uninstall registry: $displayName" })
                    }
                }

                if ($entry.PSObject.Properties.Name -contains 'DisplayIcon') {
                    $displayIcon = [string]$entry.PSObject.Properties['DisplayIcon'].Value
                    if (-not [string]::IsNullOrWhiteSpace($displayIcon)) {
                        $iconPath = ($displayIcon -split ',')[0].Trim().Trim('"')
                        if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
                            [void]$paths.Add([pscustomobject]@{ Path = (Split-Path -Parent $iconPath); Source = "Uninstall icon: $displayName" })
                        }
                    }
                }
            }
        }
        catch {
            Write-Log -Level 'WARN' -Message "Could not read uninstall registry root '$registryRoot': $($_.Exception.Message)"
        }
    }

    $vendorRoots = @(
        'HKLM:\SOFTWARE\WOW6432Node\Electronic Arts',
        'HKLM:\SOFTWARE\Electronic Arts',
        'HKCU:\SOFTWARE\Electronic Arts',
        'HKLM:\SOFTWARE\WOW6432Node\Mythic Entertainment',
        'HKLM:\SOFTWARE\Mythic Entertainment'
    )

    foreach ($vendorRoot in $vendorRoots) {
        if (-not (Test-Path -LiteralPath $vendorRoot)) {
            continue
        }

        try {
            foreach ($key in @(Get-ChildItem -LiteralPath $vendorRoot -Recurse -ErrorAction SilentlyContinue)) {
                $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $properties) {
                    continue
                }

                foreach ($propertyName in @('Install Dir', 'InstallDir', 'InstallLocation', 'Path', 'InstallPath')) {
                    if ($properties.PSObject.Properties.Name -contains $propertyName) {
                        $value = [string]$properties.$propertyName
                        if (-not [string]::IsNullOrWhiteSpace($value)) {
                            [void]$paths.Add([pscustomobject]@{ Path = $value.Trim('"'); Source = "Vendor registry: $($key.Name)" })
                        }
                    }
                }
            }
        }
        catch {
            Write-Log -Level 'WARN' -Message "Could not inspect vendor registry root '$vendorRoot': $($_.Exception.Message)"
        }
    }

    return @($paths)
}

function Get-CommonCandidatePaths {
    $paths = New-Object System.Collections.ArrayList
    foreach ($root in Get-FixedDriveRoots) {
        foreach ($relative in @(
            'Dark Age of Camelot',
            'DAoC',
            'Games\Dark Age of Camelot',
            'Games\DAoC',
            'Games\Electronic Arts\Dark Age of Camelot',
            'Electronic Arts\Dark Age of Camelot',
            'EA Games\Dark Age of Camelot',
            'Broadsword\Dark Age of Camelot',
            'Mythic Entertainment\Dark Age of Camelot',
            'Program Files\Electronic Arts\Dark Age of Camelot',
            'Program Files (x86)\Electronic Arts\Dark Age of Camelot',
            'Program Files\EA Games\Dark Age of Camelot',
            'Program Files (x86)\EA Games\Dark Age of Camelot',
            'Program Files\Mythic Entertainment\Dark Age of Camelot',
            'Program Files (x86)\Mythic Entertainment\Dark Age of Camelot'
        )) {
            [void]$paths.Add([pscustomobject]@{ Path = Join-Path ($root + '\') $relative; Source = 'Known location' })
        }
    }
    return @($paths)
}

function Search-CandidateTree {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][hashtable]$Index,
        [int]$MaxDepth = 5,
        [int]$MaxDirectories = 5000
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return 0
    }

    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{ Path = [IO.Path]::GetFullPath($Root); Depth = 0 })
    $visited = 0
    $skipNames = @('Windows', '$Recycle.Bin', 'System Volume Information', 'Recovery', 'WinSxS', 'WindowsApps')

    while ($queue.Count -gt 0 -and $visited -lt $MaxDirectories) {
        $entry = $queue.Dequeue()
        $current = [string]$entry.Path
        $depth = [int]$entry.Depth
        $visited++

        if (($visited % 250) -eq 0) {
            Set-UiStatus -Title 'Searching for DAoC' -Detail "$visited folders checked under $Root" -State 'Working'
        }

        Add-CandidateRecord -Index $Index -Path $current -Source "Targeted search: $Root"

        if ($depth -ge $MaxDepth) {
            continue
        }

        try {
            foreach ($child in @(Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction Stop)) {
                if ($skipNames -contains $child.Name) {
                    continue
                }
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($env:WINDIR) -and
                    (Test-IsSameOrChildPath -Candidate $child.FullName -Parent $env:WINDIR)) {
                    continue
                }
                $queue.Enqueue([pscustomobject]@{ Path = $child.FullName; Depth = $depth + 1 })
            }
        }
        catch {
            # Inaccessible folders are expected during a scan.
        }
    }

    return $visited
}

function Find-DaocInstallations {
    $script:InstallRecords.Clear()
    $index = @{}

    Set-UiStatus -Title 'Searching for DAoC' -Detail 'Checking registration and known installation locations...' -State 'Working'
    Write-Log -Level 'INFO' -Message 'Automatic installation discovery started.'

    foreach ($candidate in @(Get-RegistryCandidatePaths)) {
        Add-CandidateRecord -Index $index -Path ([string]$candidate.Path) -Source ([string]$candidate.Source)
    }

    foreach ($candidate in @(Get-CommonCandidatePaths)) {
        Add-CandidateRecord -Index $index -Path ([string]$candidate.Path) -Source ([string]$candidate.Source)
    }

    $searchRoots = New-Object System.Collections.ArrayList
    foreach ($driveRoot in Get-FixedDriveRoots) {
        foreach ($relative in @(
            'Games', 'Game', 'Old Games', 'MMO', 'MMOs', 'EA Games', 'Electronic Arts',
            'Broadsword', 'Mythic Entertainment',
            'Program Files\Electronic Arts', 'Program Files (x86)\Electronic Arts',
            'Program Files\EA Games', 'Program Files (x86)\EA Games',
            'Program Files\Mythic Entertainment', 'Program Files (x86)\Mythic Entertainment'
        )) {
            [void]$searchRoots.Add((Join-Path ($driveRoot + '\') $relative))
        }

        try {
            foreach ($top in @(Get-ChildItem -LiteralPath ($driveRoot + '\') -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($top.Name -match '(?i)game|electronic|\bea\b|mythic|broadsword|camelot|daoc|eden|uthgard|opendaoc') {
                    [void]$searchRoots.Add($top.FullName)
                }
            }
        }
        catch {
            # Top-level enumeration is best effort.
        }
    }

    foreach ($userRoot in @(
        (Join-Path $env:USERPROFILE 'Games'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Documents')
    )) {
        [void]$searchRoots.Add($userRoot)
    }

    $rootIndex = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($searchRoot in $searchRoots) {
        try {
            $normalizedRoot = [IO.Path]::GetFullPath([string]$searchRoot).TrimEnd('\')
            if ($rootIndex.Add($normalizedRoot)) {
                $limit = if ($normalizedRoot -match '(?i)downloads|desktop|documents') { 2500 } else { 6000 }
                [void](Search-CandidateTree -Root $normalizedRoot -Index $index -MaxDepth 5 -MaxDirectories $limit)
            }
        }
        catch {
            # Invalid candidate root.
        }
    }

    $script:InstallList.ItemsSource = $null
    $script:InstallList.ItemsSource = @($script:InstallRecords | Sort-Object Path)
    $script:DetectedCount.Text = "$($script:InstallRecords.Count) validated installation(s)"
    Write-Log -Level 'INFO' -Message "Automatic discovery finished with $($script:InstallRecords.Count) validated installation(s)."
    return @($script:InstallRecords)
}

function Get-InstallTargetPaths {
    param([Parameter(Mandatory = $true)][object[]]$Installations)

    $set = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    foreach ($installation in $Installations) {
        $path = [IO.Path]::GetFullPath([string]$installation.Path).TrimEnd('\')
        if (Test-Path -LiteralPath $path -PathType Container) {
            [void]$set.Add($path)
        }
    }
    return @($set)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $json = $Value | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)

    try {
        $acl = New-Object Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
            $sid = New-Object Security.Principal.SecurityIdentifier -ArgumentList $sidText
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )
            [void]$acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
    catch {
        Write-Log -Level 'WARN' -Message "Could not restrict ACLs on '$Path': $($_.Exception.Message)"
    }
}

function Invoke-HelperOperation {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Apply', 'Remove')][string]$Mode,
        [string[]]$Paths = @(),
        [string[]]$Processes = @()
    )

    if (-not (Test-Path -LiteralPath $script:HelperPath -PathType Leaf)) {
        throw "The helper script is missing: $($script:HelperPath)"
    }

    $actualHelperHash = (Get-FileHash -LiteralPath $script:HelperPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if (-not $actualHelperHash.Equals($script:ExpectedHelperSha256, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The helper integrity check failed. Expected $($script:ExpectedHelperSha256), received $actualHelperHash. Re-extract the original package."
    }

    $token = [Guid]::NewGuid().ToString('N')
    $requestPath = Join-Path $script:WorkRoot "$token-request.json"
    $resultPath = Join-Path $script:WorkRoot "$token-result.json"

    Write-JsonFile -Value ([ordered]@{
        Version = $script:AppVersion
        Author = $script:Author
        Created = (Get-Date).ToString('o')
        Paths = @($Paths)
        Processes = @($Processes)
    }) -Path $requestPath

    $powerShell = Get-NativePowerShellPath
    $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($script:HelperPath)`" -Mode $Mode -RequestPath `"$requestPath`" -ResultPath `"$resultPath`""

    Write-Log -Level 'INFO' -Message "Starting isolated helper in $Mode mode for $($Paths.Count) path entry source(s) and $($Processes.Count) process entry or entries."
    $process = Start-Process -FilePath $powerShell -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    Write-Log -Level 'INFO' -Message "Helper exit code: $($process.ExitCode)"

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'The helper produced no result file. Windows Security might have blocked that smaller helper script; check Protection History and this log.'
    }

    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json

    Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue

    return $result
}

function Load-State {
    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Log -Level 'WARN' -Message "Could not read rollback state: $($_.Exception.Message)"
        return $null
    }
}

function Get-StateValues {
    param(
        $State,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($null -eq $State -or -not ($State.PSObject.Properties.Name -contains $PropertyName)) {
        return @()
    }
    return @($State.$PropertyName | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Get-StateEntryCount {
    $state = Load-State
    if ($null -eq $state) {
        return 0
    }
    return @(Get-StateValues -State $state -PropertyName 'AddedPaths').Count +
           @(Get-StateValues -State $state -PropertyName 'AddedProcesses').Count
}

function Save-AddedState {
    param(
        [string[]]$AddedPaths = @(),
        [string[]]$AddedProcesses = @(),
        [Parameter(Mandatory = $true)][object[]]$Installations
    )

    $existing = Load-State
    $pathSet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $processSet = New-Object 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)

    foreach ($path in @(Get-StateValues -State $existing -PropertyName 'AddedPaths')) {
        [void]$pathSet.Add([string]$path)
    }
    foreach ($processName in @(Get-StateValues -State $existing -PropertyName 'AddedProcesses')) {
        [void]$processSet.Add([string]$processName)
    }
    foreach ($path in $AddedPaths) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
            [void]$pathSet.Add([string]$path)
        }
    }
    foreach ($processName in $AddedProcesses) {
        if (-not [string]::IsNullOrWhiteSpace([string]$processName)) {
            [void]$processSet.Add([string]$processName)
        }
    }

    $state = [ordered]@{
        Version = $script:AppVersion
        Author = $script:Author
        Updated = (Get-Date).ToString('o')
        AddedPaths = @($pathSet)
        AddedProcesses = @($processSet)
        Installations = @($Installations | ForEach-Object { [string]$_.Path })
    }
    Write-JsonFile -Value $state -Path $script:StatePath
}

function Save-RemainingState {
    param(
        [string[]]$RemainingPaths = @(),
        [string[]]$RemainingProcesses = @()
    )

    if ($RemainingPaths.Count -eq 0 -and $RemainingProcesses.Count -eq 0) {
        Remove-Item -LiteralPath $script:StatePath -Force -ErrorAction SilentlyContinue
        return
    }

    $state = [ordered]@{
        Version = $script:AppVersion
        Author = $script:Author
        Updated = (Get-Date).ToString('o')
        AddedPaths = @($RemainingPaths)
        AddedProcesses = @($RemainingProcesses)
        Installations = @()
    }
    Write-JsonFile -Value $state -Path $script:StatePath
}

function Write-HelperResultDetails {
    param($Result)

    foreach ($warning in @($Result.Warnings)) {
        Write-Log -Level 'WARN' -Message ([string]$warning)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Result.VerificationTool)) {
        Write-Log -Level 'INFO' -Message "Effective verification tool: $($Result.VerificationTool)"
    }

    if ($null -ne $Result.DisableLocalAdminMerge) {
        Write-Log -Level 'INFO' -Message "DisableLocalAdminMerge: $($Result.DisableLocalAdminMerge)"
    }

    if ($null -ne $Result.DefenderStatus) {
        Write-Log -Level 'INFO' -Message "Defender status - AM service: $($Result.DefenderStatus.AMServiceEnabled), Antivirus: $($Result.DefenderStatus.AntivirusEnabled), Real-time protection: $($Result.DefenderStatus.RealTimeProtectionEnabled)"
    }

    foreach ($verification in @($Result.Verification)) {
        $stateText = if ($verification.State -eq $true) { 'Excluded' } elseif ($verification.State -eq $false) { 'NotExcluded' } else { 'Unknown' }
        Write-Log -Level 'INFO' -Message "MpCmdRun verification $stateText after $($verification.Attempts) attempt(s): $($verification.TestPath) (exit $($verification.ExitCode))"
        if (-not [string]::IsNullOrWhiteSpace([string]$verification.Output)) {
            Write-Log -Level 'INFO' -Message "MpCmdRun output: $($verification.Output)"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$verification.Error)) {
            Write-Log -Level 'WARN' -Message "MpCmdRun detail: $($verification.Error)"
        }
    }

    foreach ($failure in @($Result.Failed)) {
        $entryType = if ($failure.PSObject.Properties.Name -contains 'EntryType') { [string]$failure.EntryType } else { 'Path' }
        Write-Log -Level 'ERROR' -Message "$entryType exclusion failed: $($failure.Path) -- $($failure.Error)"
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Result.FatalError)) {
        Write-Log -Level 'ERROR' -Message "Helper fatal error: $($Result.FatalError)"
    }
}

function Invoke-AutomaticFix {
    if ($script:IsBusy) {
        return
    }

    Set-BusyState -Busy $true
    try {
        $installations = @(Find-DaocInstallations)
        if ($installations.Count -eq 0) {
            Set-UiStatus -Title 'DAoC installation not found' -Detail 'No folder passed the automatic DAoC identity checks.' -State 'Warning' -Progress 100
            Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Warning' -Message "No validated Dark Age of Camelot installation was found automatically.`r`n`r`nNo Defender setting was changed.`r`n`r`nLog: $($script:LogPath)"
            return
        }

        $targets = @(Get-InstallTargetPaths -Installations $installations)
        if ($targets.Count -eq 0) {
            throw 'Validated installations were found, but no installation folder could be prepared.'
        }

        Set-UiStatus -Title 'Applying the loading speed fix' -Detail "Configuring folder, core-file, and game.dll process exclusions for $($targets.Count) validated installation(s)..." -State 'Working'
        Write-Log -Level 'INFO' -Message "Applying supported Defender path exclusions and the game.dll process exclusion for $($targets.Count) validated DAoC installation(s)."
        foreach ($target in $targets) {
            Write-Log -Level 'INFO' -Message "Requested validated installation: $target"
        }

        $result = Invoke-HelperOperation -Mode 'Apply' -Paths $targets -Processes @($script:ProcessExclusionName)
        Write-HelperResultDetails -Result $result

        $addedPaths = @($result.Added)
        $existingPaths = @($result.Existing)
        $addedProcesses = @($result.AddedProcesses)
        $existingProcesses = @($result.ExistingProcesses)
        $failed = @($result.Failed)
        $warnings = @($result.Warnings)
        $verificationWarnings = @($result.Verification | Where-Object { $_.State -ne $true })
        $addedCount = $addedPaths.Count + $addedProcesses.Count
        $existingCount = $existingPaths.Count + $existingProcesses.Count

        if ($addedCount -gt 0) {
            Save-AddedState -AddedPaths $addedPaths -AddedProcesses $addedProcesses -Installations $installations
        }

        foreach ($path in $addedPaths) {
            Write-Log -Level 'OK' -Message "Added and confirmed exact path exclusion: $path"
        }
        foreach ($path in $existingPaths) {
            Write-Log -Level 'INFO' -Message "Exact path exclusion already present: $path"
        }
        foreach ($processName in $addedProcesses) {
            Write-Log -Level 'OK' -Message "Added and confirmed exact process exclusion: $processName"
        }
        foreach ($processName in $existingProcesses) {
            Write-Log -Level 'INFO' -Message "Exact process exclusion already present: $processName"
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$result.FatalError) -or $failed.Count -gt 0) {
            Set-UiStatus -Title 'Loading speed fix was incomplete' -Detail "$addedCount entries added, $existingCount already present, $($failed.Count) failed." -State 'Error' -Progress 100
            Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Error' -Message "The Faster Teleport/Load Times Fix completed with one or more configuration failures.`r`n`r`nAdded entries: $addedCount`r`nAlready present: $existingCount`r`nFailed entries: $($failed.Count)`r`n`r`nReview the activity log for the exact Windows error.`r`n$($script:LogPath)"
        }
        elseif ($warnings.Count -gt 0 -or $verificationWarnings.Count -gt 0) {
            Write-Log -Level 'IMPORTANT' -Message $script:RestartNotice
            Set-UiStatus -Title 'Fix configured - restart DAoC' -Detail "$addedCount entries added and $existingCount already present. Windows reported a verification warning. $($script:RestartNotice)" -State 'Warning' -Progress 100
            Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Warning' -Message "The supported Defender exclusion entries were configured automatically.`r`n`r`nValidated installations: $($installations.Count)`r`nNew exact entries: $addedCount`r`nAlready present: $existingCount`r`nProcess exclusion: $($script:ProcessExclusionName)`r`n`r`nIMPORTANT: $($script:RestartNotice)`r`n`r`nWindows Defender returned one or more effective-state verification warnings. The entries were kept instead of being removed. Details are in:`r`n$($script:LogPath)"
        }
        else {
            Write-Log -Level 'IMPORTANT' -Message $script:RestartNotice
            Set-UiStatus -Title 'Loading speed fix completed - restart DAoC' -Detail "$addedCount entries added and verified; $existingCount were already present. $($script:RestartNotice)" -State 'Good' -Progress 100
            Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Information' -Message "The Faster Teleport/Load Times Fix completed successfully.`r`n`r`nValidated installations: $($installations.Count)`r`nNew exact entries: $addedCount`r`nAlready present: $existingCount`r`nProcess exclusion: $($script:ProcessExclusionName)`r`n`r`nThe tool configured each validated DAoC folder, its existing core files, and the game.dll process exclusion.`r`n`r`nIMPORTANT: $($script:RestartNotice)"
        }
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Loading speed fix failed: $($_.Exception.Message)"
        Set-UiStatus -Title 'Loading speed fix failed' -Detail $_.Exception.Message -State 'Error' -Progress 100
        Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Error' -Message "The Faster Teleport/Load Times Fix could not complete.`r`n`r`n$($_.Exception.Message)`r`n`r`nLog: $($script:LogPath)"
    }
    finally {
        Set-BusyState -Busy $false
    }
}

function Invoke-Rollback {
    if ($script:IsBusy) {
        return
    }

    $state = Load-State
    $paths = @(Get-StateValues -State $state -PropertyName 'AddedPaths')
    $processes = @(Get-StateValues -State $state -PropertyName 'AddedProcesses')
    $entryCount = $paths.Count + $processes.Count
    if ($entryCount -eq 0) {
        Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Message 'There are no tool-owned exclusion entries to remove.'
        return
    }

    Set-BusyState -Busy $true
    try {
        Set-UiStatus -Title 'Rolling back' -Detail "Removing $entryCount exact exclusion entry or entries previously added by this tool..." -State 'Working'
        $result = Invoke-HelperOperation -Mode 'Remove' -Paths $paths -Processes $processes
        Write-HelperResultDetails -Result $result

        $removedPaths = @($result.Removed)
        $absentPaths = @($result.AlreadyAbsent)
        $removedProcesses = @($result.RemovedProcesses)
        $absentProcesses = @($result.ProcessesAlreadyAbsent)
        $failedPaths = @($result.Failed | Where-Object { -not ($_.PSObject.Properties.Name -contains 'EntryType') -or $_.EntryType -eq 'Path' } | ForEach-Object { [string]$_.Path })
        $failedProcesses = @($result.Failed | Where-Object { $_.PSObject.Properties.Name -contains 'EntryType' -and $_.EntryType -eq 'Process' } | ForEach-Object { [string]$_.Path })
        Save-RemainingState -RemainingPaths $failedPaths -RemainingProcesses $failedProcesses

        foreach ($path in $removedPaths) {
            Write-Log -Level 'OK' -Message "Removed and confirmed exact path exclusion: $path"
        }
        foreach ($path in $absentPaths) {
            Write-Log -Level 'INFO' -Message "Path exclusion already absent during rollback: $path"
        }
        foreach ($processName in $removedProcesses) {
            Write-Log -Level 'OK' -Message "Removed and confirmed exact process exclusion: $processName"
        }
        foreach ($processName in $absentProcesses) {
            Write-Log -Level 'INFO' -Message "Process exclusion already absent during rollback: $processName"
        }

        $removedCount = $removedPaths.Count + $removedProcesses.Count
        $absentCount = $absentPaths.Count + $absentProcesses.Count
        $failedCount = $failedPaths.Count + $failedProcesses.Count
        if ($failedCount -gt 0 -or -not [string]::IsNullOrWhiteSpace([string]$result.FatalError)) {
            Set-UiStatus -Title 'Rollback was incomplete' -Detail "$removedCount removed, $absentCount already absent, $failedCount failed." -State 'Warning' -Progress 100
            Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Warning' -Message "Rollback completed with failures.`r`n`r`nRemoved: $removedCount`r`nAlready absent: $absentCount`r`nFailed: $failedCount`r`n`r`nOnly failed entries remain in rollback state."
        }
        else {
            Set-UiStatus -Title 'Rollback completed' -Detail "$removedCount removed; $absentCount were already absent." -State 'Good' -Progress 100
            Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Message 'All path and process exclusion entries created by this tool were removed or were already absent.'
        }
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Rollback failed: $($_.Exception.Message)"
        Set-UiStatus -Title 'Rollback failed' -Detail $_.Exception.Message -State 'Error' -Progress 100
        Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Error' -Message $_.Exception.Message
    }
    finally {
        Set-BusyState -Busy $false
    }
}

function Get-BitmapImage {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object System.Uri -ArgumentList $Path
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DAoC Loading Speed Fix - By Cosmy"
        Width="1360"
        Height="900"
        MinWidth="1100"
        MinHeight="700"
        WindowStartupLocation="CenterScreen"
        WindowState="Maximized"
        ResizeMode="CanResizeWithGrip"
        Background="#0B0807"
        FontFamily="Segoe UI"
        UseLayoutRounding="True">
    <Window.Resources>
        <SolidColorBrush x:Key="BackgroundBrush" Color="#0B0807"/>
        <SolidColorBrush x:Key="SurfaceBrush" Color="#17100E"/>
        <SolidColorBrush x:Key="SurfaceAltBrush" Color="#211713"/>
        <SolidColorBrush x:Key="SurfaceDeepBrush" Color="#100B0A"/>
        <SolidColorBrush x:Key="CopperBrush" Color="#C86A20"/>
        <SolidColorBrush x:Key="EmberBrush" Color="#F08A27"/>
        <SolidColorBrush x:Key="PurpleBrush" Color="#8C3FD1"/>
        <SolidColorBrush x:Key="BurgundyBrush" Color="#6E171B"/>
        <SolidColorBrush x:Key="SilverBrush" Color="#F2ECE5"/>
        <SolidColorBrush x:Key="MutedBrush" Color="#C4AA96"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#5B3525"/>
        <LinearGradientBrush x:Key="HeroGradient" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#28110C" Offset="0"/>
            <GradientStop Color="#32131B" Offset="0.52"/>
            <GradientStop Color="#241038" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="PrimaryGradient" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#B84D16" Offset="0"/>
            <GradientStop Color="#E27C24" Offset="0.55"/>
            <GradientStop Color="#9A3516" Offset="1"/>
        </LinearGradientBrush>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource SilverBrush}"/>
        </Style>
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource SurfaceBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="14"/>
            <Setter Property="Padding" Value="16"/>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="{StaticResource PrimaryGradient}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}" BorderBrush="#F4A45E" BorderThickness="1">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.70"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.38"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="#34231D"/>
        </Style>
        <Style TargetType="ListView">
            <Setter Property="Background" Value="{StaticResource SurfaceDeepBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource SilverBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="GridViewColumnHeader">
            <Setter Property="Background" Value="#2B1A15"/>
            <Setter Property="Foreground" Value="#F3C79D"/>
            <Setter Property="BorderBrush" Value="#5B3525"/>
            <Setter Property="Padding" Value="8,7"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="ProgressBar">
            <Setter Property="Foreground" Value="{StaticResource EmberBrush}"/>
            <Setter Property="Background" Value="#3A241B"/>
            <Setter Property="Height" Value="9"/>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="340" MinWidth="320" MaxWidth="380"/>
            <ColumnDefinition Width="16"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="{StaticResource HeroGradient}" BorderBrush="#A75224" BorderThickness="1" CornerRadius="18" Padding="18">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0" Background="#160D0B" BorderBrush="#D37A35" BorderThickness="1" CornerRadius="16" Padding="7">
                    <Image x:Name="BrandImage" Width="286" Height="286" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
                </Border>

                <StackPanel Grid.Row="1" Margin="2,18,2,0">
                    <TextBlock Text="DAoC Loading Speed Fix - By Cosmy" FontSize="23" FontWeight="Bold" TextWrapping="Wrap" TextTrimming="None" LineHeight="28"/>
                    <TextBlock Text="Faster Teleport/Load Times Fix" Foreground="#F0A15E" FontSize="12" FontWeight="SemiBold" Margin="1,7,0,0" TextWrapping="Wrap"/>
                    <TextBlock Text="Windows 10 and Windows 11" Foreground="#D9C8BA" FontSize="12" FontWeight="SemiBold" Margin="1,5,0,0"/>
                    <TextBlock Text="Created by Cosmy." Foreground="#D9C8BA" FontSize="13" FontWeight="SemiBold" Margin="1,9,0,0"/>
                </StackPanel>

                <Border Grid.Row="2" Background="#261512" BorderBrush="#6E3B28" BorderThickness="1" CornerRadius="12" Padding="12" Margin="0,18,0,0">
                    <StackPanel>
                        <TextBlock Text="AUTOMATIC WORKFLOW" Foreground="#F0A15E" FontWeight="Bold" FontSize="11"/>
                        <Grid Margin="0,11,0,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Ellipse Width="8" Height="8" Fill="#8C3FD1" VerticalAlignment="Top" Margin="0,5,0,0"/>
                            <TextBlock Grid.Column="1" Text="Find and validate DAoC installs" Foreground="#E6D8CC" TextWrapping="Wrap"/>
                        </Grid>
                        <Grid Margin="0,9,0,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Ellipse Width="8" Height="8" Fill="#F08A27" VerticalAlignment="Top" Margin="0,5,0,0"/>
                            <TextBlock Grid.Column="1" Text="Configure folder, core-file, and game.dll process exclusions" Foreground="#E6D8CC" TextWrapping="Wrap"/>
                        </Grid>
                        <Grid Margin="0,9,0,0">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Ellipse Width="8" Height="8" Fill="#D9D2CC" VerticalAlignment="Top" Margin="0,5,0,0"/>
                            <TextBlock Grid.Column="1" Text="Verify, save rollback state, then restart DAoC" Foreground="#E6D8CC" TextWrapping="Wrap"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <StackPanel Grid.Row="4" Margin="2,18,2,0">
                    <TextBlock Text="VERSION 1.0.2" Foreground="#BDA38F" FontSize="11" FontWeight="SemiBold"/>
                    <TextBlock Text="One normal UAC approval is required by Windows. No folder selection is required on Windows 10 or Windows 11." Foreground="#A88F7F" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <Grid Grid.Column="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="3*" MinHeight="220"/>
                <RowDefinition Height="2*" MinHeight="160"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="2,0,2,14">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="DAoC Loading Speed Fix - By Cosmy" FontSize="27" FontWeight="Bold" TextWrapping="Wrap" TextTrimming="None"/>
                    <TextBlock Text="Faster Teleport/Load Times Fix for Windows 10 and Windows 11" Foreground="{StaticResource MutedBrush}" FontSize="13" Margin="0,5,0,0" TextWrapping="Wrap"/>
                </StackPanel>
                <Border x:Name="StatusPill" Grid.Column="1" Background="#6D3AA8" CornerRadius="14" Padding="13,7" VerticalAlignment="Top">
                    <TextBlock x:Name="StatusPillText" Text="READY" FontSize="11" FontWeight="Bold" Foreground="White"/>
                </Border>
            </Grid>

            <Border Grid.Row="1" Style="{StaticResource CardStyle}" Margin="0,0,0,14">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="230"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock x:Name="StatusTitle" Text="Ready" FontSize="19" FontWeight="SemiBold"/>
                        <TextBlock x:Name="StatusDetail" Text="The Faster Teleport/Load Times Fix starts automatically. Restart Dark Age of Camelot after completion." Foreground="{StaticResource MutedBrush}" Margin="0,6,18,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                        <ProgressBar x:Name="ProgressBar" Minimum="0" Maximum="100" Value="0"/>
                        <TextBlock Text="Automatic mode" Foreground="#B68E73" FontSize="10" HorizontalAlignment="Right" Margin="0,5,0,0"/>
                    </StackPanel>
                </Grid>
            </Border>

            <Border Grid.Row="2" Style="{StaticResource CardStyle}" Margin="0,0,0,14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="Validated installations" FontSize="16" FontWeight="SemiBold"/>
                        <TextBlock x:Name="DetectedCount" Grid.Column="1" Text="0 validated installation(s)" Foreground="{StaticResource MutedBrush}"/>
                    </Grid>
                    <ListView x:Name="InstallList" Grid.Row="1">
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="Installation path" Width="475" DisplayMemberBinding="{Binding Path}"/>
                                <GridViewColumn Header="Confidence" Width="92" DisplayMemberBinding="{Binding Confidence}"/>
                                <GridViewColumn Header="Version" Width="120" DisplayMemberBinding="{Binding Version}"/>
                                <GridViewColumn Header="Core files" Width="82" DisplayMemberBinding="{Binding CoreFiles}"/>
                            </GridView>
                        </ListView.View>
                    </ListView>
                </Grid>
            </Border>

            <Border Grid.Row="3" Style="{StaticResource CardStyle}" Margin="0,0,0,14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="Activity log" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,9"/>
                    <TextBox x:Name="ActivityBox" Grid.Row="1" IsReadOnly="True" TextWrapping="NoWrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="#0E0908" Foreground="#E5D8CD" BorderBrush="#5B3525" FontFamily="Consolas" FontSize="11.5" Padding="10"/>
                </Grid>
            </Border>

            <Grid Grid.Row="4">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="Created by Cosmy." Foreground="{StaticResource MutedBrush}" VerticalAlignment="Center" TextWrapping="Wrap" Margin="2,0,16,0"/>
                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <Button x:Name="OpenLogsButton" Content="Open logs" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                    <Button x:Name="RollbackButton" Content="Roll back" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0" IsEnabled="False"/>
                    <Button x:Name="RunButton" Content="Apply loading speed fix" Style="{StaticResource PrimaryButton}" Margin="0,0,8,0"/>
                    <Button x:Name="CloseButton" Content="Close" Style="{StaticResource SecondaryButton}"/>
                </StackPanel>
            </Grid>
        </Grid>
    </Grid>
</Window>
'@

$reader = New-Object Xml.XmlNodeReader $xaml
$script:Window = [System.Windows.Markup.XamlReader]::Load($reader)

foreach ($controlName in @(
    'BrandImage', 'StatusPill', 'StatusPillText', 'StatusTitle', 'StatusDetail', 'ProgressBar',
    'DetectedCount', 'InstallList', 'ActivityBox', 'OpenLogsButton',
    'RollbackButton', 'RunButton', 'CloseButton'
)) {
    Set-Variable -Scope Script -Name $controlName -Value $script:Window.FindName($controlName)
}

try {
    $brandBitmap = Get-BitmapImage -Path $script:BrandImagePath
    if ($null -ne $brandBitmap) {
        $script:BrandImage.Source = $brandBitmap
    }
    else {
        Write-Log -Level 'WARN' -Message "Application artwork was not found: $($script:BrandImagePath)"
    }

    $iconBitmap = Get-BitmapImage -Path $script:AppIconPath
    if ($null -ne $iconBitmap) {
        $script:Window.Icon = $iconBitmap
    }
}
catch {
    Write-Log -Level 'WARN' -Message "Could not load application artwork: $($_.Exception.Message)"
}

Write-Log -Level 'INFO' -Message "Created by $($script:Author)."
Write-Log -Level 'INFO' -Message "Main UI loaded from $PSCommandPath"
Write-Log -Level 'INFO' -Message "Helper path: $($script:HelperPath)"
Write-Log -Level 'INFO' -Message "Application artwork path: $($script:BrandImagePath)"
try {
    $startupHelperHash = (Get-FileHash -LiteralPath $script:HelperPath -Algorithm SHA256).Hash
    Write-Log -Level 'INFO' -Message "Helper SHA-256: $startupHelperHash"
    Write-Log -Level 'INFO' -Message "Helper integrity expected: $($script:ExpectedHelperSha256)"
}
catch {
    Write-Log -Level 'WARN' -Message "Could not hash helper: $($_.Exception.Message)"
}

$script:RunButton.add_Click({ Invoke-AutomaticFix })
$script:RollbackButton.add_Click({ Invoke-Rollback })
$script:OpenLogsButton.add_Click({
    try {
        [void](Start-Process explorer.exe -ArgumentList "`"$($script:LogRoot)`"")
    }
    catch {
        Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Error' -Message $_.Exception.Message
    }
})
$script:CloseButton.add_Click({ $script:Window.Close() })
$script:Window.add_Closing({
    param($sender, $eventArgs)
    if ($script:IsBusy) {
        $eventArgs.Cancel = $true
        Show-Dialog -Title 'DAoC Loading Speed Fix - By Cosmy' -Kind 'Warning' -Message 'Finish the current automatic operation before closing the window.'
    }
})

$script:StartupTimer = New-Object Windows.Threading.DispatcherTimer
$script:StartupTimer.Interval = [TimeSpan]::FromMilliseconds(650)
$script:StartupTimer.add_Tick({
    $script:StartupTimer.Stop()
    Invoke-AutomaticFix
})

$script:Window.add_Loaded({
    $script:Window.WindowState = [System.Windows.WindowState]::Maximized
    [void]$script:Window.Activate()
    Set-BusyState -Busy $false
    Set-UiStatus -Title 'Starting loading speed fix' -Detail 'Preparing installation discovery...' -State 'Working'
    $script:StartupTimer.Start()
})

[void]$script:Window.ShowDialog()
