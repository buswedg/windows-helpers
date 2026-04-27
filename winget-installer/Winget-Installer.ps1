<#
.SYNOPSIS
Installs a configurable list of applications using WinGet and PowerShell.

.DESCRIPTION
This script reads a JSON file that lists application IDs, and downloads/installs each application ID via WinGet.

.PARAMETER Config
Name of the JSON file (from the 'configs' directory) containing application IDs and optional cleanup info.

.OUTPUTS
Console output and log file saved to %TEMP%\winget-installer.log.

.EXAMPLE
PS> .\Winget-Installer.ps1 -Config "config.json"
#>

[CmdletBinding()]
param (
    [string]$Config,
    [switch]$DownloadOnly
)

#Requires -RunAsAdministrator

# --- Function Definitions ---

function Get-ConfigPath
{
    $ConfigDir = Join-Path $PSScriptRoot "configs"
    if (-not (Test-Path $ConfigDir))
    {
        Write-Host "Config directory not found: $ConfigDir" -ForegroundColor Red
        exit 1
    }

    if ($Config)
    {
        $ConfigPath = Join-Path $ConfigDir $Config
        if (-not (Test-Path $ConfigPath))
        {
            if (Test-Path $Config)
            {
                return $Config
            }
            Write-Host "Specified JSON config file does not exist: $ConfigPath" -ForegroundColor Red
            exit 1
        }
        return $ConfigPath
    }

    $ConfigFiles = Get-ChildItem -Path $ConfigDir -Filter *.json
    if ($ConfigFiles.Count -eq 0)
    {
        Write-Host "No JSON config files found in '$ConfigDir'." -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable JSON config files:`n" -ForegroundColor Green
    for ($i = 0; $i -lt $ConfigFiles.Count; $i++)
    {
        Write-Host ("{0}: {1}" -f ($i + 1), $ConfigFiles[$i].Name)
    }

    do
    {
        $Selection = Read-Host "`nEnter the number of the JSON config file to use"
    } while (-not ($Selection -match '^\d+$') -or [int]$Selection -lt 1 -or [int]$Selection -gt $ConfigFiles.Count)

    return $ConfigFiles[[int]$Selection - 1].FullName
}

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "winget-installer.log"
Start-Transcript -Path $LogPath

