# Defender-Excluder

Applies a configurable list of directory exclusions to Windows Defender using PowerShell.

## Features
- **JSON Configuration**: Define your exclusion paths in a simple JSON file.
- **Clear Mode**: Option to clear all existing Defender exclusions before applying new ones, or run a clear-only mode.

## Usage
1. **Configure Exclusions**: Create a `config.json` file in the `configs` folder defining the paths to exclude.
2. **Apply Exclusions**: Execute `Reset-Defender-Exclusions.ps1` with your configuration:
```powershell
.\Reset-Defender-Exclusions.ps1 -Config "config.json"
```

3. **Clear Existing**: To remove all current exclusions before adding the new ones:
```powershell
.\Reset-Defender-Exclusions.ps1 -Config "config.json" -ClearExisting
```

4. **Clear All (No Config)**: To completely clear all exclusions and do nothing else:
```powershell
.\Reset-Defender-Exclusions.ps1 -ClearExisting
```

## Configuration
Example structure for `config.json`:
```json
{
  "Exclusions": [
    "C:\\Path\\To\\Exclude",
    "D:\\Another\\Path"
  ]
}
```

## Architecture
- `Reset-Defender-Exclusions.ps1`: Main script that parses the config and uses `Add-MpPreference` and `Remove-MpPreference` cmdlets.
