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
    $ConfigDir = Join-Path $PSScriptRoot "configs"
    if (-not (Test-Path $ConfigDir)) {
        Write-Host "Config directory not found: $ConfigDir" -ForegroundColor Red
        exit 1
    }

    if ($Json) {
        $ConfigPath = Join-Path $ConfigDir $Json
        if (-not (Test-Path $ConfigPath)) {
            Write-Host "Specified JSON config file does not exist: $ConfigPath" -ForegroundColor Red
            exit 1
        }
        return $ConfigPath
    }

    $ConfigFiles = Get-ChildItem -Path $ConfigDir -Filter *.json
    if ($ConfigFiles.Count -eq 0) {
        Write-Host "No JSON config files found in '$ConfigDir'." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++) {
        Write-Host "$($i + 1): $($ConfigFiles[$i].Name)"
    }

    do {
        $Sel = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Sel -match '^\d+$') -or [int]$Sel -lt 1 -or [int]$Sel -gt $ConfigFiles.Count)

    return $ConfigFiles[[int]$Sel - 1].FullName
}

function Get-DesiredGpuType {
    param ([string]$ConfigFilePath)

    $GpuInfo = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
    Write-Host "`nAvailable GPU types:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $GpuInfo.Gpus.Count; $i++) {
        Write-Host "$($i + 1). $($GpuInfo.Gpus[$i].tag)"
    }

    do {
        $Idx = Read-Host "Enter the number for the GPU type to use"
    } while (-not ($Idx -match '^\d+$') -or [int]$Idx -lt 1 -or [int]$Idx -gt $GpuInfo.Gpus.Count)

    return $GpuInfo.Gpus[[int]$Idx - 1]
}

function Get-InstalledDriverVersion {
    try {
        $Vc = Get-WmiObject -Class Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" }
        if (-not $Vc) { return $null }
        return ($Vc.DriverVersion.Split('.')[-2..-1] -join '.')
    } catch {
        Write-Host "Could not detect installed driver." -ForegroundColor Yellow
        return $null
    }
}

function Get-LatestDriverVersion {
    param (
        $Psid, $Pfid, $Osid
    )

    $Uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php" +
           "?func=DriverManualLookup" +
           "&psid=$Psid" +
           "&pfid=$Pfid" +
           "&osID=$Osid" +
           "&languageCode=1033" +
           "&isWHQL=1" +
           "&dch=1" +
           "&sort1=0" +
           "&numberOfResults=1"

    $Resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing
    return ($Resp.Content | ConvertFrom-Json).IDS[0].downloadInfo.Version
}

function Get-7ZipArchiver {
    $Path = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\7-Zip' -Name Path -ErrorAction SilentlyContinue).Path
    $Exe = Join-Path $Path "7z.exe"
    if (-not (Test-Path $Exe)) {
        Write-Host "7-Zip not found. Please install it before continuing." -ForegroundColor Red
        pause
        exit
    }
    return $Exe
}

function DownloadDriver {
    param (
        $Version, $MachineType, $WinVersion, $Arch, $Dest
    )

    $Url = "https://international.download.nvidia.com/Windows/$Version/$Version-$MachineType-$WinVersion-$Arch-international-dch-whql.exe"
    $Fallback = $Url -replace '\.exe$', '-rp.exe'

    Write-Host "Downloading driver to $Dest" -ForegroundColor Yellow
    Start-BitsTransfer -Source $Url -Destination $Dest -ErrorAction SilentlyContinue

    if (-not $? -or -not (Test-Path $Dest)) {
        Write-Host "Primary download failed. Trying fallback..." -ForegroundColor DarkYellow
        Start-BitsTransfer -Source $Fallback -Destination $Dest
    }
}

function InstallDriver {
    param ($7zExe, $DriverExe, $ExtractPath)

    Write-Host "Extracting driver..." -ForegroundColor Cyan
    & $7zExe x -bso0 -bsp1 -bse1 -aoa $DriverExe -o"$ExtractPath" | Out-Null

    $CfgPath = Join-Path $ExtractPath "setup.cfg"
    (Get-Content $CfgPath) | Where-Object { $_ -notmatch 'name="\${{(EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile)}}' } | Set-Content $CfgPath

    Write-Host "Installing driver..." -ForegroundColor Cyan
    & "$ExtractPath\setup.exe" -passive -noreboot -noeula -nofinish -clean -s | Out-Null

    Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Installation complete." -ForegroundColor Green
}

function Get-DriverFileName {
    param ($DriverDir)

    $Files = Get-ChildItem -Path $DriverDir -Filter *.exe
    if ($Files.Count -eq 1) {
        return $Files[0].Name
    }

    Write-Host "`nAvailable driver executables:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Files.Count; $i++) {
        Write-Host "$($i + 1). $($Files[$i].Name)"
    }

    do {
        $Choice = Read-Host "Select driver file to install"
    } while (-not ($Choice -match '^\d+$') -or [int]$Choice -lt 1 -or [int]$Choice -gt $Files.Count)

    return $Files[[int]$Choice - 1].Name
}

# --- Execution ---
$LogPath = Join-Path $env:TEMP "nvidia-driver-manager.log"
Start-Transcript -Path $LogPath

if ($Mode -in @('download-only', 'download-install')) {
    $ConfigPath = Get-ConfigFilePath

    $Gpu = Get-DesiredGpuType -ConfigFilePath $ConfigPath
    $Latest = Get-LatestDriverVersion -Psid $Gpu.Psid -Pfid $Gpu.Pfid -Osid $Gpu.Osid
    $Installed = Get-InstalledDriverVersion

    Write-Host "`nLatest version: $Latest"
    Write-Host "Installed version: $Installed"

    if ($Latest -eq $Installed) {
        $Opt = Read-Host "Driver is up-to-date. Download anyway? (Y/N)"
        if ($Opt -notin @('Y', 'y')) { exit }
    }

    New-Item -Path $Folder -ItemType Directory -Force | Out-Null

    $DriverPath = Join-Path $Folder "$($Gpu.tag)_$Latest.exe"
    DownloadDriver -Version $Latest -MachineType $Gpu.machinetype -WinVersion $Gpu.winversion -Arch $Gpu.winarchitecture -Dest $DriverPath
}

if ($Mode -in @('install-only', 'download-install')) {
    $DriverFile = Get-DriverFileName -DriverDir $Folder
    $ExtractPath = Join-Path $Folder ([System.IO.Path]::GetFileNameWithoutExtension($DriverFile))
    $7z = Get-7ZipArchiver
    InstallDriver -7zExe $7z -DriverExe (Join-Path $Folder $DriverFile) -ExtractPath $ExtractPath
}

Stop-Transcript
Write-Host "`nAll operations completed."
Start-Sleep -Seconds 5
exit
