<#
.SYNOPSIS
Configure a set of network adapters using Powershell.

.DESCRIPTION
This script reads a JSON file containing a set of network adapter configurations, then applies those settings to each adapter.

.PARAMETER Json
Name of the JSON file (from the 'configs' directory) that contains the set of adapter configurations.

.OUTPUTS
Console output and a log file saved to %TEMP%\network-adapter-manager.log.

.EXAMPLE
PS> .\Network-Adapter-Manager.ps1 -Json "test.json"
#>

[CmdletBinding()]
param (
    [string]$Json
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

$ConfigData = Get-ConfigData

if (-not $ConfigData.Adapters -or $ConfigData.Adapters.Count -eq 0) {
    Write-Host "No adapters found in config file." -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

foreach ($Adapter in $ConfigData.Adapters) {
    try {
        $name = $Adapter.Name

        if ($Adapter.Enabled -eq $false) {
            Write-Host "Disabling adapter: $name" -ForegroundColor Yellow
            Disable-NetAdapter -Name $name -Confirm:$false -ErrorAction Stop
            continue
        }

        Write-Host "Enabling adapter: $name" -ForegroundColor Cyan
        Enable-NetAdapter -Name $name -Confirm:$false -ErrorAction Stop

        if ($Adapter.Mode -eq 'dhcp') {
            Write-Host "Setting adapter '$name' to DHCP"
            Set-NetIPInterface -InterfaceAlias $name -Dhcp Enabled -ErrorAction Stop
            Set-DnsClientServerAddress -InterfaceAlias $name -ResetServerAddresses -ErrorAction Stop
        }
        elseif ($Adapter.Mode -eq 'static') {
            Write-Host "Assigning static IP to '$name': $($Adapter.IPAddress)/$($Adapter.PrefixLength)"

            # Remove all existing IPv4 addresses
            Get-NetIPAddress -InterfaceAlias $name -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Write-Host "Removing existing IP: $($_.IPAddress)" -ForegroundColor DarkGray
                    Remove-NetIPAddress -InterfaceAlias $name -IPAddress $_.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
                }

            # Remove any default gateway routes on this interface
            Get-NetRoute -InterfaceAlias $name -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Write-Host "Removing existing default gateway: $($_.NextHop)" -ForegroundColor DarkGray
                    Remove-NetRoute -InterfaceAlias $name -DestinationPrefix $_.DestinationPrefix -Confirm:$false -ErrorAction SilentlyContinue
                }

            # Assign static IP
            New-NetIPAddress -InterfaceAlias $name `
                             -IPAddress $Adapter.IPAddress `
                             -PrefixLength $Adapter.PrefixLength `
                             -DefaultGateway $Adapter.Gateway `
                             -ErrorAction Stop

            # Set DNS servers if defined
            if ($Adapter.DNS) {
                Write-Host "Setting DNS for '$name': $($Adapter.DNS -join ', ')"
                Set-DnsClientServerAddress -InterfaceAlias $name -ServerAddresses $Adapter.DNS -ErrorAction Stop
            }
        }
        else {
            Write-Host "Unknown mode for adapter '$name': $($Adapter.Mode)" -ForegroundColor Red
        }

    } catch {
        Write-Host "Error processing '$($Adapter.Name)': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Stop-Transcript
Write-Host "`nAll operations completed. Exiting in 5 seconds..."
Start-Sleep -Seconds 5
exit
