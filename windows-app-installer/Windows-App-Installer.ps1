<#
.SYNOPSIS
Downloads and/or installs applications using PowerShell.

.DESCRIPTION
This script reads a JSON file containing application definitions, then downloads and/or installs the specified applications based on the selected mode.

.PARAMETER Mode
Operation mode: 'download-only', 'install-only', or 'download-install'. Default is 'download-only'.

.PARAMETER Json
Name of the JSON file (located in the 'configs' folder) that defines the applications to process.

.OUTPUTS
Console output and log file saved to %TEMP%\windows-app-installer.log.

.EXAMPLE
PS> .\Windows-App-Installer.ps1 -Mode download-install -Json "test.json"
Downloads and installs applications defined in test.json.
#>

[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [ValidateSet("download-only", "install-only", "download-install")]
    [string]$Mode = "download-only",

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

function Download-Files {
    Write-Host "`nAvailable download options:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigData.Count; $i++) {
        Write-Host "$($i + 1)) $($ConfigData[$i].app_name)"
    }
    Write-Host "$($ConfigData.Count + 1)) Download All"

    $choice = Read-Host "`nEnter the number of the download option to perform"
    $choice = [int]$choice

    if ($choice -eq $ConfigData.Count + 1) {
        foreach ($item in $ConfigData) {
            Write-Host "Downloading $($item.app_name)..."
            $downloaded = Invoke-Download -URL $item.download_url -Destination $DownloadsDir
            $item.filename = [System.IO.Path]::GetFileName($downloaded)
        }
    } elseif ($choice -ge 1 -and $choice -le $ConfigData.Count) {
        $item = $ConfigData[$choice - 1]
        Write-Host "Downloading $($item.app_name)..."
        $downloaded = Invoke-Download -URL $item.download_url -Destination $DownloadsDir
        $item.filename = [System.IO.Path]::GetFileName($downloaded)
    } else {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }
}

function Install-Files {
    Write-Host "`nInstall Options:`n"
    for ($i = 0; $i -lt $ConfigData.Count; $i++) {
        Write-Host "$($i + 1)) Install $($ConfigData[$i].app_name)"
    }
    Write-Host "$($ConfigData.Count + 1)) Install All"

    $choice = Read-Host "`nEnter the index of the install to perform"
    $choice = [int]$choice

    if ($choice -eq $ConfigData.Count + 1) {
        foreach ($item in $ConfigData) {
            Write-Host "Installing $($item.app_name)..."
            Start-Process -FilePath (Join-Path $DownloadsDir $item.filename) -Verb RunAs
        }
    } elseif ($choice -ge 1 -and $choice -le $ConfigData.Count) {
        $item = $ConfigData[$choice - 1]
        Write-Host "Installing $($item.app_name)..."
        Start-Process -FilePath (Join-Path $DownloadsDir $item.filename) -Verb RunAs
    } else {
        Write-Host "Invalid selection." -ForegroundColor Yellow
    }
}

$invokeDownloadScript = Join-Path $PSScriptRoot "utils\Invoke-Download.ps1"
. $invokeDownloadScript

# --- Execution ---
$LogPath = Join-Path $env:TEMP "windows-app-installer.log"
Start-Transcript -Path $LogPath

$DownloadsDir = Join-Path $PSScriptRoot "downloads"
if (-not (Test-Path $DownloadsDir)) {
    New-Item -Path $DownloadsDir -ItemType Directory | Out-Null
}

$ConfigData = Get-ConfigData

# Run based on mode
switch ($Mode) {
    "download-only"     { Download-Files }
    "install-only"      { Install-Files }
    "download-install"  { Download-Files; Install-Files }
    default             { Write-Host "Invalid mode: $Mode" -ForegroundColor Red }
}

Stop-Transcript
Write-Host "`nAll operations completed. Log saved to: $LogPath"
Write-Host "`nExiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
