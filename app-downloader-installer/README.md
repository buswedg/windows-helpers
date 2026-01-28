# App-Downloader-Installer

Downloads and/or installs a configurable list of applications using PowerShell.

## Features
- **Configurable Downloads**: Specify applications to download via a simple JSON configuration.
- **Automated Installation**: Supports running installers with silent arguments.
- **Custom Destination**: Flexible download and installation paths.

## Usage
1. **Configure Apps**: Create a JSON file in the `configs` folder defining the list of applications, their URLs, and installation arguments.
2. **Run Script**: Execute `App-Downloader-Installer.ps1` with the configuration filename:
```powershell
.\App-Downloader-Installer.ps1 -Json "config.json"
```

## Configuration
Example structure for `config.json`:
```json
{
  "apps": [
    {
      "name": "AppName",
      "url": "https://example.com/installer.exe",
      "args": "/silent"
    }
  ]
}
```

## Architecture
- `App-Downloader-Installer.ps1`: Main script that parses the config and orchestration downloads/installs.
- `utils/Invoke-Download.ps1`: Helper script for handling file downloads.

