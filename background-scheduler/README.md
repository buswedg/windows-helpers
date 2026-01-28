# Background-Scheduler

Dynamically manage desktop wallpapers using a theme library and daily scheduling.

## Usage

1. **Configure themes**: Create or edit a JSON file in the `configs` folder. Define your `triggers` (library of theme files) and your weekly `schedule`.

2. **Run installation**: Run `run_helper_bs_install_task.bat` and select your configuration. This will register a `\Custom\BackgroundScheduler` task in Task Scheduler.

3. **Background Updates**: The task runs automatically **on Logon** and **every hour**. It selects the correct theme for the day (with randomization for unmapped days) and applies the wallpaper based on your time-of-day triggers.

## Architecture

- **Background-Scheduler.ps1**: The primary entry point. Centralizes logging, identifies the current theme for the day, and coordinates the application flow.
- **Set-Background.ps1**: A specialized applier that sets the desktop background based on time-of-day triggers.
- **Install-Task.ps1**: Registers the task. Uses `conhost.exe --headless` to run the task silently.
