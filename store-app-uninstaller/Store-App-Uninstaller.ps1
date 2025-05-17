<#
.SYNOPSIS
Uninstalls a configurable list of Windows Store applications using PowerShell.

.DESCRIPTION
This script reads a JSON file containing a list of application package names, and uninstalls each matching app for all users.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that contains the list of apps to uninstall.

.OUTPUTS
Console output and log file saved to %TEMP%\store-app-uninstaller.log.

.EXAMPLE
PS> .\Store-App-Uninstaller.ps1 -Json "test.json"
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

$LogPath = Join-Path $env:TEMP "store-app-uninstaller.log"
Start-Transcript -Path $LogPath

$ConfigData = Get-ConfigData

if (-not $ConfigData.Apps -or $ConfigData.Apps.Count -eq 0)
{
    Write-Host "No apps found in config file." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

Write-Host "`nUninstalling Applications..." -ForegroundColor Green

foreach ($App in $ConfigData.Apps)
{
    $Package = Get-AppxPackage -Name $App -AllUsers -ErrorAction SilentlyContinue
    if ($Package)
    {
        Write-Host "Uninstalling $App..." -ForegroundColor Yellow
        try
        {
            $Package | Remove-AppxPackage -Confirm:$false
        }
        catch
        {
            Write-Host ("Failed to uninstall {0}: {1}" -f $App, $_.Exception.Message) -ForegroundColor Red
        }
    }
    else
    {
        Write-Host "$App is not installed." -ForegroundColor Cyan
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Exiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
