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
PS> .\Store-App-Uninstaller.ps1 -Json "default.json"
#>

[CmdletBinding()]
param (
    [string]$Json
)

#Requires -RunAsAdministrator

# --- Function Definitions ---

function Get-ConfigPath
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
            if (Test-Path $Json)
            {
                return $Json
            }
            Write-Host "Specified JSON config file does not exist: $ConfigPath" -ForegroundColor Red
            exit 1
        }
        return $ConfigPath
    }

    $ConfigFiles = Get-ChildItem -Path $ConfigDir -Filter *.json
    if ($ConfigFiles.Count -eq 0)
    {
        Write-Host "No JSON config files found in '$ConfigDir'." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++)
    {
        Write-Host ("{0}: {1}" -f ($i + 1), $ConfigFiles[$i].Name)
    }

    do
    {
        $Selection = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Selection -match '^\d+$') -or [int]$Selection -lt 1 -or [int]$Selection -gt $ConfigFiles.Count)

    return $ConfigFiles[[int]$Selection - 1].FullName
}

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "store-app-uninstaller.log"
Start-Transcript -Path $LogPath

try
{
    $ConfigPath = Get-ConfigPath
    try
    {
        $ConfigData = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch
    {
        Write-Host "Failed to parse JSON: $ConfigPath" -ForegroundColor Red
        return
    }

    if (-not $ConfigData.Apps -or $ConfigData.Apps.Count -eq 0)
    {
        Write-Host "No apps found in config file." -ForegroundColor Yellow
        return
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
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
finally
{
    Stop-Transcript
    Write-Host "`nAll operations completed. Exiting in 5 seconds..."
    Start-Sleep -Seconds 5
}
