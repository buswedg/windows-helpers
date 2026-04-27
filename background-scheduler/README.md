# Background-Scheduler

Dynamically manage desktop wallpapers using a theme library and daily scheduling.

## Features
- **Dynamic Scheduling**: Apply different themes based on the day of the week.
- **Time-of-Day Triggers**: Change wallpapers based on specific times throughout the day.
- **Silent Operation**: Runs invisibly in the background using Windows Task Scheduler.

## Usage
1. **Configure Themes**: Create or edit a JSON file in the `configs` folder. Define your `triggers` (library of theme files) and a weekly `schedule`.
2. **Run Installation**: Execute `Install-Task.ps1` with the configuration to register the scheduled task:
```powershell
.\Install-Task.ps1 -Config "default.json"
```
3. **Background Updates**: The installer creates tasks in the Windows Task Scheduler under `\Custom\BackgroundScheduler\`.
    - **Daily Tasks**: Created for each day of the week to apply the specific theme for that day.
    - **Logon Task**: A smart task that runs on login, checks the current day against your schedule, and applies the correct theme.

## Configuration
Example structure for `config.json`:
```json
{
  "schedule": {
    "Monday": "ThemeName",
    "Tuesday": "AnotherTheme"
  },
  "triggers": {
    "ThemeName": "relative/path/to/theme/triggers.json",
    "AnotherTheme": "relative/path/to/another/theme/triggers.json"
  }
}
```

## Architecture
- `Install-Task.ps1`: Orchestrator that cleans up old tasks and installs the new split-execution tasks in Windows Task Scheduler.
- `Background-Scheduler.ps1`: Smart entry point (used by Logon task) that resolves the schedule dynamically.
- `Set-Background.ps1`: The worker script (used by Daily tasks) that applies a specific theme's triggers.
