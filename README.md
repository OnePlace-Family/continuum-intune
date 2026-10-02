# Continuum for Microsoft Intune

Deploys the [Continuum](https://www.oncontinuum.com) Windows desktop app through Microsoft Intune as a Win32 app. Intune installs Continuum once for the signed-in user. After that, Continuum keeps itself up to date, so you do not repackage or redeploy for routine releases.

Each [release](../../releases/latest) on this repository corresponds to one Continuum version and contains everything to upload: a package per architecture, the detection script, and a manifest with hashes.

## What to download

From the [latest release](../../releases/latest):

| File | Use |
|---|---|
| `Continuum-<version>-x64.intunewin` | App package for x64 devices |
| `Continuum-<version>-arm64.intunewin` | App package for ARM64 devices |
| `Detect.ps1` | Custom detection script, the same for both |
| `kit-manifest-<arch>.txt` | Hashes and the two command lines to paste into Intune |

Verify before uploading:

```powershell
Get-FileHash .\Continuum-<version>-x64.intunewin        # must match the SHA-256 in the release notes
gh attestation verify .\Continuum-<version>-x64.intunewin --owner OnePlace-Family   # optional, needs GitHub CLI
```

Download only the architectures you manage. Devices get the build for their own processor, so there is no reason to upload a package to tenants that have no ARM64 hardware.

## Intune app settings

Create one **Windows app (Win32)** per architecture. Everything is identical between the two except the package file and the architecture requirement. Step by step with screenshots-level detail: [docs/INTUNE-SETUP.md](docs/INTUNE-SETUP.md).

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Continuum-<version>-x64.intunewin` or `Continuum-<version>-arm64.intunewin` |
| Name | `Continuum` (suggest `Continuum (ARM64)` for the second app) |
| Publisher | `OnePlace Company Inc.` |
| Install command | `%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install.ps1` |
| Uninstall command | `%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall.ps1` |
| Install behavior | **User** |
| Device restart behavior | No specific action |
| Return codes | `0` Success, `1` Failed, `2` Failed. Keep the defaults for 1707, 3010, 1641, 1618. |
| Operating system architecture | **x64** for the x64 package, **ARM64** for the arm64 package |
| Minimum operating system | The lowest Windows 10 option offered |
| Detection rules | Use a custom detection script: `Detect.ps1`. Run script as 32-bit process: No. Enforce script signature check: No. |
| Dependencies, Supersedence | None |
| Assignment | **Required** to a user group. **Available for enrolled devices** also works for self-service through Company Portal. |

The `Sysnative` path matters: the Intune agent is a 32-bit process and a bare `powershell.exe` would start a 32-bit host.

## How updates work

- The installer is Continuum's standard one-click, per-user installer. It never elevates, and its updater runs unelevated, so standard users receive updates silently.
- `Install.ps1` installs only when Continuum is absent for the signed-in user and exits 0 otherwise. `Detect.ps1` checks that Continuum is present, not which version. Together they keep Intune from re-offering the app after Continuum has updated itself.
- When a new Continuum version appears as a release here, you do not need to replace the package in Intune. Doing so only changes the version that new devices start on before their first self-update.
- Do not add a version-equals detection rule. Intune re-offers a Required app when detection fails, and re-running this installer closes a running Continuum. An exact-version rule would do that to users after every update.

## Limits

- Devices must be Microsoft Entra joined or hybrid joined. Devices that are only Entra registered (personal devices) must run Win32 apps in System context, which this kit refuses because the install belongs to the user.
- User-context apps cannot be Enrollment Status Page blocking apps. Deploy after enrollment.
- IT does not choose which version users run; Continuum's updater does.
- Network: devices need `download.todesktop.com` and `dl.todesktop.com` for updates.

## Logs and identity on a device

- Kit scripts: `%LOCALAPPDATA%\ContinuumIntuneKit\install.log` and `uninstall.log`.
- Intune agent: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` and `AppWorkload.log`.
- Install folder: `%LOCALAPPDATA%\Programs\continuum-electron\`.
- Registry: `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\814ecc71-30fe-5c71-b9c9-65458b992584`.

Problems: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md), then open an [issue](../../issues/new/choose) with the kit logs.

## Build it yourself

If your policy requires packaging from the vendor's installer on your own machine:

```powershell
git clone https://github.com/OnePlace-Family/continuum-intune.git
cd continuum-intune
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Build-Kit.ps1 -Arch x64        # or arm64, or universal for one package carrying both
```

`Build-Kit.ps1` downloads the current installer from ToDesktop and checks its SHA-512 against the published manifest and its Authenticode signature (`OnePlace Company Inc.`), downloads Microsoft's Win32 Content Prep Tool from a pinned commit and checks its SHA-256 and signature, then packages the installer with the scripts in `payload/`. Output lands in `build\out\`.

The `.intunewin` container is encrypted with a key generated per build, so your package will not have the same hash as ours. The installer inside it and `Detect.ps1` will.

## Repository layout

| Path | Role |
|---|---|
| `payload/` | `Install.ps1`, `Uninstall.ps1`, `Common.ps1`: the files inside the package that run on devices |
| `Detect.ps1` | Custom detection script, uploaded to Intune separately; self-contained on purpose |
| `Build-Kit.ps1`, `Get-Installer.ps1` | Packaging tooling |
| `tests/` | Constants drift check, package structure check, and the smoke test CI runs on clean Windows runners |
| `tools/New-ReleaseNotes.ps1` | Renders release notes from the build manifests |
| `.github/workflows/publish.yml` | Weekly check of ToDesktop's feed; builds, tests and publishes a release for each new Continuum version |
| `docs/` | Setup, troubleshooting, maintenance |

Licensed under the [MIT License](LICENSE). The license covers the files in this repository; the Continuum name and logo are trademarks of OnePlace Company Inc. and are not covered by it.
