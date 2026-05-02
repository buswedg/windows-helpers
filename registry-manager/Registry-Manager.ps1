<#
.SYNOPSIS
Manages registry changes with backup and restore capabilities.

.DESCRIPTION
This script reads a JSON config file containing registry paths, names, and values.
It can 'Apply' these changes (while backing up original state) or 'Restore' from a previous backup.
Supports smart actions like Update, UpdateValue, Add, and Append.

.PARAMETER Config
Name of the JSON file (from the 'configs' directory) containing registry operations.

.PARAMETER Action
The action to perform: 'Apply' (default) or 'Restore'.

.OUTPUTS
Console output and log file saved to %TEMP%\registry-manager.log.

.EXAMPLE
PS> .\Registry-Manager.ps1 -Config "example.json" -Action Apply
PS> .\Registry-Manager.ps1 -Config "example.json" -Action Restore
#>

[CmdletBinding()]
param (
    [string]$Config,
    [ValidateSet("Apply", "Restore")]
    [string]$Action = "Apply"
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
            if (Test-Path $Config) { return $Config }
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

function Get-BackupPath
{
    param([string]$ConfigName)
    $BackupDir = Join-Path $PSScriptRoot "backups"
    if (-not (Test-Path $BackupDir)) { New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null }
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigName)
    return Join-Path $BackupDir "$BaseName.backup.xml"
}

# --- Main Execution ---

$LogPath = Join-Path $env:TEMP "registry-manager.log"
Start-Transcript -Path $LogPath

