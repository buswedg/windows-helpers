@echo off

net session >nul 2>&1
if %errorLevel%==0 (
    goto :main
)

if "%~1"=="-elevated" (
    echo Elevation failed. UAC is likely disabled.
    pause
    exit /b 1
)

echo Requesting administrator privileges...
powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\" -elevated' -Verb RunAs"
exit /b

:main
set "SCRIPT_PATH=%~dp0Network-Adapter-Manager.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_PATH%" -json "default.json" -mode enable
pause
