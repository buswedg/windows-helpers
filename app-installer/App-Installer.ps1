<#
.SYNOPSIS
Installs a configurable list of applications using PowerShell.

.DESCRIPTION
This script reads a JSON file that lists applications, and downloads/installs each application via PowerShell.

.PARAMETER Config
Name of the JSON file (from the 'configs' directory) containing application configurations.

.OUTPUTS
Console output and log file saved to %TEMP%\app-installer.log.

.EXAMPLE
PS> .\App-Installer.ps1 -Config "config.json"
#>

[CmdletBinding()]
param (
    [string]$Config,
    [switch]$DownloadOnly
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

    if ($Config)
    {
        $ConfigPath = Join-Path $ConfigDir $Config
        if (-not (Test-Path $ConfigPath))
        {
            if (Test-Path $Config)
            {
                return $Config
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

function Download-Files
{
    param ($Config)

    if (-not (Test-Path $Folder))
    {
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
    }

    Write-Host "`nAvailable download options:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $Config.Count; $i++)
    {
        Write-Host ("{0}) {1}" -f ($i + 1), $Config[$i].app_name)
    }
    Write-Host ("{0}) Download All" -f ($Config.Count + 1))

    $Choice = Read-Host "`nEnter the number of the download option to perform"
    
    if (-not ($Choice -match '^\d+$'))
    {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return
    }

    $Choice = [int]$Choice

    if ($Choice -eq ($Config.Count + 1))
    {
        foreach ($Item in $Config)
        {
            Write-Host "Downloading $($Item.app_name)..." -ForegroundColor Cyan
            $Downloaded = Invoke-Download -URL $Item.download_url -Destination $Folder
            $Item.filename = [System.IO.Path]::GetFileName($Downloaded)
        }
    }
    elseif ($Choice -ge 1 -and $Choice -le $Config.Count)
    {
        $Item = $Config[$Choice - 1]
        Write-Host "Downloading $($Item.app_name)..." -ForegroundColor Cyan
        $Downloaded = Invoke-Download -URL $Item.download_url -Destination $Folder
        $Item.filename = [System.IO.Path]::GetFileName($Downloaded)
    }
    else
    {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }
}

function Install-Files
{
    param ($Config)

    Write-Host "`nAvailable install options:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $Config.Count; $i++)
    {
        Write-Host ("{0}) Install {1}" -f ($i + 1), $Config[$i].app_name)
    }
    Write-Host ("{0}) Install All" -f ($Config.Count + 1))

    $Choice = Read-Host "`nEnter the number of the install option to perform"
    
    if (-not ($Choice -match '^\d+$'))
    {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return
    }

    $Choice = [int]$Choice

    if ($Choice -eq ($Config.Count + 1))
    {
        foreach ($Item in $Config)
        {
            $FilePath = Join-Path $Folder $Item.filename
            if (Test-Path $FilePath)
            {
                Write-Host "Installing $($Item.app_name)..." -ForegroundColor Cyan
                Start-Process -FilePath $FilePath -Verb RunAs
            }
            else
            {
                Write-Host "File not found for $($Item.app_name): $FilePath" -ForegroundColor Yellow
            }
        }
    }
    elseif ($Choice -ge 1 -and $Choice -le $Config.Count)
    {
        $Item = $Config[$Choice - 1]
        $FilePath = Join-Path $Folder $Item.filename
        if (Test-Path $FilePath)
        {
            Write-Host "Installing $($Item.app_name)..." -ForegroundColor Cyan
            Start-Process -FilePath $FilePath -Verb RunAs
        }
        else
        {
            Write-Host "File not found for $($Item.app_name): $FilePath" -ForegroundColor Yellow
        }
    }
    else
    {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }
}

# --- Execution ---

$Folder = "$env:TEMP\downloads"
$LogPath = Join-Path $env:TEMP "app-installer.log"
Start-Transcript -Path $LogPath

try
{
    $InvokeDownloadScript = Join-Path $PSScriptRoot "utils\Invoke-Download.ps1"
    if (Test-Path $InvokeDownloadScript)
    {
        . $InvokeDownloadScript
    }
    else
    {
        Write-Host "Critical utility missing: $InvokeDownloadScript" -ForegroundColor Red
        return
    }

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
    
    if ($DownloadOnly)
    {
        Download-Files -Config $ConfigData
    }
    else
    {
        Download-Files -Config $ConfigData
        Install-Files -Config $ConfigData
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
