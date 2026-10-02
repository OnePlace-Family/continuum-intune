# Intune install script for Continuum (per-user NSIS install).
#
# Semantics: install only when Continuum is absent for this user. Never upgrade, never
# downgrade, never reinstall. ToDesktop owns updates after the first install. Re-running the
# NSIS installer over an existing install kills the running app and reinstalls, which is
# exactly what this script exists to prevent.
#
# Must run in the user's context (Intune install behavior: User). Running as SYSTEM would
# install into the system profile, so that case fails fast.
#
# Exit codes: 0 success or already installed; the NSIS exit code when the installer fails
# (2 on its abort paths); 1 for script-level errors.

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"
$log = Get-KitLogPath -Name 'install.log'

try {
    if (Test-RunningAsSystem) {
        Write-KitLog $log 'Refusing to run as SYSTEM. Set the Intune install behavior to User.'
        exit 1
    }

    $sid = Get-CurrentSid
    $existing = Get-ContinuumInstall -Sid $sid
    if ($null -ne $existing) {
        Write-KitLog $log "Already installed: Continuum $($existing.Version) at $($existing.InstallLocation). Nothing to do."
        exit 0
    }

    $installers = @(Get-ChildItem -Path $PSScriptRoot -Filter 'Continuum Setup*.exe' -File)
    if ($installers.Count -ne 1) {
        Write-KitLog $log "Expected exactly one 'Continuum Setup*.exe' next to this script, found $($installers.Count)."
        exit 1
    }
    $installer = $installers[0]

    Write-KitLog $log "Running '$($installer.Name)' /S for user SID $sid"
    $process = Start-Process -FilePath $installer.FullName -ArgumentList '/S' -Wait -PassThru
    $code = $process.ExitCode
    Write-KitLog $log "Installer exit code $code"

    if ($code -ne 0) {
        exit $code
    }

    $installed = Get-ContinuumInstall -Sid $sid
    if ($null -eq $installed) {
        Write-KitLog $log 'Installer returned 0 but no install was found afterwards.'
        exit 1
    }

    Write-KitLog $log "Installed Continuum $($installed.Version) at $($installed.InstallLocation)"
    exit 0
}
catch {
    Write-KitLog $log "Error: $($_.Exception.Message)"
    exit 1
}
