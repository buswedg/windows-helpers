<#
.SYNOPSIS
Configure a set of network adapters using PowerShell.

.DESCRIPTION
This script can either read a JSON file containing a set of network adapter configurations and apply them, 
or disable all network adapters if the -DisableAll switch is used.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that contains the set of adapter configurations.

.PARAMETER DisableAll
Optional switch to disable all physical network adapters, bypassing the JSON configuration.

.OUTPUTS
Console output and a log file saved to %TEMP%\network-adapter-manager.log.

.EXAMPLE
PS> .\Network-Adapter-Manager.ps1 -Json "test.json"
#>

[CmdletBinding()]
param (
    [string]$Json,
    [switch]$DisableAll
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

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "network-adapter-manager.log"
Start-Transcript -Path $LogPath

try
{
    if ($DisableAll)
    {
        $Adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -ne 'Disabled' }
        if ($null -eq $Adapters -or $Adapters.Count -eq 0)
        {
            Write-Host "No active physical adapters found." -ForegroundColor Cyan
        }
        else
        {
            foreach ($Adapter in $Adapters)
            {
                try
                {
                    Write-Host "Disabling adapter: $($Adapter.Name)" -ForegroundColor Yellow
                    Disable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
                }
                catch
                {
                    Write-Host "Error disabling '$($Adapter.Name)': $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        Write-Host "`nAll adapters processed. Exiting..." -ForegroundColor Green
    }
    else
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

        if (-not $ConfigData.Adapters -or $ConfigData.Adapters.Count -eq 0)
        {
            Write-Host "No adapters found in config file." -ForegroundColor Yellow
            return
        }

        foreach ($Config in $ConfigData.Adapters)
        {
            try
            {
                $ConfigName = $Config.Name
                $ConfigEnabled = $Config.Enabled

                $Adapter = Get-NetAdapter -Name $ConfigName -ErrorAction Stop
                
                if ($ConfigEnabled)
                {
                    if ($Adapter.Status -eq 'Disabled')
                    {
                        Write-Host "Enabling adapter: $ConfigName" -ForegroundColor Cyan
                        Enable-NetAdapter -Name $ConfigName -Confirm:$false
                    }
                    else
                    {
                        Write-Host "Adapter already enabled: $ConfigName" -ForegroundColor Gray
                    }
                }
                else
                {
                    if ($Adapter.Status -ne 'Disabled')
                    {
                        Write-Host "Disabling adapter: $ConfigName" -ForegroundColor Yellow
                        Disable-NetAdapter -Name $ConfigName -Confirm:$false
                    }
                    else
                    {
                        Write-Host "Adapter already disabled: $ConfigName" -ForegroundColor Gray
                    }
                }
            }
            catch
            {
                Write-Host "Warning: Adapter '$($Config.Name)' not found on this system." -ForegroundColor Yellow
            }
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
