<#
.SYNOPSIS
Installs applications using WinGet and PowerShell.

.DESCRIPTION
This script reads a JSON file that lists application IDs, and installs each application ID via WinGet.
Automatically installs WinGet if not found. Skips applications that are already installed.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) containing application IDs and optional cleanup info.

.OUTPUTS
Console output and log file saved to %TEMP%\winget-installer.log.

.EXAMPLE
PS> .\Winget-Installer.ps1 -Json "test.json"
Installs all applications listed in test.json using WinGet.

.LINK
None
#>

[CmdletBinding()]
param (
    [string]$Json
)

#Requires -RunAsAdministrator

function Get-ConfigData {
    $configDir = Join-Path $PSScriptRoot "configs"
    if (-not (Test-Path $configDir)) {
        Write-Host "Config directory not found: $configDir" -ForegroundColor Red
        exit 1
    }

    if ($Json) {
        $path = Join-Path $configDir $Json
        if (-not (Test-Path $path)) {
            Write-Host "Specified JSON config file does not exist: $path" -ForegroundColor Red
            exit 1
        }
        return Get-Content $path -Raw | ConvertFrom-Json
    }

    $jsonFiles = Get-ChildItem -Path $configDir -Filter *.json
    if ($jsonFiles.Count -eq 0) {
        Write-Host "No JSON config files found in '$configDir'." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $jsonFiles.Count; $i++) {
        Write-Host "$($i + 1): $($jsonFiles[$i].Name)"
    }

    do {
        $selection = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($selection -match '^\d+$') -or [int]$selection -lt 1 -or [int]$selection -gt $jsonFiles.Count)

    $selectedFile = $jsonFiles[[int]$selection - 1].FullName
    return Get-Content $selectedFile -Raw | ConvertFrom-Json
}

# --- Execution ---
$LogPath = Join-Path $env:TEMP "winget-installer.log"
Start-Transcript -Path $LogPath

if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
    Write-Host "WinGet not found. Installing..." -ForegroundColor Yellow

    Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
    Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\winget.msixbundle"

    Add-AppxPackage "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx" -ErrorAction SilentlyContinue
    Add-AppxPackage "$env:TEMP\winget.msixbundle" -ErrorAction SilentlyContinue

    Remove-Item "$env:TEMP\winget" -Recurse -Force -ErrorAction SilentlyContinue
}

$ConfigData = Get-ConfigData

# Install apps
Write-Host "`nInstalling applications (skipping if already present)..." -ForegroundColor Green

foreach ($app in $ConfigData.Apps) {
    Write-Host "`nChecking if '$app' is already installed..."
    winget list --id $app --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq -1978335212) {
        Write-Host "$app not found. Installing..." -ForegroundColor Yellow
        winget install $app --silent --force --source winget --accept-package-agreements --accept-source-agreements
        foreach ($proc in $ConfigData.ProcessesToKill) {
            Get-Process $proc -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
        }
    } else {
        Write-Host "$app is already installed." -ForegroundColor Cyan
    }
}

# Cleanup files
if ($ConfigData.FilesToClean) {
    Write-Host "`nCleaning specified files from desktops..." -ForegroundColor Green
    $publicDesktop = "C:\Users\Public\Desktop"
    $userDesktop = [Environment]::GetFolderPath("Desktop")
    $cutoffTime = (Get-Date).AddHours(-1)

    foreach ($file in $ConfigData.FilesToClean) {
        foreach ($path in @($publicDesktop, $userDesktop)) {
            Get-ChildItem "$path\$file" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -le $cutoffTime } |
                Remove-Item -Force -ErrorAction SilentlyContinue

            Get-ChildItem "$path\$file" -Hidden -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -le $cutoffTime } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Log saved to: $LogPath"
Write-Host "`nExiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
