<#
.SYNOPSIS
Starts a list of physical machines by using Wake On LAN.

.DESCRIPTION
Wake sends a Wake On LAN magic packet to a given machine's MAC address by
calculating the directed broadcast address of the primary network interface.

.PARAMETER MacAddress
MacAddress of target machine to wake (e.g., A0DEF169BE02 or 24-8A-07-20-C8-CA).

.OUTPUTS
Console output and log file saved to %TEMP%\wake-on-lan.log.

.EXAMPLE
PS> .\Wake-On-Lan.ps1 -MacAddress "A0DEF169BE02"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="MAC address of target machine to wake up")]
    [string]$MacAddress
)

# --- Function Definitions ---

function Send-Packet
{
    param ([string]$Mac)
    
    $UdpClient = $null 
    
    try
    {
        # 1. Get the Primary Network Configuration
        $NetConfig = Get-NetIPConfiguration | Where-Object { 
            ($_.IPv4DefaultGateway -ne $null) -and 
            ($_.IPv4Address.IPAddress -notmatch '^169\.254\.')
        } | Select-Object -First 1

        if (-not $NetConfig)
        {
            throw "Could not find a valid IPv4 configuration with a Default Gateway. Check your network."
        }
        
        $IPAddress = [Net.IPAddress]::Parse($NetConfig.IPv4Address.IPAddress)
        $PrefixLength = $NetConfig.IPv4Address.PrefixLength
        
        Write-Host "Selected IP: $($IPAddress.IPAddressToString) / $($PrefixLength)" -ForegroundColor Gray

        # 2. Calculate Directed Broadcast Address
        $HostMaskUint = [System.UInt32]::MaxValue -shr $PrefixLength
        $HostMaskBytes = [System.BitConverter]::GetBytes($HostMaskUint)
        
        if ([System.BitConverter]::IsLittleEndian)
        {
            [Array]::Reverse($HostMaskBytes)
        }
        
        $IPBytes = $IPAddress.GetAddressBytes()
        $BroadcastBytes = @()
        for ($i = 0; $i -lt 4; $i++)
        {
            $BroadcastBytes += $IPBytes[$i] -bor $HostMaskBytes[$i]
        }
        
        $BroadcastAddress = [Net.IPAddress]::new($BroadcastBytes)
        Write-Host "Calculated Broadcast Address: $($BroadcastAddress.IPAddressToString)" -ForegroundColor Gray

        # 3. Send Magic Packet
        $UdpClient = New-Object Net.Sockets.UdpClient
        $UdpClient.EnableBroadcast = $true 

        $IPEndPoint = New-Object Net.IPEndPoint $BroadcastAddress, 9
        $MACBytes = [Net.NetworkInformation.PhysicalAddress]::Parse($Mac)
        $Packet = [Byte[]](,0xFF*6)+($MACBytes.GetAddressBytes()*16)

        $UdpClient.Send($Packet, $Packet.Length, $IPEndPoint) | Out-Null
        Write-Host "Magic packet sent successfully to $Mac" -ForegroundColor Green
    }
    catch
    {
        Write-Host "Error during packet sending: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally
    {
        if ($UdpClient)
        {
            $UdpClient.Close()
            $UdpClient.Dispose()
        }
    }
}

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "wake-on-lan.log"
Start-Transcript -Path $LogPath

try
{
    $MacReady = $MacAddress -replace '[-.:]', ''
    $MacReady = $MacReady.ToUpper()

    Write-Host "`nSending magic packet to $MacReady..." -ForegroundColor Cyan
    Send-Packet -Mac $MacReady
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
finally
{
    Stop-Transcript
}