<#
.SYNOPSIS
Installs a configurable list of applications using WinGet and PowerShell.

.DESCRIPTION
This script reads a JSON file that lists application IDs, and installs each application ID via WinGet.
Automatically installs WinGet if not found. Skips applications that are already installed.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) containing application IDs and optional cleanup info.

.OUTPUTS
Console output and log file saved to %TEMP%\winget-installer.log.

.EXAMPLE
PS> .\Winget-Installer.ps1 -Json "test.json"
#>

[CmdletBinding()]
param (
    [string]$Json
)

#Requires -RunAsAdministrator

function Get-ConfigData
{
    $ConfigDir = Join-Path $PSScriptRoot "configs"
    if (-not (Test-Path $ConfigDir))
    {
        Write-Host "Config directory not found: $ConfigDir" -ForegroundColor Red
        exit 1
    }

    if ($Json)
    {
        $ConfigPath = Join-Path $ConfigDir $Json
        if (-not (Test-Path $ConfigPath))
        {
            Write-Host "Specified JSON config file does not exist: $ConfigPath" -ForegroundColor Red
            exit 1
        }
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }

    $ConfigFiles = Get-ChildItem -Path $ConfigDir -Filter *.json
    if ($ConfigFiles.Count -eq 0)
    {
        Write-Host "No JSON config files found in '$ConfigDir'." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++) {
        Write-Host "$( $i + 1 ): $( $ConfigFiles[$i].Name )"
    }

    do
    {
        $Selection = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Selection -match '^\d+$') -or [int]$Selection -lt 1 -or [int]$Selection -gt $ConfigFiles.Count)

    $ConfigFile = $ConfigFiles[[int]$Selection - 1].FullName
    return Get-Content $ConfigFile -Raw | ConvertFrom-Json
}

# --- Execution ---
$LogPath = Join-Path $env:TEMP "winget-installer.log"
Start-Transcript -Path $LogPath

if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue))
{
    Write-Host "WinGet not found. Installing..." -ForegroundColor Yellow

    Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
    Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\winget.msixbundle"

    Add-AppxPackage "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx" -ErrorAction SilentlyContinue
    Add-AppxPackage "$env:TEMP\winget.msixbundle" -ErrorAction SilentlyContinue

    Remove-Item "$env:TEMP\winget" -Recurse -Force -ErrorAction SilentlyContinue
}

$ConfigData = Get-ConfigData

if (-not $ConfigData.Apps -or $ConfigData.Apps.Count -eq 0)
{
    Write-Host "No apps found in config file." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

# Install apps
Write-Host "`nInstalling applications (skipping if already present)..." -ForegroundColor Green

foreach ($App in $ConfigData.Apps)
{
    Write-Host "`nChecking if '$App' is already installed..."
    winget list --id $App --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq -1978335212)
    {
        Write-Host "$App not found. Installing..." -ForegroundColor Yellow
        winget install $App --silent --force --source winget --accept-package-agreements --accept-source-agreements
        foreach ($Proc in $ConfigData.ProcessesToKill)
        {
            Get-Process $Proc -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
        }
    }
    else
    {
        Write-Host "$App is already installed." -ForegroundColor Cyan
    }
}

# Cleanup files
if ($ConfigData.FilesToClean)
{
    Write-Host "`nCleaning specified files from desktop..." -ForegroundColor Green
    $PublicDesktop = "C:\Users\Public\Desktop"
    $UserDesktop = [Environment]::GetFolderPath("Desktop")
    $CutoffTime = (Get-Date).AddHours(-1)

    foreach ($File in $ConfigData.FilesToClean)
    {
        foreach ($Path in @($PublicDesktop, $UserDesktop))
        {
            Get-ChildItem "$Path\$File" -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -le $CutoffTime } |
                    Remove-Item -Force -ErrorAction SilentlyContinue

            Get-ChildItem "$Path\$File" -Hidden -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -le $CutoffTime } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Exiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
