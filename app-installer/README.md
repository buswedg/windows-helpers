# App-Installer

Downloads and/or installs a configurable list of applications using PowerShell.

## Features
- **Configurable Downloads**: Specify applications to download via a simple JSON configuration.
- **Automated Installation**: Supports running installers.
- **Custom Destination**: Flexible download and installation paths.

## Usage
1. **Configure Apps**: Create a JSON file in the `configs` folder defining the list of applications and their download URLs.

2. **Run Script**: Execute `App-Installer.ps1` with your given config:
```powershell
.\App-Installer.ps1 -Config "config.json"
```

3. **Download Only**: To just download the installers to the output folder without running them:
```powershell
.\App-Installer.ps1 -Config "config.json" -DownloadOnly
```

## Configuration
Example structure for `config.json`:
```json
[
    {
        "app_name":  "FileZilla",
        "filename":  "FileZilla_3.65.0_win64_sponsored2-setup.exe",
        "download_url":  "https://download.filezilla-project.org/client/FileZilla_3.65.0_win64_sponsored2-setup.exe"
    }
]
```

## Architecture
- `App-Installer.ps1`: Main script that parses the config and orchestration downloads/installs.
- `utils/Invoke-Download.ps1`: Helper script for handling file downloads.
