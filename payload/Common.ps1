# Shared constants and helpers for Install.ps1 and Uninstall.ps1, which run from the
# extracted .intunewin folder. Detect.ps1 is uploaded to Intune on its own and therefore
# duplicates what it needs instead of dot-sourcing this file.
#
# Identity of Continuum's per-user NSIS install: uninstall GUID, exe and folder names.

$script:ContinuumGuid = '814ecc71-30fe-5c71-b9c9-65458b992584'
$script:ContinuumUninstallSubKey = "Software\Microsoft\Windows\CurrentVersion\Uninstall\$script:ContinuumGuid"
$script:ContinuumInstallSubKey = "Software\$script:ContinuumGuid"
$script:ContinuumExeName = 'Continuum.exe'
$script:ContinuumFolderName = 'continuum-electron'
$script:ContinuumUninstallerName = 'Uninstall Continuum.exe'
$script:LocalSystemSid = 'S-1-5-18'

function Get-CurrentSid {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Test-RunningAsSystem {
    (Get-CurrentSid) -eq $script:LocalSystemSid
}

function Get-ConsoleUserSid {
    # Owner of the first explorer.exe is the interactively signed-in user. Works for local,
    # domain and Entra accounts without needing NTAccount translation.
    $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $explorer) {
        return $null
    }
    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid -ErrorAction SilentlyContinue
    if ($null -eq $owner -or $owner.ReturnValue -ne 0) {
        return $null
    }
    $owner.Sid
}

function Get-TargetUserSid {
    # Intune runs detection as SYSTEM first and may re-run it as the user. Resolve the user
    # either way so both passes read the same hive.
    if (Test-RunningAsSystem) {
        return Get-ConsoleUserSid
    }
    Get-CurrentSid
}

function Get-ProfilePathForSid {
    param([Parameter(Mandatory)][string]$Sid)
    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid"
    (Get-ItemProperty -Path $key -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
}

function Get-ContinuumInstall {
    # Returns $null when not installed, otherwise an object with Version, InstallLocation,
    # ExePath, QuietUninstallString.
    param([Parameter(Mandatory)][string]$Sid)

    $hiveRoot = "Registry::HKEY_USERS\$Sid"
    if (-not (Test-Path -Path $hiveRoot)) {
        return $null
    }

    $uninstall = Get-ItemProperty -Path "$hiveRoot\$script:ContinuumUninstallSubKey" -ErrorAction SilentlyContinue
    if ($null -eq $uninstall) {
        return $null
    }

    $installLocation = (Get-ItemProperty -Path "$hiveRoot\$script:ContinuumInstallSubKey" -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
    if ([string]::IsNullOrWhiteSpace($installLocation)) {
        $profilePath = Get-ProfilePathForSid -Sid $Sid
        if ([string]::IsNullOrWhiteSpace($profilePath)) {
            return $null
        }
        $installLocation = Join-Path $profilePath "AppData\Local\Programs\$script:ContinuumFolderName"
    }

    $exePath = Join-Path $installLocation $script:ContinuumExeName
    if (-not (Test-Path -Path $exePath -PathType Leaf)) {
        return $null
    }

    [pscustomobject]@{
        Version              = [string]$uninstall.DisplayVersion
        InstallLocation      = $installLocation
        ExePath              = $exePath
        QuietUninstallString = [string]$uninstall.QuietUninstallString
    }
}

function Get-KitLogPath {
    param([Parameter(Mandatory)][string]$Name)
    $dir = Join-Path $env:LOCALAPPDATA 'ContinuumIntuneKit'
    if (-not (Test-Path -Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    Join-Path $dir $Name
}

function Write-KitLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Message
    )
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $line
}
