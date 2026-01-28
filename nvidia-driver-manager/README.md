# NVIDIA-Driver-Manager

Downloads and/or installs essential Nvidia display drivers using PowerShell and 7-Zip.

## Features
- **Minimal Installation**: Installs only the minimal driver components (Display Driver, PhysX), excluding bloatware like GeForce Experience.
- **Automated Workflow**: Supports downloading, installing, or both in a single run.
- **Silent Operation**: Performs silent installations for a disruption-free experience.

## Usage
1. **Configure GPUs**: Create a `config.json` file in the `configs` folder defining your GPU model and driver download URL.
2. **Run Manager**: Execute `Nvidia-Driver-Manager.ps1` with your configuration and desired mode:
```powershell
.\Nvidia-Driver-Manager.ps1 -Json "config.json" -Mode download-install
```

3. **Select Mode**: Use `-Mode` to choose between `download-only`, `install-only`, or `download-install`.

## Configuration
Example structure for `config.json`:
```json
{
  "GPUs": [
    {
      "display_name": "RTX 3080",
      "download_url": "https://us.download.nvidia.com/Windows/..."
    }
  ]
}
```

## Architecture
- `Nvidia-Driver-Manager.ps1`: Main script that handles downloading via BITS and installing via 7-Zip extraction and setup.exe.

