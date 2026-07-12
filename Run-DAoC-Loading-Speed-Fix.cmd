@echo off
rem Created by Cosmy.
setlocal EnableExtensions

title DAoC Loading Speed Fix - By Cosmy
set "SCRIPT=%~dp0DAoC-Loading-Speed-Fix.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SCRIPT%" (
    echo.
    echo DAoC Loading Speed Fix could not start because this file is missing:
    echo %SCRIPT%
    echo.
    echo Created by Cosmy.
    pause
    exit /b 2
)

"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%"
set "EXITCODE=%ERRORLEVEL%"

if not "%EXITCODE%"=="0" (
    echo.
    echo DAoC Loading Speed Fix exited with code %EXITCODE%.
    echo Created by Cosmy.
    pause
)

exit /b %EXITCODE%
