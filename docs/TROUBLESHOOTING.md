# Troubleshooting

Start with the two logs on the device:

- Kit: `%LOCALAPPDATA%\ContinuumIntuneKit\install.log` and `uninstall.log` (signed-in user's profile).
- Intune agent: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log`. Search for `Continuum`, `detection state`, and `lpExitCode`.

## Symptoms

| Symptom | Cause and fix |
|---|---|
| Admin center shows Failed with `0x87D1041C` | The install ran but detection said "not installed". Run `Detect.ps1` by hand as the user: it must print `Continuum <version> installed at ...` and exit 0. If it prints nothing, check that `Continuum.exe` exists under `%LOCALAPPDATA%\Programs\continuum-electron\` and that the uninstall registry key below exists. |
| Admin center shows "Not applicable" | The architecture requirement does not match the device. Since June 2025 an x64 requirement no longer includes ARM64 devices; create the ARM64 app for those. |
| `install.log` says "Refusing to run as SYSTEM" | Install behavior is set to System. Change it to User. |
| Install never starts | In `AppWorkload.log` confirm the device shows the user as primary user and that the assignment targets a group containing that user. User-context apps install only while that user is signed in. |
| Installer exit code 2 | The installer aborted. Usually an older copy's uninstaller failed. Look at the state of `%LOCALAPPDATA%\Programs\continuum-electron\`, remove the folder, and sync again. |
| Install ran but Intune recorded exit code `3221225786` (0xC000013A) | The install script process was terminated while the installer ran. Seen once when an orphaned Continuum copy (files present, registry key missing) was replaced in place; detection then succeeded and Intune reported Installed. Not reproducible on clean installs. If it recurs, remove `%LOCALAPPDATA%\Programs\continuum-electron\` and sync. |
| Admin center never updates | Reporting lags the device by fifteen minutes to an hour. Trust the registry check and wait. |
| Assignment changed from Uninstall back to Required but nothing happens | The agent does not re-evaluate an app it has already processed in the current interval. Wait for the interval, or force it: as an administrator on the device, delete `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\<user GUID>` and run `Restart-Service IntuneManagementExtension`. The agent rebuilds that key on the next check-in. |
| App was uninstalled by Intune but reappears | The group is still in a Required assignment, possibly a second one. Check every assignment on the app. |
| Users are prompted for elevation | Not expected: the installer and updater never elevate. Check that the device policy does not run the app from a location other than the user's profile. |

## Identity of an install

- Registry: `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\814ecc71-30fe-5c71-b9c9-65458b992584` with `DisplayVersion` and `QuietUninstallString`.
- Folder: `%LOCALAPPDATA%\Programs\continuum-electron\Continuum.exe`.
- Both belong to the user who installed it. Another user on the same device gets their own copy.

## Running the scripts by hand

As the user, from a folder containing the extracted payload and the installer (or from a clone of this repository after `.\Build-Kit.ps1`, using `build\source` and `build\out\Detect.ps1`):

```powershell
.\Detect.ps1; $LASTEXITCODE       # 1 before install
.\Install.ps1; $LASTEXITCODE      # 0
.\Detect.ps1; $LASTEXITCODE       # 0 and prints the version
.\Install.ps1; $LASTEXITCODE      # 0, "Already installed"
.\Uninstall.ps1; $LASTEXITCODE    # 0
.\Detect.ps1; $LASTEXITCODE       # 1
```

To see what Intune's SYSTEM-context detection sees, run `Detect.ps1` as SYSTEM with Sysinternals PsExec while the user is signed in: `psexec -s -i powershell -NoProfile -ExecutionPolicy Bypass -File Detect.ps1`. It resolves the signed-in user through `explorer.exe` and reads that user's registry hive.

## Reporting a problem

Open an [issue](../../issues/new/choose) with the release version, the architecture, the Windows build, the device join type, the admin center status, and both kit logs.
