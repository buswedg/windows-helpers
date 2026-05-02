<#
.SYNOPSIS
Standardized Backup Manager for the windows-helpers suite.

.DESCRIPTION
This script reads a JSON config file and uses 7-Zip to archive multiple source directories 
into a timestamped backup file. Supports exclusion patterns and robust path validation.

.PARAMETER Config
Name of the JSON file (from the 'configs' directory) containing backup sources and destinations.

.OUTPUTS
Console output and log file saved to %TEMP%\backup-manager.log.

.EXAMPLE
PS> .\Backup-Manager.ps1 -Config "my-config.json"
#>

[CmdletBinding()]
param (
    [string]$Config
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
            if (Test-Path $Config) { return $Config }
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

function Get-7ZipArchiver
{
    $7zPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\7-Zip' -Name Path -ErrorAction SilentlyContinue).Path
    if ([string]::IsNullOrWhiteSpace($7zPath))
    {
        Write-Host "7-Zip registry key not found. Checking common paths..." -ForegroundColor Yellow
        $7zPath = "C:\Program Files\7-Zip"
    }
    
    $7zExe = Join-Path $7zPath "7z.exe"
    if (-not (Test-Path $7zExe))
    {
        Write-Host "7-Zip (7z.exe) not found at '$7zExe'. Please install it." -ForegroundColor Red
        exit 1
    }
    return $7zExe
}

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "backup-manager.log"
Start-Transcript -Path $LogPath

try
{
    $ConfigPath = Get-ConfigPath
    
    Write-Host "`nLoading config: $ConfigPath" -ForegroundColor Cyan
    try
    {
        $ConfigData = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch
    {
        Write-Host "Failed to parse JSON config: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Validation
    if ([string]::IsNullOrWhiteSpace($ConfigData.BackupDir))
    {
        Write-Host "BackupDir is missing or empty in configuration." -ForegroundColor Red
        return
    }

    if ($null -eq $ConfigData.Sources -or $ConfigData.Sources.Count -eq 0)
    {
        Write-Host "No Sources defined in configuration." -ForegroundColor Yellow
        return
    }

    # Setup Backup Directory
    $BackupDir = $ConfigData.BackupDir
    if (-not (Test-Path $BackupDir))
    {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Write-Host "Created backup directory: $BackupDir" -ForegroundColor Yellow
    }

    # Prepare 7-Zip Command
    $ArchiverPath = Get-7ZipArchiver
    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $archiveName = "backup_$timestamp.7z"
    $backupFilePath = Join-Path $BackupDir $archiveName

    # Construct Arguments Array
    # a: Add to archive
    # -mx=9: Ultra compression
    # -ssw: Compress files open for writing
    $sevenZipArguments = @("a", "-mx=9", "-ssw")

    # Handle Smart Exclusions
    if ($null -ne $ConfigData.Excludes)
    {
        foreach ($pattern in $ConfigData.Excludes)
        {
            if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
            
            $cleanPattern = $pattern
            $recursive = $true
            
            # Smart Logic: Leading / means root-only (non-recursive)
            if ($pattern.StartsWith("/") -or $pattern.StartsWith("\"))
            {
                $recursive = $false
                $cleanPattern = $pattern.Substring(1)
            }
            
            # Smart Logic: Trailing / means directory
            if ($cleanPattern.EndsWith("/") -or $cleanPattern.EndsWith("\"))
            {
                $cleanPattern = $cleanPattern.TrimEnd("/", "\")
            }

            $flag = if ($recursive) { "-xr!" } else { "-x!" }
            $sevenZipArguments += "$flag$cleanPattern"
        }
    }

    # Handle Exclude File
    if ($null -ne $ConfigData.ExcludeFile)
    {
        $ExcludeFilePath = $ConfigData.ExcludeFile
        if (-not (Test-Path $ExcludeFilePath))
        {
            $LocalExcludeFile = Join-Path $PSScriptRoot $ExcludeFilePath
            if (Test-Path $LocalExcludeFile) { $ExcludeFilePath = $LocalExcludeFile }
        }

        if (Test-Path $ExcludeFilePath)
        {
            $sevenZipArguments += "-xr@$ExcludeFilePath"
        }
        else
        {
            Write-Host "ExcludeFile not found: $ExcludeFilePath" -ForegroundColor Yellow
        }
    }

    # Add Destination
    $sevenZipArguments += $backupFilePath

    # Add Sources
    $validSourceCount = 0
    foreach ($path in $ConfigData.Sources)
    {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path))
        {
            $sevenZipArguments += $path
            $validSourceCount++
        }
        else
        {
            Write-Host "Source '$path' not found or invalid. Skipping." -ForegroundColor Yellow
        }
    }

    if ($validSourceCount -eq 0)
    {
        Write-Host "No valid source paths found to backup." -ForegroundColor Red
        return
    }

    # Execution
    Write-Host "`nStarting backup to: $backupFilePath" -ForegroundColor Green
    Write-Host "Sources: $($validSourceCount) folders detected." -ForegroundColor Gray
    
    $process = Start-Process -FilePath $ArchiverPath -ArgumentList $sevenZipArguments -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0)
    {
        Write-Host "`nBackup completed successfully!" -ForegroundColor Green
    }
    elseif ($process.ExitCode -eq 1)
    {
        Write-Host "`nBackup completed with warnings (some files might have been skipped)." -ForegroundColor Yellow
    }
    else
    {
        Write-Host "`n7-Zip failed with exit code $($process.ExitCode)" -ForegroundColor Red
    }
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
finally
{
    Stop-Transcript
    Write-Host "`nExiting in 5 seconds..."
    Start-Sleep -Seconds 5
}
