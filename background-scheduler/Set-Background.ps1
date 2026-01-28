<#
.SYNOPSIS
Sets the desktop background based on time-of-day triggers.

.DESCRIPTION
Manages wallpapers via time-of-day triggers defined in a JSON file.

.PARAMETER Json
Path to the JSON file containing background triggers.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$Json
)

# --- Function Definitions ---

function Get-ConfigData
{
    param ([string]$Path)
    if (-not (Test-Path $Path))
    {
        return $null
    }
    try
    {
        return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch
    {
        return $null
    }
}

function Resolve-RelativePath
{
    param ([string]$BasePath, [string]$RelativePath)
    if ([System.IO.Path]::IsPathRooted($RelativePath))
    {
        return $RelativePath
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $RelativePath))
}

function Get-NormalizedTriggers
{
    param ([string]$ConfigFilePath)
    $ConfigDir = Split-Path $ConfigFilePath -Parent
    $Data = Get-ConfigData -Path $ConfigFilePath
    if ($null -eq $Data) { return $null }

    $Triggers = $null
    if ($Data.triggers -is [System.Collections.IEnumerable] -and $Data.triggers -isnot [string])
    { 
        $Triggers = $Data.triggers 
    }
    elseif ($Data -is [array])
    {
        $Triggers = $Data
    }

    if ($Triggers)
    {
        $Normalized = foreach ($T in $Triggers)
        {
            $ImgPath = if ($T.path)
            {
                $T.path
            }
            else
            {
                $T.image
            }
            if ($ImgPath)
            {
                [PSCustomObject]@{
                    time = $T.time
                    path = Resolve-RelativePath -BasePath $ConfigDir -RelativePath $ImgPath
                }
            }
        }
        return $Normalized
    }
    return $null
}

function Set-Wallpaper
{
    param ([string]$Path)
    $Code = @'
using System;
using System.Runtime.InteropServices;
public class Background {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    public static void Set(string path) {
        SystemParametersInfo(0x0014, 0, path, 0x01 | 0x02);
    }
}
'@
    try { Add-Type -TypeDefinition $Code -ErrorAction SilentlyContinue } catch {}
    [Background]::Set($Path)
}

# --- Main Execution ---

try
{
    $ConfigPath = [System.IO.Path]::GetFullPath($Json)
    $Triggers = Get-NormalizedTriggers -ConfigFilePath $ConfigPath
    
    if ($null -eq $Triggers) { return }

    # Determine Correct Background (Time-based)
    $Now = (Get-Date).TimeOfDay
    $ActiveTrigger = $null
    
    $SortedTriggers = $Triggers | ForEach-Object { 
        $_ | Select-Object path, @{
            n = 'time'
            e = { [TimeSpan]::Parse($_.time) }
        } 
    } | Sort-Object time

    foreach ($Trigger in $SortedTriggers)
    {
        if ($Now -ge $Trigger.time)
        {
            $ActiveTrigger = $Trigger
        }
    }

    # Wrap around logic
    if ($null -eq $ActiveTrigger)
    {
        $ActiveTrigger = $SortedTriggers[-1]
    }

    if ($ActiveTrigger -and (Test-Path $ActiveTrigger.path))
    {
        Write-Host "Setting wallpaper: $($ActiveTrigger.path) (Trigger: $($ActiveTrigger.time))" -ForegroundColor Green
        Set-Wallpaper -Path $ActiveTrigger.path
    }
}
catch
{
    Write-Error "Applier Error: $_"
}
