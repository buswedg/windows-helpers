<#
.SYNOPSIS
Enables or disables a configurable list of network adapters using Powershell.

.DESCRIPTION
This script reads a JSON file containing a list of network adapter names, then enables or disables them based on the specified Mode parameter.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that contains the list of adapter names.

.PARAMETER Mode
Action to perform on all adapters: 'enable' or 'disable'.

.OUTPUTS
Console output and a log file saved to %TEMP%\network-adapter-manager.log.

.EXAMPLE
PS> .\Network-Adapter-Manager.ps1 -Json "adapters.json" -Mode "Enable"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Json,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Enable", "Disable")]
    [string]$Mode
)

#Requires -RunAsAdministrator

function Get-ConfigData
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
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
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
        $Selection = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Selection -match '^\d+$') -or [int]$Selection -lt 1 -or [int]$Selection -gt $ConfigFiles.Count)

    $ConfigFile = $ConfigFiles[[int]$Selection - 1].FullName
    return Get-Content $ConfigFile -Raw | ConvertFrom-Json
}

$LogPath = Join-Path $env:TEMP "network-adapter-manager.log"
Start-Transcript -Path $LogPath

$ConfigData = Get-ConfigData

if (-not $ConfigData.Adapters -or $ConfigData.Adapters.Count -eq 0)
{
    Write-Host "No adapters found in config file." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

foreach ($Adapter in $ConfigData.Adapters)
{
    if (-not $Adapter)
    {
        Write-Host "Invalid entry: adapter name is empty." -ForegroundColor Red
        continue
    }

    try
    {
        switch ( $Mode.ToLower() )
        {
            "enable" {
                Write-Host "Enabling adapter: $Adapter" -ForegroundColor Cyan
                Enable-NetAdapter -Name $Adapter -Confirm:$false -ErrorAction Stop
            }
            "disable" {
                Write-Host "Disabling adapter: $Adapter" -ForegroundColor Yellow
                Disable-NetAdapter -Name $Adapter -Confirm:$false -ErrorAction Stop
            }
        }
    }
    catch
    {
        Write-Host ("Failed to $Mode '$Adapter': {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Exiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
