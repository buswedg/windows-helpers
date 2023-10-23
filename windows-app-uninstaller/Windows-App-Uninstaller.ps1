<#
.SYNOPSIS

Uninstalls applications using PowerShell.

.DESCRIPTION

Uninstalls all applications in the specified JSON file using Powershell.

.PARAMETER Json
Name of the JSON file (without path) containing uninstallation information.

.OUTPUTS

Screen output and TransAction log which is available in %Temp%\windows-app-uninstaller.log.

.EXAMPLE

PS> .\Windows-App-Uninstaller.ps1 -Json "test.json"
Uninstalls all applications in test.json.

.LINK

None

#>

# Parameters
[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Name of the JSON file (without path) containing uninstallation information")]
    [string]$Json
)

#Requires -RunAsAdministrator

Start-Transcript -Path $ENV:TEMP\windows-app-uninstaller.log

Set-ExecutionPolicy Bypass -Force:$True -Confirm:$false -ErrorAction SilentlyContinue
Set-Variable -Name 'ConfirmPreference' -Value 'None' -Scope Global

$ProgressPreference = 'SilentlyContinue'

$JsonFilePath = Join-Path $PSScriptRoot "configs\$Json"

if (-not (Test-Path $JsonFilePath)) {
    Write-Host "The specified JSON file does not exist: $JsonFilePath" -ForegroundColor Red
    exit 1
}

$JsonData = Get-Content $JsonFilePath -Raw | ConvertFrom-Json

Write-Host "Uninstalling Applications..." -ForegroundColor Green
Foreach ($App in $JsonData.Apps) {
    $appPackage = Get-AppxPackage -Name $App -AllUsers -ErrorAction SilentlyContinue
    if ($appPackage -ne $null) {
        Write-Host ("Uninstalling {0}..." -f $App) -ForegroundColor Yellow
        $appPackage | Remove-AppxPackage -Confirm:$false
    } else {
        Write-Host ("{0} is not installed." -f $App) -ForegroundColor Cyan
    }
}

Stop-Transcript

Write-Host "All operations completed."
Write-Host "Exiting script in 5 seconds."; Start-Sleep -Seconds 5
exit
