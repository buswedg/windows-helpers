<#
.SYNOPSIS
Downloads and/or installs essential Nvidia display drivers using PowerShell and 7-Zip.

.DESCRIPTION
This script reads a JSON file containing GPU definitions, then downloads and/or installs the specified GPU driver based on the selected GPU type.
It excludes optional components like GeForce Experience and ShadowPlay. Requires 7-Zip for extraction.

.PARAMETER Mode
Operation mode: 'download-only', 'install-only', or 'download-install'. Default is 'download-only'.

.PARAMETER Folder
Download and extraction directory. Default is $env:TEMP\NVIDIA.

.PARAMETER Json
Name of the JSON file in the 'configs' folder containing GPU information.

.OUTPUTS
Console output and log file saved to %TEMP%\nvidia-driver-manager.log.

.EXAMPLE
PS> .\Nvidia-Driver-Installer.ps1 -Mode download-install -Json "test.json"
Downloads and installs the Nvidia driver for the selected GPU from the JSON file.

.LINK
None
#>

[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [ValidateSet('download-only', 'install-only', 'download-install')]
    [string]$Mode = "download-only",

    [string]$Folder = "$env:TEMP\NVIDIA",

    [string]$Json
)

# Requires
Import-Module BitsTransfer -ErrorAction SilentlyContinue

function Get-ConfigFilePath {
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
        return $path
    }

    $files = Get-ChildItem -Path $configDir -Filter *.json
    if ($files.Count -eq 0) {
        Write-Host "No JSON config files found in: $configDir" -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:" -ForegroundColor Green
    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Host "$($i + 1): $($files[$i].Name)"
    }

    do {
        $sel = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($sel -match '^\d+$') -or [int]$sel -lt 1 -or [int]$sel -gt $files.Count)

    return $files[[int]$sel - 1].FullName
}

function Get-DesiredGpuType {
    param ([string]$ConfigFilePath)

    $gpuInfo = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
    Write-Host "`nAvailable GPU types:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $gpuInfo.Gpus.Count; $i++) {
        Write-Host "$($i + 1). $($gpuInfo.Gpus[$i].tag)"
    }

    do {
        $idx = Read-Host "Enter the number for the GPU type to use"
    } while (-not ($idx -match '^\d+$') -or [int]$idx -lt 1 -or [int]$idx -gt $gpuInfo.Gpus.Count)

    return $gpuInfo.Gpus[[int]$idx - 1]
}

function Get-InstalledDriverVersion {
    try {
        $vc = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" }
        if (-not $vc) { return $null }
        return ($vc.DriverVersion.Split('.')[-2..-1] -join '.')
    } catch {
        Write-Host "Could not detect installed driver." -ForegroundColor Yellow
        return $null
    }
}

function Get-LatestDriverVersion {
    param ($Psid, $Pfid, $Osid)

    $uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php" +
           "?func=DriverManualLookup&psid=$Psid&pfid=$Pfid&osID=$Osid&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1"

    $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing
    return ($resp.Content | ConvertFrom-Json).IDS[0].downloadInfo.Version
}

function Get-7ZipArchiver {
    $path = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\7-Zip' -Name Path -ErrorAction SilentlyContinue).Path
    $exe = Join-Path $path "7z.exe"
    if (-not (Test-Path $exe)) {
        Write-Host "7-Zip not found. Please install it before continuing." -ForegroundColor Red
        pause
        exit
    }
    return $exe
}

function DownloadDriver {
    param (
        $Version, $MachineType, $WinVersion, $Arch, $Dest
    )

    $url = "https://international.download.nvidia.com/Windows/$Version/$Version-$MachineType-$WinVersion-$Arch-international-dch-whql.exe"
    $fallback = $url -replace '\.exe$', '-rp.exe'

    Write-Host "Downloading driver to $Dest" -ForegroundColor Yellow
    Start-BitsTransfer -Source $url -Destination $Dest -ErrorAction SilentlyContinue

    if (-not $? -or -not (Test-Path $Dest)) {
        Write-Host "Primary download failed. Trying fallback..." -ForegroundColor DarkYellow
        Start-BitsTransfer -Source $fallback -Destination $Dest
    }
}

function InstallDriver {
    param ($7zExe, $DriverExe, $ExtractPath)

    Write-Host "Extracting driver..." -ForegroundColor Cyan
    & $7zExe x -bso0 -bsp1 -bse1 -aoa $DriverExe -o"$ExtractPath" | Out-Null

    $cfgPath = Join-Path $ExtractPath "setup.cfg"
    (Get-Content $cfgPath) | Where-Object { $_ -notmatch 'name="\${{(EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile)}}' } | Set-Content $cfgPath

    Write-Host "Installing driver..." -ForegroundColor Cyan
    & "$ExtractPath\setup.exe" -passive -noreboot -noeula -nofinish -clean -s | Out-Null

    Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Installation complete." -ForegroundColor Green
}

function Get-DriverFileName {
    param ($Folder)
    $files = Get-ChildItem -Path $Folder -Filter *.exe
    if ($files.Count -eq 1) {
        return $files[0].Name
    }

    Write-Host "`nAvailable driver executables:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Host "$($i + 1). $($files[$i].Name)"
    }

    do {
        $choice = Read-Host "Select driver file to install"
    } while (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $files.Count)

    return $files[[int]$choice - 1].Name
}

# --- Execution ---
$LogPath = Join-Path $env:TEMP "nvidia-driver-manager.log"
Start-Transcript -Path $LogPath

if ($Mode -in @('download-only', 'download-install')) {
    $configPath = Get-ConfigFilePath
    $gpu = Get-DesiredGpuType -ConfigFilePath $configPath
    $latest = Get-LatestDriverVersion -Psid $gpu.Psid -Pfid $gpu.Pfid -Osid $gpu.Osid
    $installed = Get-InstalledDriverVersion

    Write-Host "`nLatest version: $latest"
    Write-Host "Installed version: $installed"

    if ($latest -eq $installed) {
        $opt = Read-Host "Driver is up-to-date. Download anyway? (Y/N)"
        if ($opt -notin @('Y', 'y')) { exit }
    }

    New-Item -Path $Folder -ItemType Directory -Force | Out-Null
    $driverPath = Join-Path $Folder "$($gpu.tag)_$latest.exe"
    DownloadDriver -Version $latest -MachineType $gpu.machinetype -WinVersion $gpu.winversion -Arch $gpu.winarchitecture -Dest $driverPath
}

if ($Mode -in @('install-only', 'download-install')) {
    $driverFile = Get-DriverFileName -Folder $Folder
    $extractPath = Join-Path $Folder ([System.IO.Path]::GetFileNameWithoutExtension($driverFile))
    $7z = Get-7ZipArchiver
    InstallDriver -7zExe $7z -DriverExe (Join-Path $Folder $driverFile) -ExtractPath $extractPath
}

Stop-Transcript
Write-Host "`nAll operations completed. Log saved to: $LogPath"
