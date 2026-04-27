<#
.SYNOPSIS
Adds a configurable list of folder paths to the Windows Defender exclusions list.

.DESCRIPTION
This script reads a JSON file containing a list of folder paths, and adds them to the Windows Defender exclusion paths. It can optionally clear existing folder exclusions before adding the new ones.

.PARAMETER Config
Name of the JSON file (from the 'configs' directory) that contains the list of paths to exclude.

.PARAMETER ClearExisting
If specified, removes all existing folder exclusions before applying the new ones.

.OUTPUTS
Console output.

.EXAMPLE
PS> .\Reset-Defender-Exclusions.ps1 -Config "default.json" -ClearExisting
#>

[CmdletBinding()]
param (
    [string]$Config,
    [switch]$ClearExisting
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

# --- Main Execution ---

Write-Host "--- Starting Windows Defender Exclusion Setup ---" -ForegroundColor Cyan

try
{
    # 1. Clear all existing Folder exclusions if requested
    if ($ClearExisting) {
        $existingPaths = (Get-MpPreference).ExclusionPath
        if ($existingPaths) {
            Write-Host "`nRemoving $($existingPaths.Count) existing folder exclusions..." -ForegroundColor Yellow
            $existingPaths | ForEach-Object { Remove-MpPreference -ExclusionPath $_ }
        } else {
            Write-Host "`nNo existing folder exclusions found." -ForegroundColor Gray
        }
    } else {
        Write-Host "`nKeeping existing folder exclusions as -ClearExisting was not specified." -ForegroundColor Gray
    }

    if (-not $Config -and $ClearExisting) {
        Write-Host "`nNo config specified, stopping after clearing exclusions." -ForegroundColor Green
    } else {
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

        if (-not $ConfigData.Exclusions -or $ConfigData.Exclusions.Count -eq 0)
        {
            Write-Host "No exclusions found in config file." -ForegroundColor Yellow
        } else {
            # 2. Add the new folders
            Write-Host "`nAdding new exclusions..." -ForegroundColor Green
            foreach ($path in $ConfigData.Exclusions) {
                if (Test-Path $path) {
                    Add-MpPreference -ExclusionPath $path
                    Write-Host " [+] Added: $path"
                } else {
                    Write-Host " [!] Warning: Path not found, still added to list: $path" -ForegroundColor Magenta
                    Add-MpPreference -ExclusionPath $path
                }
            }
        }
    }

    # 3. Final Verification
    Write-Host "`n--- Current Active Exclusions ---" -ForegroundColor Cyan
    (Get-MpPreference).ExclusionPath
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
finally
{
    Write-Host "`nDone!" -ForegroundColor Green
}