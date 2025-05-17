# Winget-Installer

Installs a configurable list of applications using WinGet and PowerShell.

## Usage

1. Create a new 'config.json' file in the configs folder, with the packages you'd like to install.

2. Simply run 'run_winget_installer.bat' and reference the filename (with extension) of the config file you created
   above.

## Note:

In encountering the below error:

```bash
Installer hash does not match; this cannot be overridden when running as admin
```

Run the following in an elevated prompt:

```bash
winget settings --enable InstallerHashOverride
```

And then install the package manually by running the following in a non-elevated prompt:

```bash
winget install --ignore-security-hash [package]
```
