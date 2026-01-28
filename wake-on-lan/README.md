# Wake-On-Lan

Starts physical machines using Wake On LAN magic packets.

## Features
- **Magic Packet**: Sends standard Wake-on-LAN magic packets to target MAC addresses.
- **Auto-Discovery**: Automatically calculates the correct directed broadcast address based on the machine's primary active network interface.
- **Simple CLI**: Easy-to-use command line argument for specifying target MAC.

## Usage
1. **Identify MAC**: Locate the MAC address of the target machine you wish to wake.
2. **Run Script**: Execute `Wake-On-Lan.ps1` with the MAC address as a parameter.

```powershell
.\Wake-On-Lan.ps1 -MacAddress "A0DEF169BE02"
```

## Architecture
- `Wake-On-Lan.ps1`: Single-file script that determines network configuration and broadcasts the magic packet via UDP.

