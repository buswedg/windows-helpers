<#
.SYNOPSIS
Installs the background scheduler orchestration task.

.DESCRIPTION
Registers a single scheduled task (BackgroundScheduler-LogOnOrHourly-Run) that runs Background-Scheduler.ps1.
The task is configured to run:
1. Hourly (daily repetition).
2. At User Logon (with a 30-second delay).

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that defines the background schedule.

.OUTPUTS
Console output indicating success or failure of task registration.

.EXAMPLE
PS> .\Install-Task.ps1 -Json "config.json"
#>

[CmdletBinding()]
param (
    [string]$Json
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

    if ($Json)
    {
        $ConfigPath = Join-Path $ConfigDir $Json
        if (-not (Test-Path $ConfigPath))
        {
            Write-Host "Specified JSON config file does not exist: $ConfigPath" -ForegroundColor Red
            exit 1
        }
        return $Json
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
    # 1. Select Config
    $ConfigName = Get-ConfigFileName
    
    $TaskName = "BackgroundScheduler-LogOnOrHourly-Run"
    $TaskPath = "\Custom\"
    $ScriptPath = "$PSScriptRoot\Background-Scheduler.ps1"

    Write-Host "`nRegistering task: $TaskName using config $ConfigName" -ForegroundColor Cyan

    # 2. Define Action
    # Use conhost.exe --headless to run PowerShell silently (no window flash)
    $ArgList = "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" -Json `"$ConfigName`""
    $Action = New-ScheduledTaskAction -Execute "conhost.exe" -Argument $ArgList

    # 3. Define Triggers
    $Triggers = @()
    
    # Trigger 1: Daily, repeating hourly
    $TimeTrigger = New-ScheduledTaskTrigger -Daily -At 12:00am
    $TimeTrigger.Repetition = (New-ScheduledTaskTrigger -Once -At 12:00am -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
    $Triggers += $TimeTrigger

    # Trigger 2: At Logon (30 sec delay)
    $LogonTrigger = New-ScheduledTaskTrigger -AtLogOn
    $LogonTrigger.Delay = "PT30S"
    $Triggers += $LogonTrigger

    # 4. Define Settings
    $Settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -Priority 5

    # 5. Unregister existing Task
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue

    # 6. Register Task
    Register-ScheduledTask -Action $Action -Trigger $Triggers -Settings $Settings -TaskName $TaskName -TaskPath $TaskPath -User $env:USERNAME -Force | Out-Null

    Write-Host "SUCCESS: BackgroundScheduler task registered successfully." -ForegroundColor Green
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
