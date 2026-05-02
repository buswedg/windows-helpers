# Registry Manager

A PowerShell helper to manage registry changes with automatic backup and restoration support.

## Features
- **Smart Actions**: Sophisticated logic for conditional updates (`Update`, `UpdateValue`, `Add`) to prevent creating "ghost" keys.
- **Automatic Backups**: Captures the current state of any modified registry keys before applying changes.
- **One-Click Restoration**: Reverts the registry to its exact prior state using XML-based backups.
- **Append Support**: Safely adds data to strings (e.g., PATH) or `MultiString` lists without overwriting existing entries.
- **Administrative Enforcement**: Automatically ensures it is running with the necessary privileges.

## Usage
1. **Configure Operations**: Create a JSON file in the `configs` folder defining your registry changes.
2. **Apply Changes**: Execute the script with your configuration to apply settings and create a backup:
```powershell
.\Registry-Manager.ps1 -Config "example.json" -Action Apply
```
3. **Restore State**: If needed, revert the changes by running the restore action:
```powershell
.\Registry-Manager.ps1 -Config "example.json" -Action Restore
```

## Configuration
Example structure for `example.json`:
```json
{
    "Operations": [
        {
            "Path": "HKCU:\\Software\\ExampleApp",
            "Name": "AlwaysOnTop",
            "Value": 1,
            "Type": "DWord",
            "Action": "Set"
        },
        {
            "Path": "HKLM:\\SOFTWARE\\MyCustomApp",
            "Name": "ConfigPath",
            "Value": "C:\\Tools",
            "Action": "Add"
        }
    ]
}
```

### Action Types
| Action | Targets | Condition | Behavior |
| :--- | :--- | :--- | :--- |
| **`Set`** (Default) | Key + Value | None | Ensures Key + Value exist. Overwrites if present. |
| **`Update`** | Key | Key exists | Only sets value if the **Key (Path)** exists. |
| **`UpdateValue`** | Value | Value exists | Only sets data if the **Value (Name)** exists. |
| **`Add`** | Value | Value missing | Only sets value if it is **not** already there. |
| **`Append`** | Value | Value exists | Appends data to existing strings or lists. |
| **`Delete`** | Key | Key exists | Deletes the **entire Registry Key**. |
| **`DeleteValue`** | Value | Value exists | Deletes only the **specific Value** name. |

## Architecture
- `Registry-Manager.ps1`: Main script handling registry operations and backup/restore logic.
- `configs/`: Directory for JSON configuration files.
- `backups/`: Directory where XML-based registry snapshots are stored.
- `shortcuts/`: Batch script wrappers for common operations.
