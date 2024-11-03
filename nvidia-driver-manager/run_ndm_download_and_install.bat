@echo off
set "SCRIPT_PATH=%~dp0Nvidia-Driver-Manager.ps1"
net session >nul 2>&1
if %errorlevel% equ 0 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -mode download-install -folder %~dp0downloads
	pause
) else (
    echo Script must be run with Administrator privileges.
    pause
)
