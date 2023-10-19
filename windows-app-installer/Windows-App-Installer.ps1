<#
.SYNOPSIS

Downloads and/or installs applications using PowerShell.

.DESCRIPTION

Downloads and/or installs all applications in the specified JSON file using Powershell.

.PARAMETER Mode
Specifies the mode of operation ('download-only', 'install-only', or 'download-install', default: 'download-only').

.PARAMETER Json
Name of the JSON file (without path) containing the installation information.

.OUTPUTS

Screen output and TransAction log which is available in %Temp%\windows-app-installer.log.

.EXAMPLE

PS> .\Windows-App-Installer.ps1 -Mode "download-only" -Json "test.json"
Downloads all applications in test.json.

.LINK

None

#>

[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [ValidateSet("download-only", "install-only", "download-install")]
    [string]$Mode = "download-only",
    [Parameter(Mandatory = $true, HelpMessage = "Name of the JSON file (without path) containing installation information")]
    [string]$Json
)

#Requires -RunAsAdministrator

Start-Transcript -Path $ENV:TEMP\windows-app-installer.log

$InvokeDownloadsScriptPath = Join-Path $PSScriptRoot "utils\Invoke-Download.ps1"
. "$InvokeDownloadsScriptPath"

Function Get-MD5Hash {
    param (
        [string]$filePath
    )

    $md5Hash = Get-FileHash -Path $filePath -Algorithm MD5 | Select-Object -ExpandProperty Hash

    return $md5Hash
}

Function Get-FileVersion {
    param (
        [string]$filePath
    )

    $fileVersion = (Get-Item $filePath).VersionInfo.FileVersion

    if (-not $fileVersion) {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        $fileVersion = $fileName -replace "[^\d.]"
    }

    if (-not $fileVersion) {
        $fileVersion = "NA"
    }

    return $fileVersion
}

Function Download-Files {
    $index = 1

    Write-Host "Download Options:"
    foreach ($download in $JsonData) {
        Write-Host "$index) $($download.app_name)"
        $index++
    }

    Write-Host "$index) Download All"

    $userChoice = Read-Host "Enter the index of the download you want or '$index' to download all"

    $userChoice = [int]$userChoice
    if ($userChoice -ge 1 -and $userChoice -lt $index) {
        if ($userChoice -eq $index) {
            foreach ($download in $JsonData) {
                Write-Host "Downloading $($download.app_name)..."
                $downloadedFilePath = Invoke-Download -URL $download.download_url -Destination $DownloadsPath
                $download.filename = [System.IO.Path]::GetFileName($downloadedFilePath)
                $download.version = (Get-FileVersion -filePath $downloadedFilePath)
                $JsonData | ConvertTo-Json | Set-Content -Path $JsonFilePath
            }
        } else {
            $selectedDownload = $JsonData[$userChoice - 1]
            Write-Host "Downloading $($selectedDownload.app_name)..."
            $downloadedFilePath = Invoke-Download -URL $selectedDownload.download_url -Destination $DownloadsPath
            $selectedDownload.filename = [System.IO.Path]::GetFileName($downloadedFilePath)
            $selectedDownload.version = (Get-FileVersion -filePath $downloadedFilePath)
            $JsonData | ConvertTo-Json | Set-Content -Path $JsonFilePath
        }
    } else {
        Write-Host "Invalid choice. Aborting download."
    }
}

Function Install-Files {
    $index = 1

    Write-Host "Install Options:"
    foreach ($download in $JsonData) {
        $app_name = $download.app_name
        Write-Host "$index) Install $app_name"
        $index++
    }

    Write-Host "$index) Install All"

    $userChoice = Read-Host "Enter the index of the app you want to install or '$index' to install all:"

    if ($userChoice -eq $index) {
        foreach ($download in $JsonData) {
            Write-Host "Installing $($download.app_name)..."
            Start-Process -FilePath (Join-Path -Path $DownloadsPath -ChildPath $download.filename) -Verb RunAs
        }
    } elseif ($userChoice -ge 1 -and $userChoice -lt $index) {
        $selectedInstall = $JsonData[$userChoice - 1]
        Write-Host "Installing $($selectedInstall.app_name)..."
        Start-Process -FilePath (Join-Path -Path $DownloadsPath -ChildPath $selectedInstall.filename) -Verb RunAs
    } else {
        Write-Host "Invalid choice. Aborting installation."
    }
}

$DownloadsPath = Join-Path $PSScriptRoot "downloads"
if (-not (Test-Path -Path $DownloadsPath)) {
    New-Item -Path $DownloadsPath -ItemType Directory | Out-Null
}

$JsonFilePath = Join-Path $PSScriptRoot "configs\$Json"

if (-not (Test-Path $JsonFilePath)) {
    Write-Host "The specified JSON file does not exist: $JsonFilePath" -ForegroundColor Red
    exit 1
}

$JsonData = Get-Content $JsonFilePath -Raw | ConvertFrom-Json

if (-not $Mode) {
    $Mode = Read-Host "Select mode: 1) download-only, 2) install-only, 3) download-install"
}

if ($Mode -eq "1" -or $Mode -eq "download-only") {
    Download-Files
} elseif ($Mode -eq "2" -or $Mode -eq "install-only") {
    Install-Files
} elseif ($Mode -eq "3" -or $Mode -eq "download-install") {
    Download-Files
    Install-Files
} else {
    Write-Host "Invalid mode selected."
}

Stop-Transcript

Write-Host "All operations completed."
Write-Host "Exiting script in 5 seconds."; Start-Sleep -Seconds 5
exit
