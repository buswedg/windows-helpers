<#
.SYNOPSIS
Installs separate background scheduler tasks for each day.

.DESCRIPTION
Registers multiple scheduled tasks:
1. One task for each day of the week defined in the config (BackgroundScheduler-Daily-<Day>).
2. One task for user logon (BackgroundScheduler-Logon).

All tasks are stored in \Custom\BackgroundScheduler.

.PARAMETER Config
Name of the JSON file (from the 'configs' directory) that defines the background schedule.

.OUTPUTS
Console output indicating success or failure of task registration.

.EXAMPLE
PS> .\Install-Task.ps1 -Config "default.json"
#>

[CmdletBinding()]
param (
    [string]$Config
)

#Requires -RunAsAdministrator

# --- Function Definitions ---

function Get-ConfigFileName
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
            Write-Host "Specified JSON config file does not exist: $ConfigPath" -ForegroundColor Red
            exit 1
        }
        return $Config
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

    return $ConfigFiles[[int]$Selection - 1].Name
}

# --- Main Execution ---

try
{
    # 1. Select config
    $ConfigName = Get-ConfigFileName
    $ConfigDir = Join-Path $PSScriptRoot "configs"
    $ConfigPath = Join-Path $ConfigDir $ConfigName
    
    $TaskPath = "\Custom\BackgroundScheduler\"
    $ScriptPath = "$PSScriptRoot\Background-Scheduler.ps1"

    # Load config to get schedule
    $ConfigData = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Days = $ConfigData.schedule.psobject.Properties.Name

    Write-Host "`nRegistering tasks in $TaskPath using config $ConfigName" -ForegroundColor Cyan

    # 2. Daily task settings
    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -Priority 5

    # 3. Clean up existing tasks
    Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

    # 4. Register daily tasks
    $DayMap = @{
        "Mon" = "Monday"
        "Tue" = "Tuesday"
        "Wed" = "Wednesday"
        "Thu" = "Thursday"
        "Fri" = "Friday"
        "Sat" = "Saturday"
        "Sun" = "Sunday"
    }

    $SetBackgroundScript = "$PSScriptRoot\Set-Background.ps1"

    foreach ($DayKey in $Days)
    {
        $FullDay = $DayMap[$DayKey]
        if ($null -eq $FullDay) { $FullDay = $DayKey } # Fallback if already full name

        # Resolve theme path
        $ThemeName = $ConfigData.schedule.$DayKey
        if (-not $ThemeName) {
            Write-Host "Warning: No theme defined for $DayKey. Skipping." -ForegroundColor Yellow
            continue
        }

        # Resolve path from triggers
        $ThemeRelativePath = $ConfigData.triggers.$ThemeName
        if (-not $ThemeRelativePath) {
            Write-Host "Warning: Theme '$ThemeName' not found in 'triggers' section. Skipping $DayKey." -ForegroundColor Yellow
            continue
        }

        # Handle relative paths
        if (-not [System.IO.Path]::IsPathRooted($ThemeRelativePath)) {
             $ThemeAbsolutePath = Join-Path $PSScriptRoot $ThemeRelativePath
        } else {
             $ThemeAbsolutePath = $ThemeRelativePath
        }
        
        # Verify theme file exists
        if (-not (Test-Path $ThemeAbsolutePath)) {
             Write-Host "Warning: Theme file not found at '$ThemeAbsolutePath'. Skipping $DayKey." -ForegroundColor Red
             continue
        }

        $TaskName = "BackgroundScheduler-Schedule-$FullDay"
        Write-Host "Registering daily task: $TaskName -> $ThemeName" -ForegroundColor Gray

        # Define action with direct link to Set-Background.ps1
        $ArgList = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$SetBackgroundScript`" -Triggers `"$ThemeAbsolutePath`""
        $Action = New-ScheduledTaskAction -Execute "conhost.exe" -Argument $ArgList

        $Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $FullDay -At 12:00am
        # Stop repetition one minute before midnight to prevent overlap
        $Trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 12:00am -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 59)).Repetition

        Register-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings -TaskName $TaskName -TaskPath $TaskPath -User $env:USERNAME -Force | Out-Null
    }

    # 5. Register logon task
    $LogonTaskName = "BackgroundScheduler-Logon-Run"
    Write-Host "Registering logon task: $LogonTaskName" -ForegroundColor Gray

    # Points to Background-Scheduler.ps1 which dynamically determines the day
    $SchedulerScript = "$PSScriptRoot\Background-Scheduler.ps1"
    $LogonArgList = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$SchedulerScript`" -Config `"$ConfigName`""
    $LogonAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument $LogonArgList

    $LogonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $LogonTrigger.Delay = "PT30S"

    Register-ScheduledTask -Action $LogonAction -Trigger $LogonTrigger -Settings $Settings -TaskName $LogonTaskName -TaskPath $TaskPath -User $env:USERNAME -Force | Out-Null

    Write-Host "`nSUCCESS: BackgroundScheduler tasks registered successfully in $TaskPath" -ForegroundColor Green
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
