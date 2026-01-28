# WinGet-Installer

Installs a configurable list of applications using WinGet and PowerShell.

## Features
- **Bulk Installation**: Install multiple applications via a single JSON config.
- **Auto-dependency**: Automatically installs WinGet if it is not present on the system.
- **Smart Detection**: Skips applications that are already installed.
- **Process Management**: Can terminate specific processes during installation.
- **Desktop Cleanup**: Option to remove unwanted desktop shortcuts after installation.

## Usage
1. **Configure Apps**: Create a `config.json` file in the `configs` folder defining the list of package IDs.
2. **Run Installer**: Execute `WinGet-Installer.ps1` with the configuration:
```powershell
.\WinGet-Installer.ps1 -Json "config.json"
```

## Configuration
Example structure for `config.json`:
```json
{
  "Apps": [
    "Google.Chrome",
    "Mozilla.Firefox"
  ],
  "ProcessesToKill": [
    "msedge"
  ],
  "FilesToClean": [
    "Microsoft Edge.lnk"
  ]
}
```

## Architecture
- `WinGet-Installer.ps1`: Main script that handles WinGet installation (if missing) and package installation.

## Troubleshooting
If you encounter an "Installer hash does not match" error:
```bash
Installer hash does not match; this cannot be overridden when running as admin
```
Run the following in an elevated prompt:
```bash
winget settings --enable InstallerHashOverride
```
Then install the package manually in a non-elevated prompt:
```bash
winget install --ignore-security-hash [package]
```

