# Intune uninstall script for Continuum (per-user NSIS install).
#
# Intune does not expand environment variables in the uninstall command, so this script
# reads the uninstaller location from the user's registry instead of hard-coding a path.
# The NSIS uninstaller closes a running Continuum before removing files. User data under
# %APPDATA% is kept, matching what the installer's own upgrade path does.
#
# Exit codes: 0 when nothing is installed or removal succeeded; the uninstaller's exit code
# when it fails; 1 for script-level errors.

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"
$log = Get-KitLogPath -Name 'uninstall.log'

try {
    if (Test-RunningAsSystem) {
        Write-KitLog $log 'Refusing to run as SYSTEM. Set the Intune install behavior to User.'
        exit 1
    }

    $sid = Get-CurrentSid
    $install = Get-ContinuumInstall -Sid $sid
    if ($null -eq $install) {
        Write-KitLog $log 'Continuum is not installed for this user. Nothing to do.'
        exit 0
    }

    $uninstaller = Join-Path $install.InstallLocation $script:ContinuumUninstallerName
    if (-not (Test-Path -Path $uninstaller -PathType Leaf)) {
        Write-KitLog $log "Uninstaller not found at '$uninstaller'."
        exit 1
    }

    # _?= makes the NSIS uninstaller run in place instead of from a temp copy, so -Wait
    # returns its real exit code. The trade-off is that it cannot delete itself; cleaned up below.
    $arguments = "/S /currentuser _?=$($install.InstallLocation)"
    Write-KitLog $log "Running '$uninstaller' $arguments"
    $process = Start-Process -FilePath $uninstaller -ArgumentList $arguments -Wait -PassThru
    $code = $process.ExitCode
    Write-KitLog $log "Uninstaller exit code $code"
    if ($code -ne 0) {
        exit $code
    }

    Remove-Item -Path $uninstaller -Force -ErrorAction SilentlyContinue
    if ((Test-Path -Path $install.InstallLocation) -and -not (Get-ChildItem -Path $install.InstallLocation -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $install.InstallLocation -Force -ErrorAction SilentlyContinue
    }

    if ($null -ne (Get-ContinuumInstall -Sid $sid)) {
        Write-KitLog $log 'Uninstaller returned 0 but the install is still present.'
        exit 1
    }

    Write-KitLog $log 'Continuum removed.'
    exit 0
}
catch {
    Write-KitLog $log "Error: $($_.Exception.Message)"
    exit 1
}
