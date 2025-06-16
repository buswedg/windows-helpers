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
Reads 'test.json' from the 'configs' directory and applies the network adapter settings.

.EXAMPLE
PS> .\Network-Adapter-Manager.ps1 -DisableAll
Disables all physical network adapters on the system.
#>

[CmdletBinding()]
param (
    [string]$Json,
    [switch]$DisableAll
)

#Requires -RunAsAdministrator

function Get-ConfigData {
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
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    }

    $ConfigFiles = Get-ChildItem -Path $ConfigDir -Filter *.json
    if ($ConfigFiles.Count -eq 0) {
        Write-Host "No JSON config files found in '$ConfigDir'." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++) {
        Write-Host "$( $i + 1 ): $( $ConfigFiles[$i].Name )"
    }

    do {
        $Selection = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Selection -match '^\d+$') -or [int]$Selection -lt 1 -or [int]$Selection -gt $ConfigFiles.Count)

    $ConfigFile = $ConfigFiles[[int]$Selection - 1].FullName
    return Get-Content $ConfigFile -Raw | ConvertFrom-Json
}

$LogPath = Join-Path $env:TEMP "network-adapter-manager.log"
Start-Transcript -Path $LogPath

if ($DisableAll) {
    $Adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -ne 'Disabled' }
    foreach ($Adapter in $Adapters) {
        try {
            Write-Host "Disabling adapter: $($Adapter.Name)" -ForegroundColor Yellow
            Disable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop
        } catch {
            Write-Host "Error disabling '$($Adapter.Name)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "`nAll adapters processed. Exiting..." -ForegroundColor Green
    exit 0
}

$ConfigData = Get-ConfigData

if (-not $ConfigData.Adapters -or $ConfigData.Adapters.Count -eq 0) {
    Write-Host "No adapters found in config file." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

foreach ($Config in $ConfigData.Adapters) {
    try {
        $ConfigName = $Config.Name
        $ConfigEnabled = $Config.Enabled

        $Adapter = Get-NetAdapter -Name $ConfigName -ErrorAction Stop
        $AdapterEnabled = $Adapter.Status -eq 'Up'

        if ($ConfigEnabled -ne $AdapterEnabled) {
            if ($ConfigEnabled) {
                Write-Host "Enabling adapter: $ConfigName" -ForegroundColor Cyan
                Enable-NetAdapter -Name $ConfigName -Confirm:$false -ErrorAction Stop
            } else {
                Write-Host "Disabling adapter: $ConfigName" -ForegroundColor Yellow
                Disable-NetAdapter -Name $ConfigName -Confirm:$false -ErrorAction Stop
            }
            Start-Sleep -Seconds 2
        } else {
            Write-Host "Adapter '$ConfigName' is already in desired state. Skipping..." -ForegroundColor DarkGray
        }

        if ($ConfigEnabled -and $Config.Mode) {
            if ($Config.Mode -eq 'dhcp') {
                Write-Host "Setting adapter '$ConfigName' to DHCP"
                Set-NetIPInterface -InterfaceAlias $ConfigName -Dhcp Enabled -ErrorAction Stop
                Set-DnsClientServerAddress -InterfaceAlias $ConfigName -ResetServerAddresses -ErrorAction Stop
            }
            elseif ($Config.Mode -eq 'static') {
                Write-Host "Assigning static IP to '$ConfigName': $($Config.IPAddress)/$($Config.PrefixLength)"

                # Remove all IPv4 addresses (including DHCP leases)
                Get-NetIPAddress -InterfaceAlias $ConfigName -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

                # Remove default gateways
                Get-NetRoute -InterfaceAlias $ConfigName -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | 
                    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

                # Disable DHCP
                Set-NetIPInterface -InterfaceAlias $ConfigName -Dhcp Disabled -ErrorAction SilentlyContinue

                # Reset DNS client addresses
                Set-DnsClientServerAddress -InterfaceAlias $ConfigName -ResetServerAddresses -ErrorAction SilentlyContinue

                # Assign the static IP + gateway
                New-NetIPAddress -InterfaceAlias $ConfigName `
                                 -IPAddress $Config.IPAddress `
                                 -PrefixLength $Config.PrefixLength `
                                 -DefaultGateway $Config.Gateway `
                                 -ErrorAction SilentlyContinue

                # Set DNS servers if configured
                if ($Config.DNS) {
                    Write-Host "Setting DNS for '$ConfigName': $($Config.DNS -join ', ')"
                    Set-DnsClientServerAddress -InterfaceAlias $ConfigName -ServerAddresses $Config.DNS -ErrorAction Stop
                }
            }
            else {
                Write-Host "Unknown mode '$($Config.Mode)' for adapter '$ConfigName'" -ForegroundColor Red
            }
        }

    } catch {
        Write-Host "Error processing '$ConfigName': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Exiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