try
{
    $ConfigPath = Get-ConfigPath
    $ConfigName = [System.IO.Path]::GetFileName($ConfigPath)
    $BackupPath = Get-BackupPath -ConfigName $ConfigName

    try
    {
        $ConfigData = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch
    {
        Write-Host "Failed to parse JSON: $ConfigPath" -ForegroundColor Red
        return
    }

    if (-not $ConfigData.Operations)
    {
        Write-Host "No operations found in config file." -ForegroundColor Yellow
        return
    }

    if ($Action -eq "Apply")
    {
        Write-Host "`nBacking up current registry state to $BackupPath..." -ForegroundColor Cyan
        $BackupList = New-Object System.Collections.Generic.List[PSObject]
        
        foreach ($Op in $ConfigData.Operations)
        {
            $Exists = Test-Path $Op.Path
            
            # Special Handling: Key-level Delete
            if ($Op.Action -eq "Delete" -and [string]::IsNullOrEmpty($Op.Name))
            {
                if ($Exists)
                {
                    $Key = Get-Item -Path $Op.Path
                    foreach ($ValName in $Key.GetValueNames())
                    {
                        $BackupList.Add([PSCustomObject]@{
                            Path      = $Op.Path
                            Name      = $ValName
                            Exists    = $true
                            ValExists = $true
                            OldValue  = $Key.GetValue($ValName)
                            Type      = $Key.GetValueKind($ValName)
                        })
                    }
                }
                # Track the key itself
                $BackupList.Add([PSCustomObject]@{
                    Path      = $Op.Path
                    Name      = $null
                    Exists    = $Exists
                    ValExists = $false
                    OldValue  = $null
                })
            }
            else
            {
                # Standard Value-level Backup
                $ValExists = $false
                $OldVal = $null
                $OldType = $null
                if ($Exists)
                {
                    $Prop = Get-ItemProperty -Path $Op.Path -Name $Op.Name -ErrorAction SilentlyContinue
                    if ($Prop)
                    {
                        $ValExists = $true
                        $OldVal = $Prop.($Op.Name)
                        $Key = Get-Item -Path $Op.Path
                        $OldType = $Key.GetValueKind($Op.Name)
                    }
                }
                $BackupList.Add([PSCustomObject]@{
                    Path      = $Op.Path
                    Name      = $Op.Name
                    Exists    = $Exists
                    ValExists = $ValExists
                    OldValue  = $OldVal
                    Type      = $OldType
                })
            }
        }
        $BackupList | Export-Clixml -Path $BackupPath

        Write-Host "Applying registry changes..." -ForegroundColor Green
        foreach ($Op in $ConfigData.Operations)
        {
            $PathExists = Test-Path $Op.Path
            $ValueExists = $false
            if ($PathExists)
            {
                $Prop = Get-ItemProperty -Path $Op.Path -Name $Op.Name -ErrorAction SilentlyContinue
                if ($Prop) { $ValueExists = $true }
            }

            $CurrentAction = if ($Op.Action) { $Op.Action } else { "Set" }
            $Type = if ($Op.Type) { $Op.Type } else { "DWord" }

            switch ($CurrentAction)
            {
                "Delete"
                {
                    if ($PathExists)
                    {
                        Write-Host "Deleting Key: $($Op.Path)..." -ForegroundColor Gray
                        Remove-Item -Path $Op.Path -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                "DeleteValue"
                {
                    if ($ValueExists)
                    {
                        Write-Host "Deleting Value: $($Op.Path)\$($Op.Name)..." -ForegroundColor Gray
                        Remove-ItemProperty -Path $Op.Path -Name $Op.Name -ErrorAction SilentlyContinue
                    }
                }
                "Update"
                {
                    if ($PathExists)
                    {
                        Write-Host "Updating Value (Key exists): $($Op.Path)\$($Op.Name) to $($Op.Value)..." -ForegroundColor Gray
                        Set-ItemProperty -Path $Op.Path -Name $Op.Name -Value $Op.Value -Type $Type -Force
                    }
                    else
                    {
                        Write-Host "Skipped Update: Key not found for $($Op.Path)" -ForegroundColor Yellow
                    }
                }
                "UpdateValue"
                {
                    if ($ValueExists)
                    {
                        Write-Host "Updating Value (Value exists): $($Op.Path)\$($Op.Name) to $($Op.Value)..." -ForegroundColor Gray
                        Set-ItemProperty -Path $Op.Path -Name $Op.Name -Value $Op.Value -Type $Type -Force
                    }
                    else
                    {
                        Write-Host "Skipped UpdateValue: Value not found for $($Op.Name)" -ForegroundColor Yellow
                    }
                }
                "Add"
                {
                    if (-not $ValueExists)
                    {
                        Write-Host "Adding Value (New only): $($Op.Path)\$($Op.Name) to $($Op.Value)..." -ForegroundColor Gray
                        if (-not $PathExists) { New-Item -Path $Op.Path -Force | Out-Null }
                        Set-ItemProperty -Path $Op.Path -Name $Op.Name -Value $Op.Value -Type $Type -Force
                    }
                    else
                    {
                        Write-Host "Skipped Add: Value already exists for $($Op.Name)" -ForegroundColor Yellow
                    }
                }
                "Append"
                {
                    if ($ValueExists)
                    {
                        $CurrentValue = (Get-ItemProperty -Path $Op.Path -Name $Op.Name).$($Op.Name)
                        $NewValue = $null

                        if ($Type -eq "MultiString")
                        {
                            $NewValue = [System.Collections.Generic.List[string]]::new($CurrentValue)
                            if ($Op.Value -is [array]) { $NewValue.AddRange($Op.Value) }
                            else { $NewValue.Add($Op.Value) }
                            $NewValue = $NewValue.ToArray()
                        }
                        else
                        {
                            $Delimiter = if ($Op.Delimiter) { $Op.Delimiter } else { ";" }
                            $NewValue = "$CurrentValue$Delimiter$($Op.Value)"
                        }

                        Write-Host "Appending to $($Op.Path)\$($Op.Name)..." -ForegroundColor Gray
                        Set-ItemProperty -Path $Op.Path -Name $Op.Name -Value $NewValue -Type $Type -Force
                    }
                    else
                    {
                        Write-Host "Skipped Append: Value not found for $($Op.Name)" -ForegroundColor Yellow
                    }
                }
                Default # "Set"
                {
                    Write-Host "Setting $($Op.Path)\$($Op.Name) to $($Op.Value)..." -ForegroundColor Gray
                    if (-not $PathExists) { New-Item -Path $Op.Path -Force | Out-Null }
                    Set-ItemProperty -Path $Op.Path -Name $Op.Name -Value $Op.Value -Type $Type -Force
                }
            }
        }
        Write-Host "`nAll operations completed successfully." -ForegroundColor Green
    }
    elseif ($Action -eq "Restore")
    {
        if (-not (Test-Path $BackupPath))
        {
            Write-Host "No backup file found at $BackupPath. Cannot restore." -ForegroundColor Red
            return
        }

        Write-Host "`nRestoring registry state from $BackupPath..." -ForegroundColor Cyan
        # Reverse the order of backup items to ensure keys are created before values, 
        # or values are removed before keys are deleted.
        $Backup = Import-Clixml -Path $BackupPath
        $ReversedBackup = [System.Collections.Generic.List[PSObject]]::new($Backup)
        $ReversedBackup.Reverse()

        foreach ($Item in $ReversedBackup)
        {
            if ([string]::IsNullOrEmpty($Item.Name))
            {
                # Key-level restoration
                if ($Item.Exists)
                {
                    if (-not (Test-Path $Item.Path)) 
                    { 
                        Write-Host "Restoring Key: $($Item.Path)..." -ForegroundColor Gray
                        New-Item -Path $Item.Path -Force | Out-Null 
                    }
                }
                else
                {
                    if (Test-Path $Item.Path) 
                    { 
                        Write-Host "Removing added Key: $($Item.Path)..." -ForegroundColor Gray
                        Remove-Item -Path $Item.Path -Recurse -Force -ErrorAction SilentlyContinue 
                    }
                }
            }
            else
            {
                # Value-level restoration
                if ($Item.ValExists)
                {
                    Write-Host "Restoring Value: $($Item.Path)\$($Item.Name)..." -ForegroundColor Gray
                    if (-not (Test-Path $Item.Path)) { New-Item -Path $Item.Path -Force | Out-Null }
                    $Type = if ($Item.Type) { $Item.Type } else { "DWord" }
                    Set-ItemProperty -Path $Item.Path -Name $Item.Name -Value $Item.OldValue -Type $Type -Force
                }
                else
                {
                    if (Test-Path $Item.Path)
                    {
                        Write-Host "Removing added Value: $($Item.Path)\$($Item.Name)..." -ForegroundColor Gray
                        Remove-ItemProperty -Path $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        Write-Host "`nRestoration complete." -ForegroundColor Green
    }
}
catch
{
    Write-Host "An unexpected error occurred: $_" -ForegroundColor Red
}
finally
{
    Stop-Transcript
    Write-Host "`nExiting in 5 seconds..."
    Start-Sleep -Seconds 5
}
