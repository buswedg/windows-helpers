# WinGet-Installer

Downloads and/or installs a configurable list of applications using WinGet and PowerShell.

## Features
- **Bulk Installation**: Install multiple applications via a single JSON config.
- **Version Targeting**: Pin specific versions (e.g., `1.2.3`) or use `"latest"` for the most recent release.
- **Auto-dependency**: Automatically installs WinGet if it is not present on the system.
- **Unattended Installation**: Automatically accepts all source and package agreements.
- **Process Management**: Can terminate specific running processes (like browsers) prior to installation to prevent file lock issues.
- **Desktop Cleanup**: Includes optional post-install cleanup of recently created desktop shortcuts.
- **Offline Packager**: Can generate a portable offline installer bundle containing downloaded `.exe`, `.msi`, and `.msix` files, along with an auto-generated silent-install batch script.

## Usage
1. **Configure Apps**: Create a JSON file in the `configs` folder defining the list of application IDs.

2. **Run Installer**: Execute `WinGet-Installer.ps1` with your configuration:
```powershell
.\WinGet-Installer.ps1 -Config "config.json"
```

3. **Offline Packager**: To download the installers instead of installing them locally, pass the `-DownloadOnly` switch:
```powershell
.\WinGet-Installer.ps1 -Config "config.json" -DownloadOnly
```
This will create a new `offline_bundle` directory containing all the installers and an `install.bat` file you can use on any target machine.

## Configuration
Example structure for `config.json`:
```json
{
  "Apps": {
    "Google.Chrome": "latest",
    "Python.Python.3.13": "3.13.0"
  },
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

