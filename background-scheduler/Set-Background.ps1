<#
.SYNOPSIS
Sets the desktop background based on time-of-day triggers.

.DESCRIPTION
Manages wallpapers via time-of-day triggers defined in a JSON file.

.PARAMETER Triggers
Path to the JSON file containing background triggers.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$Triggers
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
    $TriggersPath = [System.IO.Path]::GetFullPath($Triggers)
    $NormalizedTriggers = Get-NormalizedTriggers -ConfigFilePath $TriggersPath
    
    if ($null -eq $NormalizedTriggers) { return }

    # Determine active trigger based on time
    $Now = (Get-Date).TimeOfDay
    $ActiveTrigger = $null
    
    $SortedTriggers = $NormalizedTriggers | ForEach-Object { 
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

    # Handle wrap-around for late night triggers
    if ($null -eq $ActiveTrigger)
    {
        $ActiveTrigger = $SortedTriggers[-1]
    }

    if ($ActiveTrigger -and (Test-Path $ActiveTrigger.path))
    {
        Set-Wallpaper -Path $ActiveTrigger.path
    }
}
catch
{
    Write-Error "Applier Error: $_"
}
