<#
.SYNOPSIS
Main entry point for the background scheduler.

.DESCRIPTION
Coordinates theme selection and background application.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that contains the theme library and schedule.

.OUTPUTS
Console output and log file saved to %TEMP%\background-scheduler.log.

.EXAMPLE
PS> .\Background-Scheduler.ps1 -Json "default.json"
#>

[CmdletBinding()]
param (
    [string]$Json
)

# --- Configuration ---
$LogPath = Join-Path $env:TEMP "background-scheduler.log"
$ApplierPath = Join-Path $PSScriptRoot "Set-Background.ps1"

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

function Resolve-PathRobust
{
    param ([string]$Target, [string]$Dir)
    if ([System.IO.Path]::IsPathRooted($Target)) { return $Target }
    return [System.IO.Path]::GetFullPath((Join-Path $Dir $Target))
}

# --- Main Execution ---

Start-Transcript -Path $LogPath -Append

try
{
    Write-Host "`n--- Background Scheduler Run: $(Get-Date) ---" -ForegroundColor Gray
    
    # 1. Resolve Config
    $ConfigPath = Get-ConfigPath
    $ConfigDir = Split-Path $ConfigPath -Parent
    
    try
    {
        $Data = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch
    {
        Write-Host "Failed to parse JSON: $ConfigPath" -ForegroundColor Red
        return
    }

    if ($null -eq $Data.triggers)
    {
        Write-Host "Error: No 'triggers' library found in config." -ForegroundColor Red
        return
    }

    # 2. Determine Theme
    $DayFull = (Get-Date).DayOfWeek.ToString()
    $DayShort = $DayFull.Substring(0, 3)
    $ThemeName = $null

    # Check Schedule
    $Schedule = $Data.schedule
    if ($Schedule)
    {
        if ($Schedule.$DayFull)
        {
            $ThemeName = $Schedule.$DayFull
        }
        elseif ($Schedule.$DayShort)
        {
            $ThemeName = $Schedule.$DayShort
        }
    }

    # Randomize if missing
    $Library = $Data.triggers
    if ($null -eq $ThemeName)
    {
        $LibraryThemes = $Library.psobject.Properties.Name
        
        # Create a Seed from Today's date (YYYYMMDD) ensuring consistency across the entire day
        $Seed = [int](Get-Date -Format "yyyyMMdd")
        $ThemeName = $LibraryThemes | Get-Random -SetSeed $Seed
        
        Write-Host "Day: $DayFull (Unmapped) -> Randomly chosen theme (Deterministic): $ThemeName" -ForegroundColor Cyan
    }
    else
    {
        Write-Host "Day: $DayFull -> Scheduled theme: $ThemeName" -ForegroundColor Cyan
    }

    # 3. Resolve Theme Triggers Path
    $ThemePath = $Library.$ThemeName
    if ($null -eq $ThemePath)
    {
        Write-Host "Error: Theme '$ThemeName' not found in library." -ForegroundColor Red
        return
    }

    $TriggersPath = Resolve-PathRobust -Target $ThemePath -Dir $ConfigDir
    if (-not (Test-Path $TriggersPath))
    {
        Write-Host "Error: Triggers file not found: $TriggersPath" -ForegroundColor Red
        return
    }

    # 4. Call Applier
    if (-not (Test-Path $ApplierPath))
    {
        Write-Host "Error: Applier script not found: $ApplierPath" -ForegroundColor Red
        return
    }

    Write-Host "Applying background triggers from: $TriggersPath" -ForegroundColor Cyan
    & $ApplierPath -Json $TriggersPath
    
    Write-Host "--- Background Scheduler Run Complete ---" -ForegroundColor Gray
}
catch
{
    Write-Host "Critical Orchestration Error: $_" -ForegroundColor Red
}
finally
{
    Stop-Transcript
}
