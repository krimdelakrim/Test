[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$RepairSystemFiles,
    [switch]$ForceReinstall,
    [string]$DownloadDirectory = "$env:TEMP",
    [switch]$SilentInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp][$Level] $Message"
}

function Get-ReleaseMap {
    return [ordered]@{
        378389 = '4.5'
        378675 = '4.5.1'
        378758 = '4.5.1'
        379893 = '4.5.2'
        393295 = '4.6'
        393297 = '4.6'
        394254 = '4.6.1'
        394271 = '4.6.1'
        394802 = '4.6.2'
        394806 = '4.6.2'
        460798 = '4.7'
        460805 = '4.7'
        461308 = '4.7.1'
        461310 = '4.7.1'
        461808 = '4.7.2'
        461814 = '4.7.2'
        528040 = '4.8 (Win 10 May 2019+)'
        528049 = '4.8 (Win 10 May 2019+)'
        528372 = '4.8.1 (Win 11 22H2)'
        533320 = '4.8.1 (Win 11 23H2)'
    }
}

function Get-DotNetReleaseInfo {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    try {
        $item = Get-ItemProperty -Path $regPath -ErrorAction Stop
        [pscustomobject]@{
            Release = [int]$item.Release
            Version = $item.Version
            Install = $item.Install
        }
    }
    catch {
        Write-Log "Unable to find registry key $regPath. .NET Framework 4.x Full likely not installed." 'WARN'
        return $null
    }
}

function Resolve-DotNetVersion {
    param([int]$Release)

    if (-not $Release) { return $null }

    $map = Get-ReleaseMap
    $matchingKey = $map.Keys | Sort-Object -Descending | Where-Object { $_ -le $Release } | Select-Object -First 1
    if ($null -ne $matchingKey) {
        return $map[$matchingKey]
    }
    return $null
}

function Get-DotNetStatus {
    $info = Get-DotNetReleaseInfo
    if ($null -eq $info) {
        return [pscustomobject]@{
            Installed = $false
            Release = $null
            ReportedVersion = $null
            ResolvedVersion = $null
        }
    }

    $resolved = Resolve-DotNetVersion -Release $info.Release
    [pscustomobject]@{
        Installed = ($info.Install -eq 1)
        Release = $info.Release
        ReportedVersion = $info.Version
        ResolvedVersion = $resolved
    }
}

function Invoke-DotNetRepair {
    param(
        [switch]$IncludeSfc
    )

    Write-Log 'Starting optional .NET repair steps. This may take a while.'
    if ($IncludeSfc) {
        Write-Log 'Running System File Checker (sfc /scannow).' 'INFO'
        Start-Process -FilePath 'sfc.exe' -ArgumentList '/scannow' -Verb RunAs -Wait
    }

    Write-Log 'Running Deployment Image Servicing and Management (DISM) restore health.' 'INFO'
    Start-Process -FilePath 'dism.exe' -ArgumentList '/Online','/Cleanup-Image','/RestoreHealth' -Verb RunAs -Wait

    Write-Log 'Re-registering .NET framework with Windows optional features.' 'INFO'
    Start-Process -FilePath 'dism.exe' -ArgumentList '/Online','/Enable-Feature','/FeatureName:NetFx4','/All','/NoRestart' -Verb RunAs -Wait
}

function Get-InstallerPath {
    param([string]$Directory)
    if (-not (Test-Path -Path $Directory)) {
        Write-Log "Creating download directory $Directory" 'INFO'
        New-Item -Path $Directory -ItemType Directory -Force | Out-Null
    }
    return (Join-Path -Path $Directory -ChildPath 'ndp48-web.exe')
}

function Download-DotNetInstaller {
    param(
        [string]$Destination
    )

    $uri = 'https://download.microsoft.com/download/6/5/2/65267708-5B79-4E05-B4F4-5E2E3A1B576B/ndp48-web.exe'
    Write-Log "Downloading .NET Framework 4.8 installer from $uri" 'INFO'
    try {
        Invoke-WebRequest -Uri $uri -OutFile $Destination -UseBasicParsing
    }
    catch {
        Write-Log "Primary download failed: $($_.Exception.Message). Retrying with BITS." 'WARN'
        Start-BitsTransfer -Source $uri -Destination $Destination -RetryInterval 60 -RetryTimeout 600
    }
}

function Install-DotNetFramework {
    param(
        [string]$Installer,
        [switch]$Silent
    )

    if (-not (Test-Path -Path $Installer)) {
        throw "Installer '$Installer' not found."
    }

    $arguments = if ($Silent) { '/q /norestart' } else { '/passive /norestart' }
    Write-Log "Launching .NET Framework installer $Installer with arguments '$arguments'" 'INFO'
    Start-Process -FilePath $Installer -ArgumentList $arguments -Verb RunAs -Wait
}

function Ensure-DotNet48 {
    param(
        [switch]$Force,
        [switch]$Silent,
        [string]$DownloadDirectory
    )

    $status = Get-DotNetStatus
    if ($status.Installed -and -not $Force) {
        if ($status.Release -ge 528040) {
            Write-Log ".NET Framework 4.8 or later already installed (release $($status.Release), version '$($status.ResolvedVersion)')." 'INFO'
            return
        }
        else {
            Write-Log "Detected .NET release $($status.Release) ('$($status.ResolvedVersion)'), will upgrade to 4.8." 'INFO'
        }
    }
    elseif (-not $status.Installed) {
        Write-Log '.NET Framework 4.x Full not detected. Installing 4.8 now.' 'INFO'
    }
    else {
        Write-Log 'Force flag specified. Reinstalling .NET Framework 4.8.' 'INFO'
    }

    $installerPath = Get-InstallerPath -Directory $DownloadDirectory
    Download-DotNetInstaller -Destination $installerPath
    Install-DotNetFramework -Installer $installerPath -Silent:$Silent
}

Write-Log 'Evaluating .NET Framework 4.x installation status.'
$status = Get-DotNetStatus
if ($status.Installed) {
    Write-Log "Current release key: $($status.Release). Reported version: $($status.ReportedVersion). Resolved version: $($status.ResolvedVersion)." 'INFO'
}
else {
    Write-Log 'No installed .NET Framework 4.x Full detected.' 'WARN'
}

Ensure-DotNet48 -Force:$ForceReinstall -Silent:$SilentInstall -DownloadDirectory $DownloadDirectory

if ($RepairSystemFiles) {
    Invoke-DotNetRepair -IncludeSfc
}

Write-Log 'Script completed. Restart Windows to finalize the installation if prompted.' 'INFO'
