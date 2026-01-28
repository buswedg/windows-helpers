# Background-Scheduler

Dynamically manage desktop wallpapers using a theme library and daily scheduling.

## Features
- **Dynamic Scheduling**: Apply different themes based on the day of the week.
- **Time-of-Day Triggers**: Change wallpapers based on specific times throughout the day.
- **Silent Operation**: Runs invisibly in the background.

## Usage
1. **Configure Themes**: Create or edit a JSON file in the `configs` folder. Define your `triggers` (library of theme files) and a weekly `schedule`.
2. **Run Installation**: Execute `Install-Task.ps1` with the configuration to register the scheduled task:
```powershell
.\Install-Task.ps1 -Json "config.json"
```
3. **Background Updates**: The task runs automatically **on Logon** and **every hour**, selecting the correct theme and applying wallpapers.

## Configuration
Example structure for `config.json`:
```json
{
  "schedule": {
    "Monday": "ThemeName",
    "Tuesday": "AnotherTheme"
  },
  "triggers": {
    "ThemeName": "relative/path/to/theme/config.json"
  }
}
```

## Architecture
- `Background-Scheduler.ps1`: Primary entry point that centralizes logging and theme selection.
- `Set-Background.ps1`: specialized applier that sets the desktop background based on time-of-day triggers.
- `Install-Task.ps1`: Registers the task using `conhost.exe --headless` for silent execution.
