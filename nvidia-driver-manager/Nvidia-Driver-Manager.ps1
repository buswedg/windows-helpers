<#
.SYNOPSIS

Downloads and/or installs Nvidia display drivers using PowerShell.

.DESCRIPTION

Downloads and/or installs essential Nvidia display drivers (excluding GeForce and Shadowplay components) using Powershell and 7zip.

.PARAMETER Mode
Specifies the mode of operation ('download-only', 'install-only', or 'download-install', default: 'download-only').

.PARAMETER Folder
Specifies the download and extraction folder (default: `$env:temp`).

.OUTPUTS

Screen output and TransAction log which is available in %Temp%\nvidia-driver-manager.log.

.EXAMPLE

PS> .\Nvidia-Driver-Installer.ps1 -Mode download-install
Downloads and installs the latest Nvidia drivers based on GPU information provided by user.

.LINK

None

#>

[CmdletBinding(DefaultParameterSetName = "All")]
param (
    [ValidateSet('download-only', 'install-only', 'download-install')]
    [string]$Mode = "download-only",
    [string]$Folder = "$env:temp\NVIDIA"
)

#Requires -RunAsAdministrator

Import-Module BitsTransfer

Start-Transcript -Path $ENV:TEMP\nvidia-driver-manager.log

function Get-SelectedGpu {
    $Json = Read-Host "Enter the name of the JSON file (without path) containing GPU information."
    $JsonGpuFilePath = Join-Path $PSScriptRoot "configs\$Json"

    if (-not (Test-Path $JsonGpuFilePath)) {
        Write-Host "The specified JSON file does not exist: $JsonGpuFilePath" -ForegroundColor Red
        exit 1
    }

    $GpuInfo = Get-Content $JsonGpuFilePath | ConvertFrom-Json

    Write-Host "Available GPUs:"
    for ($i = 0; $i -lt $GpuInfo.Gpus.Count; $i++) {
        Write-Host "$($i + 1). $($GpuInfo.Gpus[$i].tag)"
    }

    do {
        $SelectedGpuIndex = Read-Host "Enter the index number of the GPU type to download"
        if (-not ([int]::TryParse($SelectedGpuIndex, [ref]$null)) -or $SelectedGpuIndex -lt 1 -or $SelectedGpuIndex -gt $GpuInfo.Gpus.Count) {
            Write-Host "Invalid selection. Please choose a valid number."
            $InvalidSelection = $true
        }
        else {
            $InvalidSelection = $false
        }
    } while ($InvalidSelection)

    return $GpuInfo.Gpus[$SelectedGpuIndex - 1]
}

function Get-DriverFileForInstallation {
    param (
        [string]$Folder
    )

    if (-not (Test-Path -Path $Folder -PathType Container)) {
        Write-Host ""
        Write-Host "The folder does not exist: $Folder" -ForegroundColor Red
        Write-Host "Press any key to exit..."
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }

    $DriverFiles = Get-ChildItem -Path $Folder -Filter "*.exe"

    if ($DriverFiles.Count -eq 0) {
        Write-Host ""
        Write-Host "No executable files found in the extraction folder." -ForegroundColor Red
        Write-Host "Press any key to exit..."
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }

    Write-Host ""
    Write-Host "Available executable files for installation:"

    for ($i = 0; $i -lt $DriverFiles.Count; $i++) {
        Write-Host "$($i + 1). $($DriverFiles[$i].Name)"
    }

    do {
        $SelectedFileIndex = Read-Host "Enter the index number of the executable to install"

        if (-not ([int]::TryParse($SelectedFileIndex, [ref]$null))) {
            Write-Host "Invalid input. Please enter a valid number."
            $InvalidSelection = $true
        }
        else {
            $SelectedFileIndex = [int]$SelectedFileIndex
            if ($SelectedFileIndex -lt 1 -or $SelectedFileIndex -gt $DriverFiles.Count) {
                Write-Host "Invalid selection. Please choose a valid number."
                $InvalidSelection = $true
            }
            else {
                $InvalidSelection = $false
            }
        }
    } while ($InvalidSelection)

    return $DriverFiles[$SelectedFileIndex - 1]
}

function Get-InstalledDriverVersion {
    Write-Host "Attempting to detect currently installed driver version..."
    try {
        $VideoController = Get-WmiObject -ClassName Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
        if ($VideoController -eq $null) {
            Write-Host "No compatible Nvidia device found."
            return $null
        }
        $InstalledDriverVersion = ($VideoController.DriverVersion.Replace('.', '')[-5..-1] -join '').insert(3, '.')
        return $InstalledDriverVersion
    }
    catch {
        Write-Host ""
        Write-Host -ForegroundColor Yellow "Unable to detect currently installed Nvidia driver."
        return $null
    }
}

function Get-LatestDriverVersion {
    param (
        [string]$Psid,
        [string]$Pfid,
        [string]$Osid
    )

    $Uri = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php" +
        "?func=DriverManualLookup" +
        "&psid=$Psid" +
        "&pfid=$Pfid" +
        "&osID=$Osid" +
        "&languageCode=1033" +
        "&isWHQL=1" +
        "&dch=1" +
        "&sort1=0" +
        "&numberOfResults=1"

    $Response = Invoke-WebRequest -Uri $Uri -Method GET -UseBasicParsing
    $Payload = $Response.Content | ConvertFrom-Json
    return $Payload.IDS[0].downloadInfo.Version
}