try
{
    if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue))
    {
        Write-Host "WinGet not found. Installing..." -ForegroundColor Yellow

        Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\winget.msixbundle"

        Add-AppxPackage "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx" -ErrorAction SilentlyContinue
        Add-AppxPackage "$env:TEMP\winget.msixbundle" -ErrorAction SilentlyContinue

        Remove-Item "$env:TEMP\winget" -Recurse -Force -ErrorAction SilentlyContinue
    }

    $ConfigPath = Get-ConfigPath
    try
    {
        $ConfigData = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch
    {
        Write-Host "Failed to parse JSON: $ConfigPath" -ForegroundColor Red
        return
    }

    if (-not $ConfigData.Apps -or $ConfigData.Apps.Count -eq 0)
    {
        Write-Host "No apps found in config file." -ForegroundColor Yellow
        return
    }

    # Execution branches
    if ($DownloadOnly)
    {
        $BundleDir = Join-Path $PSScriptRoot "offline_bundle"
        if (-not (Test-Path $BundleDir))
        {
            New-Item -Path $BundleDir -ItemType Directory -Force | Out-Null
        }

        Write-Host "`nDownloading applications to $BundleDir..." -ForegroundColor Green
        
        $InstallScriptPath = Join-Path $BundleDir "install.bat"
        $InstallScriptContent = "@echo off`r`n:: Auto-generated offline installer script`r`n:: Run as Administrator to install all packages silently.`r`n`r`n"
        
        # Test elevation in the generated batch script
        $InstallScriptContent += "net session >nul 2>&1`r`nif %errorLevel% neq 0 (`r`n    echo Requesting Administrator privileges...`r`n    powershell -Command `"Start-Process cmd -ArgumentList '/c %~dpnx0' -Verb RunAs`"`r`n    exit /b`r`n)`r`n`r`n"
        
        # Go to script directory
        $InstallScriptContent += "cd /d `"%~dp0`"`r`n`r`n"

        foreach ($AppProp in $ConfigData.Apps.psobject.Properties)
        {
            $App = $AppProp.Name
            $Version = $AppProp.Value
            
            Write-Host "`nDownloading package for '$App' (Version: $Version)..." -ForegroundColor Cyan
            
            $AppDir = Join-Path $BundleDir $App
            if (-not (Test-Path $AppDir)) {
                 New-Item -Path $AppDir -ItemType Directory -Force | Out-Null
            }

            $VersionArg = if ($Version -ne "latest") { "--version $Version" } else { "" }
            if ($Version -ne "latest") {
                winget download --id $App --version $Version --download-directory $AppDir --accept-source-agreements
            } else {
                winget download --id $App --download-directory $AppDir --accept-source-agreements
            }
            
            # Add an entry to install.bat for whatever installers landed in the folder
            $InstallScriptContent += "echo Installing $App...`r`n"
            $InstallScriptContent += "for %%f in (`"$App\*.exe`") do ( start /wait `"`" `"%%f`" )`r`n"
            $InstallScriptContent += "for %%f in (`"$App\*.msi`") do ( msiexec.exe /i `"%%f`" /qn /norestart )`r`n"
            $InstallScriptContent += "for %%f in (`"$App\*.msix`", `"$App\*.appx`") do ( powershell -Command `"Add-AppxPackage -Path '%%f'`" )`r`n`r`n"
        }

        $InstallScriptContent += "echo.`r`necho All operations completed.`r`npause`r`n"
        Set-Content -Path $InstallScriptPath -Value $InstallScriptContent -Encoding UTF8
        Write-Host "`nOffline bundle generation complete. Check the \offline_bundle folder and use install.bat on your target machine." -ForegroundColor Green
    }
    else
    {
        # Install Logic
        Write-Host "`nInstalling applications (skipping if already present)..." -ForegroundColor Green

        foreach ($AppProp in $ConfigData.Apps.psobject.Properties)
        {
            $App = $AppProp.Name
            $Version = $AppProp.Value

            Write-Host "`nChecking if '$App' (Version: $Version) is already installed..." -ForegroundColor Gray
            
            if ($Version -ne "latest") {
                winget list --id $App --version $Version --accept-source-agreements | Out-Null
            } else {
                winget list --id $App --accept-source-agreements | Out-Null
            }

            if ($LASTEXITCODE -eq -1978335212)
            {
                Write-Host "$App (Version: $Version) not found. Installing..." -ForegroundColor Yellow
                
                if ($Version -ne "latest") {
                    winget install $App --version $Version --silent --force --source winget --accept-package-agreements --accept-source-agreements
                } else {
                    winget install $App --silent --force --source winget --accept-package-agreements --accept-source-agreements
                }

                if ($ConfigData.ProcessesToKill)
                {
                    foreach ($Proc in $ConfigData.ProcessesToKill)
                    {
                        Get-Process $Proc -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
                    }
                }
            }
            else
            {
                Write-Host "$App (Version: $Version) is already installed." -ForegroundColor Cyan
            }
        }
    }

    # Cleanup files
    if ($ConfigData.FilesToClean)
    {
        Write-Host "`nCleaning specified files from desktop..." -ForegroundColor Green
        $PublicDesktop = "C:\Users\Public\Desktop"
        $UserDesktop = [Environment]::GetFolderPath("Desktop")
        $CutoffTime = (Get-Date).AddHours(-1)

        foreach ($File in $ConfigData.FilesToClean)
        {
            foreach ($Path in @($PublicDesktop, $UserDesktop))
            {
                Get-ChildItem "$Path\$File" -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -le $CutoffTime } |
                        Remove-Item -Force -ErrorAction SilentlyContinue

                Get-ChildItem "$Path\$File" -Hidden -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -le $CutoffTime } |
                        Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
finally
{
    Stop-Transcript
    Write-Host "`nAll operations completed. Exiting in 5 seconds..."
    Start-Sleep -Seconds 5
}
