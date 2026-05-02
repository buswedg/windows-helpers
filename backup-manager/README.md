# Backup Manager

Utility to backup directories using 7-Zip with support for exclusion patterns and standardized configurations.

## Features
- **Smart Validation**: Prevents execution errors by validating source and destination paths before starting.
- **7-Zip Powered**: Uses ultra-high compression (LZMA2) and handles open files via system-wide sharing modes.
- **Smart Excludes**: Supports `.gitignore` style logic for handling recursion and directory patterns.
- **Auto-Discovery**: Automatically scans for JSON configurations in the `configs/` directory.
- **Logging**: Generates detailed transcripts of every backup run for audit and troubleshooting.

## Usage
1. **Prepare Configuration**: Create a JSON file in the `configs` folder defining your source paths and backup destination.
2. **Run Backup**: Execute the script with your configuration:
```powershell
.\Backup-Manager.ps1 -Config "my-backup.json"
```

## Configuration
Example structure for `my-backup.json`:
```json
{
    "BackupDir": "D:\\Backups\\Projects",
    "Sources": [
        "C:\\Projects\\MyApps"
    ],
    "Excludes": [
        "node_modules/",
        "env/",
        "/.git",
        "*.tmp"
    ],
    "ExcludeFile": "my-excludes.txt"
}
```

### Smart Pattern Syntax
The manager interprets patterns in the `Excludes` list using a `.gitignore` style logic:

| Pattern | Logic | Behavior |
| :--- | :--- | :--- |
| **`node_modules/`** | Recursive Folder | Skips any folder named `node_modules` anywhere in the tree. |
| **`/.git`** | Root Only | Skips `.git` ONLY if it is at the root of a source folder. |
| **`*.tmp`** | Wildcard | Skips any file matching the extension recursively. |
| **`temp/*`** | Contents Only | Skips files inside `temp`, but keeps the `temp` folder in the archive. |

### ExcludeFile
You can also point to an external text file using `ExcludeFile`. Each line in the text file will be treated as a recursive exclusion (`-xr!`).

## Architecture
- `Backup-Manager.ps1`: Main logic and 7-Zip orchestration.
- `configs/`: Directory for JSON configuration files.
- `configs/example.json.dist`: Template for new configurations.
