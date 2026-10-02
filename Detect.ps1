# Intune detection script for Continuum (per-user NSIS install).
#
# Self-contained on purpose: Intune uploads this file alone and runs it from a temp folder,
# so nothing here may depend on Common.ps1 or the kit folder.
#
# Contract (Microsoft): installed = exit 0 AND something on STDOUT. Anything on STDERR means
# not installed, so every failure path below exits 1 silently.
#
# Presence-only on purpose. Continuum self-updates through ToDesktop after the first install,
# so an exact-version rule would flip to "not installed" after each release and make Intune
# kill and reinstall the app daily. Set $MinimumVersion only to express a floor; never pin.

$MinimumVersion = $null   # e.g. '1.3.10'

$ErrorActionPreference = 'Stop'

$Guid = '814ecc71-30fe-5c71-b9c9-65458b992584'
$UninstallSubKey = "Software\Microsoft\Windows\CurrentVersion\Uninstall\$Guid"
$InstallSubKey = "Software\$Guid"
$ExeName = 'Continuum.exe'
$FolderName = 'continuum-electron'
$LocalSystemSid = 'S-1-5-18'

try {
    # Intune evaluates detection as SYSTEM first and may repeat it as the user. Resolve the
    # signed-in user's SID either way so both passes read the same hive.
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($sid -eq $LocalSystemSid) {
        $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" | Select-Object -First 1
        if ($null -eq $explorer) {
            exit 1
        }
        $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwnerSid
        if ($null -eq $owner -or $owner.ReturnValue -ne 0) {
            exit 1
        }
        $sid = $owner.Sid
    }

    $hiveRoot = "Registry::HKEY_USERS\$sid"
    if (-not (Test-Path -Path $hiveRoot)) {
        exit 1
    }

    $uninstall = Get-ItemProperty -Path "$hiveRoot\$UninstallSubKey" -ErrorAction SilentlyContinue
    if ($null -eq $uninstall) {
        exit 1
    }

    $installLocation = (Get-ItemProperty -Path "$hiveRoot\$InstallSubKey" -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
    if ([string]::IsNullOrWhiteSpace($installLocation)) {
        $profilePath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if ([string]::IsNullOrWhiteSpace($profilePath)) {
            exit 1
        }
        $installLocation = Join-Path $profilePath "AppData\Local\Programs\$FolderName"
    }

    if (-not (Test-Path -Path (Join-Path $installLocation $ExeName) -PathType Leaf)) {
        exit 1
    }

    $version = [string]$uninstall.DisplayVersion
    if (-not [string]::IsNullOrWhiteSpace($MinimumVersion)) {
        $installed = [version]($version -replace '[^0-9.].*$', '')
        if ($installed -lt [version]$MinimumVersion) {
            exit 1
        }
    }

    Write-Output "Continuum $version installed at $installLocation"
    exit 0
}
catch {
    exit 1
}
