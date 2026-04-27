# Network-Adapter-Manager

Configure a set of network adapters using PowerShell.

## Features
- **Profile Management**: Enable or disable specific network adapters based on defined profiles.
- **Bulk Operations**: "Disable All" switch for quickly shutting down all physical adapters.
- **Safe Execution**: Checks if adapters exist before attempting modification to avoid errors.

## Usage
1. **Configure Adapters**: Create a JSON file in the `configs` folder defining the list of adapters.
2. **Run Manager**: Execute `Network-Adapter-Manager.ps1` with your configuration:
```powershell
.\Network-Adapter-Manager.ps1 -Config "config.json"
```

3. **Disable All**: Run with the `-DisableAll` switch to disable all network interfaces.

```powershell
.\Network-Adapter-Manager.ps1 -DisableAll
```

## Configuration
Adapters can be identified either by their native Windows `Name` or a `MAC` address (which is consistent across reinstalls). If `MAC` is supplied, it takes priority over `Name`.

Example structure for `config.json` showcasing different identification methods:
```json
{
  "Adapters": [
    {
      "Name": "Virtual Switch",
      "Enabled": true
    },
    {
      "MAC": "00:11:22:33:44:55",
      "Enabled": false
    }
  ]
}
```

## Architecture
- `Network-Adapter-Manager.ps1`: Main script processing JSON configurations and executing `Enable-NetAdapter` or `Disable-NetAdapter` commands.
