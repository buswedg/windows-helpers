# Network-Adapter-Manager

Configure a set of network adapters using PowerShell.

## Features
- **Profile Management**: Enable or disable specific network adapters based on defined profiles.
- **Bulk Operations**: "Disable All" switch for quickly shutting down all physical adapters.
- **Safe Execution**: Checks if adapters exist before attempting modification to avoid errors.

## Usage
1. **Configure Adapters**: Create a `config.json` file in the `configs` folder defining which adapters should be enabled or disabled.
2. **Run Manager**: Execute `Network-Adapter-Manager.ps1` with your configuration:
```powershell
.\Network-Adapter-Manager.ps1 -Json "config.json"
```

3. **Disable All**: Run with the `-DisableAll` switch to disable all network interfaces.

```powershell
.\Network-Adapter-Manager.ps1 -DisableAll
```

## Configuration
Example structure for `config.json`:
```json
{
  "Adapters": [
    {
      "Name": "Ethernet",
      "Enabled": true
    },
    {
      "Name": "Wi-Fi",
      "Enabled": false
    }
  ]
}
```

## Architecture
- `Network-Adapter-Manager.ps1`: Main script processing JSON configurations and executing `Enable-NetAdapter` or `Disable-NetAdapter` commands.
