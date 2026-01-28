# Store-App-Uninstaller

Uninstalls a configurable list of Windows Store applications using PowerShell.

## Features
- **Bulk Uninstall**: Remove multiple Windows Store apps via a single configuration.
- **System-wide Removal**: Uninstalls applications for all users on the machine.
- **Safety Checks**: Verifies if an app is installed before attempting removal.

## Usage
1. **Configure Apps**: Create a `config.json` file in the `configs` folder listing the package names of apps to remove.
2. **Run Uninstaller**: Execute `Store-App-Uninstaller.ps1` with the configuration:
```powershell
.\Store-App-Uninstaller.ps1 -Json "config.json"
```

## Configuration
Example structure for `config.json`:
```json
{
  "Apps": [
    "Microsoft.BingWeather",
    "Microsoft.XboxApp"
  ]
}
```

## Architecture
- `Store-App-Uninstaller.ps1`: Main script that iterates through the config and runs `Remove-AppxPackage`.

## Notes
To clear your Windows Store apps library of uninstalled apps, simply press `Windows Key + R`, type `wsreset.exe` and hit enter.

