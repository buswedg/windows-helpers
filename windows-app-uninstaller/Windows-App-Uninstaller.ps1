<#
.SYNOPSIS
Uninstalls Windows Store applications using PowerShell.

.DESCRIPTION
This script reads a JSON file containing a list of application package names, and uninstalls each matching app for all users.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that contains the list of apps to uninstall.

.OUTPUTS
Console output and log file saved to %TEMP%\windows-app-uninstaller.log.

.EXAMPLE
PS> .\Windows-App-Uninstaller.ps1 -Json "test.json"
Uninstalls all applications listed in test.json.

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

$LogPath = Join-Path $env:TEMP "windows-app-uninstaller.log"
Start-Transcript -Path $LogPath

$ConfigData = Get-ConfigData

if (-not $ConfigData.Apps -or $ConfigData.Apps.Count -eq 0) {
    Write-Host "No apps found in config file." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

Write-Host "`nUninstalling Applications..." -ForegroundColor Green

foreach ($app in $ConfigData.Apps) {
    $package = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
    if ($package) {
        Write-Host "Uninstalling $app..." -ForegroundColor Yellow
        try {
            $package | Remove-AppxPackage -Confirm:$false
        } catch {
            Write-Host ("Failed to uninstall {0}: {1}" -f $app, $_.Exception.Message) -ForegroundColor Red
        }
    } else {
        Write-Host "$app is not installed." -ForegroundColor Cyan
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Log saved to: $LogPath"
Write-Host "`nExiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
