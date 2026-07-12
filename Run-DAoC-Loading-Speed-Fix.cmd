@echo off
rem Created by Cosmy.
setlocal EnableExtensions DisableDelayedExpansion

title DAoC Loading Speed Fix - By Cosmy
set "SCRIPT=%~dp0DAoC-Loading-Speed-Fix.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if /I "%~1"=="--launcher-test" goto :launcher_test
if exist "%SCRIPT%" goto :run
goto :missing

:launcher_test
if exist "%SCRIPT%" exit /b 0
exit /b 2

:missing
echo.
echo DAoC Loading Speed Fix could not start because the PowerShell application is missing.
echo Extract the complete release ZIP and keep all files together.
echo.
echo Created by Cosmy.
pause
exit /b 2

:run
"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%"
set "EXITCODE=%ERRORLEVEL%"
if "%EXITCODE%"=="0" goto :finish

echo.
echo DAoC Loading Speed Fix exited with code %EXITCODE%.
echo Created by Cosmy.
pause

:finish
exit /b %EXITCODE%
