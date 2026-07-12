# Contributing

Created by Cosmy.

Bug reports and focused pull requests are welcome.

Before submitting a change:

1. Keep Windows PowerShell 5.1 compatibility.
2. Keep PowerShell and command files ASCII-only with CRLF line endings.
3. Do not disable Microsoft Defender protections or use obfuscation.
4. Run `scripts\Test-Project.ps1`.
5. Describe the behavior being fixed and the Windows 10 or Windows 11 build used for testing.

Run project validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Project.ps1
```

Build the end-user release ZIP:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1
```

All submitted work must preserve the application name and the attribution `Created by Cosmy.`