function DownloadDriver {
    param (
        [string]$LatestDriverVersion,
        [string]$MachineType,
        [string]$WinVersion,
        [string]$WinArchitecture,
        [string]$DownloadFilePath
    )

    $Url = "https://international.download.nvidia.com/Windows/$LatestDriverVersion/$LatestDriverVersion-$MachineType-$WinVersion-$WinArchitecture-international-dch-whql.exe"
    $RpUrl = "https://international.download.nvidia.com/Windows/$LatestDriverVersion/$LatestDriverVersion-$MachineType-$WinVersion-$WinArchitecture-international-dch-whql-rp.exe"

    Write-Host "Downloading the latest version to $DownloadFilePath"
    Start-BitsTransfer -Source $Url -Destination $DownloadFilePath

    if (-not $?) {
        Write-Host "Download failed, trying alternative RP package now..."
        Start-BitsTransfer -Source $RpUrl -Destination $DownloadFilePath
    }
}

function InstallDriver {
    param (
        [string]$ArchiverProgram,
        [string]$DownloadFilePath,
        [string]$ExtractFolderPath
    )

    Write-Host "Extracting files now..."

    if ((Test-Path $ArchiverProgram) -eq $false) {
        Write-Host "Something went wrong. No archive program detected. This should not happen."
        exit
    }
    
    $FilesToExtract = "Display.Driver HDAudio NVI2 PhysX EULA.txt ListDevices.txt setup.cfg setup.exe"

    Start-Process -FilePath $ArchiverProgram -NoNewWindow -ArgumentList "x -bso0 -bsp1 -bse1 -aoa $DownloadFilePath $FilesToExtract -o""$ExtractFolderPath""" -Wait

    (Get-Content "$ExtractFolderPath\setup.cfg") | Where-Object { $_ -notmatch 'name="\${{(EulaHtmlFile|FunctionalConsentFile|PrivacyPolicyFile)}}' } | Set-Content "$ExtractFolderPath\setup.cfg" -Encoding UTF8 -Force

    Write-Host "Installing Nvidia drivers now..."
    $InstallArgs = "-passive -noreboot -noeula -nofinish -clean -s"
    Start-Process -FilePath "$ExtractFolderPath\setup.exe" -ArgumentList $InstallArgs -Wait

    Write-Host "Deleting downloaded files"
    Remove-Item $ExtractFolderPath -Recurse -Force
}

function Get-7ZipArchiver {
    if ((Test-Path HKLM:\SOFTWARE\7-Zip\) -eq $true) {
        $SevenZipPath = Get-ItemProperty -Path HKLM:\SOFTWARE\7-Zip\ -Name Path
        $SevenZipPath = $SevenZipPath.Path
        $SevenZipPathExe = Join-Path $SevenZipPath "7z.exe"

        if ((Test-Path $SevenZipPathExe) -eq $true) {
            $ArchiverProgram = $SevenZipPathExe
        }
    }
    else {
        Write-Host ""
        Write-Host "Sorry, but it looks like you don't have 7zip installed."
        Write-Host "Press any key to exit..."
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }

    return $ArchiverProgram
}

if ($Mode -eq 'download-only' -or $Mode -eq 'download-install') {
    $SelectedGpu = Get-SelectedGpu
    $LatestDriverVersion = Get-LatestDriverVersion -Psid $SelectedGpu.Psid -Pfid $SelectedGpu.Pfid -Osid $SelectedGpu.Osid
    Write-Output "Latest downloadable driver version: $LatestDriverVersion"
    $InstalledDriverVersion = Get-InstalledDriverVersion
    Write-Output "Installed driver version: $InstalledDriverVersion"

    if ($LatestDriverVersion -eq $InstalledDriverVersion) {
        while ($Choice -notmatch "[y|n]") {
            $Choice = Read-Host "Would you like to download anyway?  (Y/N)"
        }
        if ($Choice -eq "n") {
            Write-Host "Press any key to exit..."
            $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit
        }
    }

    New-Item -Path $Folder -ItemType Directory -ErrorAction SilentlyContinue
    $DownloadFilePath = Join-Path $Folder "$($SelectedGpu.tag)_$LatestDriverVersion.exe"
    DownloadDriver -LatestDriverVersion $LatestDriverVersion -MachineType $SelectedGpu.machinetype -WinVersion $SelectedGpu.winversion -WinArchitecture $SelectedGpu.winarchitecture -DownloadFilePath $DownloadFilePath
    Write-Host -ForegroundColor Green "Driver downloaded."
}

if ($Mode -eq 'install-only' -or $Mode -eq 'download-install') {
    $SelectedFile = Get-DriverFileForInstallation -Folder $Folder
    $ArchiverProgram = Get-7ZipArchiver
    $ExtractFolderPath = Join-Path $Folder $( [System.IO.Path]::GetFileNameWithoutExtension($SelectedFile) )
    $DownloadFilePath = Join-Path $Folder $SelectedFile
    InstallDriver -ArchiverProgram $ArchiverProgram -DownloadFilePath $DownloadFilePath -ExtractFolderPath $ExtractFolderPath
    Write-Host -ForegroundColor Green "Driver installed. You may need to reboot to finish installation."
}

Stop-Transcript

Write-Host "All operations completed."
Write-Host "Exiting script in 5 seconds."; Start-Sleep -Seconds 5
exit
