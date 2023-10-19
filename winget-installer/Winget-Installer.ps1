<#
.SYNOPSIS

Installs applications using Winget and PowerShell.

.DESCRIPTION

Installs all packages from the specified .json file.

.PARAMETER json
Name of the JSON file (without path) containing the installation information.

.OUTPUTS

Screen output and TransAction log which is available in %Temp%\winget-installer.log.

.EXAMPLE

PS> Winget-Installer.ps1 -Json "test.json"
Installs all applications in test.json.

.LINK

None

#>

# Parameters
[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Name of the JSON file (without path) containing installation information")]
    [string]$json
)

#Requires -RunAsAdministrator

Start-Transcript -Path $ENV:TEMP\winget-installer.log

Set-ExecutionPolicy Bypass -Force:$True -Confirm:$false -ErrorAction SilentlyContinue
Set-Variable -Name 'ConfirmPreference' -Value 'None' -Scope Global

$ProgressPreference = 'SilentlyContinue'

$JsonFilePath = Join-Path $PSScriptRoot "configs\$json"

if (-not (Test-Path $JsonFilePath)) {
    Write-Host "The specified JSON file does not exist: $JsonFilePath" -ForegroundColor Red
    exit 1
}

$JsonData = Get-Content $JsonFilePath -Raw | ConvertFrom-Json

if (!(Get-AppxPackage -Name Microsoft.Winget.Source)) {
    Write-Host ("Winget was not found and installing now") -ForegroundColor Yellow
    Invoke-Webrequest -uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -Outfile $ENV:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx
    Invoke-Webrequest -uri https://aka.ms/getwinget -Outfile $ENV:TEMP\winget.msixbundle    
    Add-AppxPackage $ENV:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx -ErrorAction SilentlyContinue
    Add-AppxPackage -Path $ENV:TEMP\winget.msixbundle -ErrorAction SilentlyContinue
}

Write-Host ("Installing Applications but skipping install if already present") -ForegroundColor Green
Foreach ($App in $JsonData.Apps) {
    Write-Host ("Checking if {0} is already installed..." -f $App)
    winget.exe list --id $App --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq '-1978335212') {
        Write-Host ("{0} was not found and installing now" -f $App.Split('.')[1]) -ForegroundColor Yellow
        winget.exe install $App --silent --force --source winget --accept-package-agreements --accept-source-agreements
        Foreach ($Application in $JsonData.ProcessesToKill) {
            get-process $Application -ErrorAction SilentlyContinue | Stop-Process -Force:$True -Confirm:$false
        }
    } 
}

Remove-Item $ENV:TEMP\Winget -Recurse -Force:$True -ErrorAction:SilentlyContinue

Foreach ($File in $JsonData.FilesToClean) {
    Write-Host ("Cleaning {0} from Windows Desktop" -f $File) -ForegroundColor Green
    $UserDesktop = ([Environment]::GetFolderPath("Desktop"))
    Get-ChildItem C:\users\public\Desktop\$File -ErrorAction SilentlyContinue | Where-Object LastWriteDate -LE ((Get-Date).AddHours( - 1)) | Remove-Item -Force:$True
    Get-ChildItem $UserDesktop\$File -ErrorAction SilentlyContinue | Where-Object LastWriteDate -LE ((Get-Date).AddHours( - 1)) | Remove-Item -Force:$True
    Get-ChildItem C:\users\public\Desktop\$File -Hidden -ErrorAction SilentlyContinue | Where-Object LastWriteDate -LE ((Get-Date).AddHours( - 1)) | Remove-Item -Force:$True
    Get-ChildItem $UserDesktop\$File -Hidden -ErrorAction SilentlyContinue | Where-Object LastWriteDate -LE ((Get-Date).AddHours( - 1)) | Remove-Item -Force:$True
}

Stop-Transcript