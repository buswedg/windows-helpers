<#
.SYNOPSIS
Downloads and/or installs a configurable list of applications using PowerShell.

.DESCRIPTION
This script reads a JSON file containing application definitions, then downloads and/or installs the specified applications based on the selected mode.

.PARAMETER Mode
Operation mode: 'download-only', 'install-only', or 'download-install'. Default is 'download-only'.

.PARAMETER Folder
Download and extraction directory. Default is $env:TEMP\downloads.

.PARAMETER Json
Name of the JSON file (located in the 'configs' folder) that defines the applications to process.

.OUTPUTS
Console output and log file saved to %TEMP%\windows-app-installer.log.

.EXAMPLE
PS> .\Windows-App-Installer.ps1 -Mode download-install -Json "test.json"
#>

[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [ValidateSet("download-only", "install-only", "download-install")]
    [string]$Mode = "download-only",

    [string]$Folder = "$env:TEMP\downloads",

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

function Download-Files
{
    param ($Config)

    New-Item -Path $Folder -ItemType Directory | Out-Null

    Write-Host "`nAvailable download options:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $Config.Count; $i++) {
        Write-Host "$( $i + 1 )) $( $Config[$i].app_name )"
    }
    Write-Host "$( $Config.Count + 1 )) Download All"

    $Choice = Read-Host "`nEnter the number of the download option to perform"
    $Choice = [int]$Choice

    if ($Choice -eq $Config.Count + 1)
    {
        foreach ($Item in $Config)
        {
            Write-Host "Downloading $( $Item.app_name )..."
            $Downloaded = Invoke-Download -URL $Item.download_url -Destination $Folder
            $Item.filename = [System.IO.Path]::GetFileName($Downloaded)
        }
    }
    elseif ($Choice -ge 1 -and $Choice -le $Config.Count)
    {
        $Item = $Config[$Choice - 1]
        Write-Host "Downloading $( $Item.app_name )..."
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

    Write-Host "`nAvailable install options:`n"
    for ($i = 0; $i -lt $Config.Count; $i++) {
        Write-Host "$( $i + 1 )) Install $( $Config[$i].app_name )"
    }
    Write-Host "$( $Config.Count + 1 )) Install All"

    $Choice = Read-Host "`nEnter the number of the install option to perform"
    $Choice = [int]$Choice

    if ($Choice -eq $Config.Count + 1)
    {
        foreach ($Item in $Config)
        {
            Write-Host "Installing $( $Item.app_name )..."
            Start-Process -FilePath (Join-Path $Folder $Item.filename) -Verb RunAs
        }
    }
    elseif ($Choice -ge 1 -and $Choice -le $Config.Count)
    {
        $Item = $Config[$Choice - 1]
        Write-Host "Installing $( $Item.app_name )..."
        Start-Process -FilePath (Join-Path $Folder $Item.filename) -Verb RunAs
    }
    else
    {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }
}

$InvokeDownloadScript = Join-Path $PSScriptRoot "utils\Invoke-Download.ps1"
. $InvokeDownloadScript

# --- Execution ---
$LogPath = Join-Path $env:TEMP "windows-app-installer.log"
Start-Transcript -Path $LogPath

$ConfigData = Get-ConfigData

switch ($Mode)
{
    "download-only"     {
        Download-Files -Config $ConfigData
    }
    "install-only"      {
        Install-Files -Config $ConfigData
    }
    "download-install"  {
        Download-Files -Config $ConfigData; Install-Files -Config $ConfigData
    }
    default             {
        Write-Host "Invalid mode: $Mode" -ForegroundColor Red
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Exiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
