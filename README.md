# DAoC Loading Speed Fix - By Cosmy

Created by Cosmy.

A one-click Windows utility for the Dark Age of Camelot Faster Teleport/Load Times Fix. It automatically finds validated DAoC installations and configures Microsoft Defender path exclusions for the installation folder and existing core client files, plus the `game.dll` process exclusion used by the fix.

## Supported systems

- Windows 10 64-bit
- Windows 11 64-bit
- Windows PowerShell 5.1
- Microsoft Defender Antivirus
- A local administrator account

## Run

1. Download and extract the release ZIP to a local folder.
2. Double-click `Run-DAoC-Loading-Speed-Fix.cmd`.
3. Approve the Windows administrator prompt.
4. After the application reports completion, close and restart Dark Age of Camelot before testing teleport or load times.

The application opens maximized and the fix starts automatically. No DAoC folder selection or manual Windows Security configuration is required.

## What the tool does

- Detects official and custom DAoC installations on local fixed drives.
- Validates each installation before changing Defender preferences.
- Adds exact path exclusions for each validated installation folder and its existing core client files.
- Adds and verifies `game.dll` in the Microsoft Defender process exclusion list.
- Verifies that the exact entries appear in Microsoft Defender preferences.
- Uses `MpCmdRun.exe -CheckExclusion -Path` as an additional verification check when available.
- Saves a detailed activity log.
- Keeps a rollback record for exclusions created by the tool.

## Restart required

Restart Dark Age of Camelot for the fix to take effect. After the exclusions are applied, close the running game client completely, then launch it again. If the game was not running, start it after the tool reports completion.

## Safety

The tool does not disable Microsoft Defender, real-time protection, script scanning, tamper protection, services, or security policy. It rejects network paths, drive roots, removable drives, Windows system folders, protected system folders, and reparse-point paths.

Organization-managed security policy can prevent local exclusions from becoming effective. The tool reports this condition in its activity log when Windows exposes it.

## Rollback

Open the application and select **Roll back**. Only exact path and process exclusion entries recorded as created by this tool are removed.

## Logs and state

```text
C:\ProgramData\DAoCLoadingSpeedFix\Logs
C:\ProgramData\DAoCLoadingSpeedFix\state.json
```

Created by Cosmy.
