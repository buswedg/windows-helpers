@echo off

set "SCRIPT_PATH=%~dp0Nvidia-Driver-Manager.ps1"

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -mode download-only -folder %~dp0downloads
pause
