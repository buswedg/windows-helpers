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
#>

[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [ValidateSet('download-only', 'install-only', 'download-install')]
    [string]$Mode = "download-only",

    [string]$Folder = "$env:TEMP\NVIDIA",

    [string]$Json
)

#Requires -RunAsAdministrator

Import-Module BitsTransfer -ErrorAction SilentlyContinue

function Get-ConfigFilePath
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
        return $ConfigPath
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
        $Sel = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Sel -match '^\d+$') -or [int]$Sel -lt 1 -or [int]$Sel -gt $ConfigFiles.Count)

    return $ConfigFiles[[int]$Sel - 1].FullName
}

function Get-DesiredGpuType
{
    param (
        $Configs
    )

    Write-Host "`nAvailable GPU types:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Configs.Gpus.Count; $i++) {
        Write-Host "$( $i + 1 ). $( $Configs.Gpus[$i].tag )"
    }

    do
    {
        $Sel = Read-Host "Enter the number of the GPU type to use"
    } while (-not ($Sel -match '^\d+$') -or [int]$Sel -lt 1 -or [int]$Sel -gt $Configs.Gpus.Count)

    return $Configs.Gpus[[int]$Sel - 1]
}

function GetDesiredDriverVersion
{
    param (
        $Versions
    )

    Write-Host "`nAvailable driver versions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Versions.Count; $i++) {
        Write-Host "$( $i + 1 ). Version $( $Versions[$i].downloadInfo.Version ) - Released $( $Versions[$i].downloadInfo.DownloadDate )"
    }

    do
    {
        $Sel = Read-Host "Enter the number of the driver version to download"
    } while (-not ($Sel -match '^\d+$') -or [int]$Sel -lt 1 -or [int]$Sel -gt $Versions.Count)

    return $Versions[[int]$Sel - 1].downloadInfo.Version
}

function Get-InstalledDriverVersion
{
    try
    {
        $v = (Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.Manufacturer -like "*NVIDIA*" -and $_.DeviceName -like "*NVIDIA*" } | Select-Object -First 1).DriverVersion
        $p = $v -split '\.'
        return "$( $p[2][-1] )$($p[3].Substring(0, 2) ).$($p[3].Substring($p[3].Length - 2, 2) )"
    }
    catch
    {
        Write-Host "Could not detect installed driver." -ForegroundColor Yellow
        return $null
    }
}

function Get-AvailableDriverVersions
{
    param (
        $GpuType,
        $Count = 5
    )

    $Uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php" +
            "?func=DriverManualLookup" +
            "&psid=$( $GpuType.psid )" +
            "&pfid=$( $GpuType.pfid )" +
            "&osID=$( $GpuType.osid )" +
            "&languageCode=1033" +
            "&isWHQL=1" +
            "&dch=1" +
            "&sort1=0" +
            "&numberOfResults=$Count"

    $Resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing
    return ($Resp.Content | ConvertFrom-Json).IDS
}

function Get-7ZipArchiver
{
    $7zPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\7-Zip' -Name Path -ErrorAction SilentlyContinue).Path
    $7zExe = Join-Path $7zPath "7z.exe"
    if (-not (Test-Path $7zExe))
    {
        Write-Host "7-Zip not found. Please install it before continuing." -ForegroundColor Red
        pause
        exit
    }

    return $7zExe
}

function DownloadDriver
{
    param (
        $Version,
        $MachineType,
        $WinVersion,
        $Arch,
        $Dest
    )

    $DownloadUrl = "https://international.download.nvidia.com/Windows/$Version/$Version" +
            "-$MachineType" +
            "-$WinVersion" +
            "-$Arch" +
            "-international" +
            "-dch" +
            "-whql.exe"

    $FallbackUrl = $DownloadUrl -replace '\.exe$', '-rp.exe'

    New-Item -Path $Folder -ItemType Directory -Force | Out-Null

    Write-Host "Downloading driver to $Dest" -ForegroundColor Yellow
    Start-BitsTransfer -Source $DownloadUrl -Destination $Dest -ErrorAction SilentlyContinue

    if (-not $? -or -not (Test-Path $Dest))
    {
        Write-Host "Primary download failed. Trying fallback..." -ForegroundColor DarkYellow
        Start-BitsTransfer -Source $FallbackUrl -Destination $Dest
    }
}

function InstallDriver
{
    param (
        $DriverExe,
        $ExtractPath
    )

    $7zExe = Get-7ZipArchiver

    Write-Host "Extracting driver..." -ForegroundColor Cyan
    & $7zExe x -bso0 -bsp1 -bse1 -aoa $DriverExe -o"$ExtractPath" | Out-Null

    $CfgPath = Join-Path $ExtractPath "setup.cfg"
    (Get-Content $CfgPath) | Where-Object { $_ -notmatch 'name="\${{(EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile)}}' } | Set-Content $CfgPath

    Write-Host "Installing driver..." -ForegroundColor Cyan
    & "$ExtractPath\setup.exe" -passive -noreboot -noeula -nofinish -clean -s | Out-Null

    Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Installation complete." -ForegroundColor Green
}

function Get-DriverFileName
{
    param (
        $DriverDir
    )

    $DriverFiles = Get-ChildItem -Path $DriverDir -Filter *.exe
    if ($DriverFiles.Count -eq 1)
    {
        return $DriverFiles[0].Name
    }

    Write-Host "`nAvailable driver executables:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $DriverFiles.Count; $i++) {
        Write-Host "$( $i + 1 ). $( $DriverFiles[$i].Name )"
    }

    do
    {
        $Sel = Read-Host "Select driver file to install"
    } while (-not ($Sel -match '^\d+$') -or [int]$Sel -lt 1 -or [int]$Sel -gt $DriverFiles.Count)

    return $DriverFiles[[int]$Sel - 1].Name
}

# --- Execution ---
$LogPath = Join-Path $env:TEMP "nvidia-driver-manager.log"
Start-Transcript -Path $LogPath

if ($Mode -in @('download-only', 'download-install'))
{
    $ConfigPath = Get-ConfigFilePath
    $Configs = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    $DesiredGpuType = Get-DesiredGpuType -Configs $Configs
    $AvailableVersions = Get-AvailableDriverVersions -GpuType $DesiredGpuType -Count 5
    $DesiredVersion = GetDesiredDriverVersion -Versions $AvailableVersions
    $InstalledVersion = Get-InstalledDriverVersion

    Write-Host "`nDesired version: $DesiredVersion"
    Write-Host "Installed version: $InstalledVersion"

    if ($DesiredVersion -eq $InstalledVersion)
    {
        $Opt = Read-Host "Installed driver already matches desired version. Download anyway? (Y/N)"
        if ($Opt -notin @('Y', 'y'))
        {
            exit
        }
    }

    $DriverPath = Join-Path $Folder "$( $DesiredGpuType.tag )_$DesiredVersion.exe"
    DownloadDriver -Version $DesiredVersion -MachineType $DesiredGpuType.machinetype -WinVersion $DesiredGpuType.winversion -Arch $DesiredGpuType.winarchitecture -Dest $DriverPath
}

if ($Mode -in @('install-only', 'download-install'))
{
    $DriverFile = Get-DriverFileName -DriverDir $Folder
    $ExtractPath = Join-Path $Folder ([System.IO.Path]::GetFileNameWithoutExtension($DriverFile))
    InstallDriver -DriverExe (Join-Path $Folder $DriverFile) -ExtractPath $ExtractPath
}

Stop-Transcript
Write-Host "`nAll operations completed."
Start-Sleep -Seconds 5
exit
