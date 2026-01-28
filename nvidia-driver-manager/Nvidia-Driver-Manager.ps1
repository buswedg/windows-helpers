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
Name of the JSON file (from the 'configs' directory) that contains the GPU information.

.OUTPUTS
Console output and log file saved to %TEMP%\nvidia-driver-manager.log.

.EXAMPLE
PS> .\Nvidia-Driver-Manager.ps1 -Mode download-install -Json "config.json"
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

function Get-SevenZipPath
{
    $Paths = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )

    foreach ($Path in $Paths)
    {
        if (Test-Path $Path)
        {
            return $Path
        }
    }
    return $null
}

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "nvidia-driver-manager.log"
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

    if ($null -eq $ConfigData.GPUs -or $ConfigData.GPUs.Count -eq 0)
    {
        Write-Host "No GPU definitions found in JSON." -ForegroundColor Red
        return
    }

    # Select GPU
    Write-Host "`nSelect GPU type to process:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigData.GPUs.Count; $i++)
    {
        Write-Host ("{0}: {1}" -f ($i + 1), $ConfigData.GPUs[$i].display_name)
    }

    do
    {
        $GpuSelection = Read-Host "`nEnter the number for the GPU type"
    } while (-not ($GpuSelection -match '^\d+$') -or [int]$GpuSelection -lt 1 -or [int]$GpuSelection -gt $ConfigData.GPUs.Count)

    $SelectedGpu = $ConfigData.GPUs[[int]$GpuSelection - 1]
    $DownloadUrl = $SelectedGpu.download_url
    $DriverFileName = [System.IO.Path]::GetFileName($DownloadUrl)
    $TargetFile = Join-Path $Folder $DriverFileName

    if ($Mode -match 'download')
    {
        if (-not (Test-Path $Folder))
        {
            New-Item -Path $Folder -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $TargetFile)
        {
            Write-Host "Driver file already exists: $DriverFileName. Skipping download." -ForegroundColor Cyan
        }
        else
        {
            Write-Host "Downloading Driver: $DriverFileName..." -ForegroundColor Cyan
            Start-BitsTransfer -Source $DownloadUrl -Destination $TargetFile
        }
    }

    if ($Mode -match 'install')
    {
        if (-not (Test-Path $TargetFile))
        {
            Write-Host "Driver file not found for installation: $TargetFile" -ForegroundColor Red
            return
        }

        $SevenZipPath = Get-SevenZipPath
        if ($null -eq $SevenZipPath)
        {
            Write-Host "7-Zip not found. Extraction required for minimal installation." -ForegroundColor Red
            return
        }

        $ExtractPath = Join-Path $Folder "Extracted"
        if (Test-Path $ExtractPath)
        {
            Remove-Item $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null

        Write-Host "Extracting driver to $ExtractPath..." -ForegroundColor Cyan
        & $SevenZipPath x "$TargetFile" "-o$ExtractPath" -y | Out-Null

        Write-Host "Starting Minimal Nvidia Driver Installation..." -ForegroundColor Green
        # DisplayDriver = Base Driver, NVI2 = Installer Framework, PhysX = PhysX support
        # setup.exe -s = silent mode
        $SetupPath = Join-Path $ExtractPath "setup.exe"
        if (Test-Path $SetupPath)
        {
            Start-Process -FilePath $SetupPath -ArgumentList "-s", "-n", "-f", "DisplayDriver", "NVI2", "PhysX" -Wait -Verb RunAs
            Write-Host "Operation completed." -ForegroundColor Green
        }
        else
        {
            Write-Host "Setup.exe not found in extracted folder." -ForegroundColor Red
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
