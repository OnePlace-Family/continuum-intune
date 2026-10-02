# Deploying Continuum through Intune

Written for the Intune administrator setting Continuum up for the first time. Budget about thirty minutes for the admin center work and one sync on a test device.

## Prerequisites

- An Intune tenant with MDM authority set to Intune.
- Test devices that are Microsoft Entra joined or hybrid joined and enrolled in Intune. On the device, `dsregcmd /status` shows `AzureAdJoined : YES` and an `MdmUrl`. Entra-registered personal devices are not supported, see the README.
- A licensed test user who signs in to the device.
- The files from the [latest release](../../releases/latest): the package for each architecture you manage, `Detect.ps1`, and the manifest.

## 1. Create a pilot group

Groups → New group. Type **Security**, name `Continuum Pilot`, membership **Assigned**. Add the test user. Assign Continuum to users, not devices: the install is per user and runs in the user's context.

## 2. Create the x64 app

Apps → Windows → Add → App type **Windows app (Win32)** → Select.

| Page | Fill in |
|---|---|
| App information | Select app package file: `Continuum-<version>-x64.intunewin`. Name `Continuum`. Publisher `OnePlace Company Inc.`. App version: the version from `kit-manifest-x64.txt`. Optional: logo, information URL `https://www.oncontinuum.com`. |
| Program | Install command and Uninstall command: copy both lines from `kit-manifest-x64.txt`. Install behavior **User**. Device restart behavior **No specific action**. Return codes: add `1` Failed and `2` Failed, keep the rest. |
| Requirements | Operating system architecture **x64** only. Minimum operating system: lowest option. |
| Detection rules | Rules format **Use a custom detection script**. Script file: `Detect.ps1`. Run script as 32-bit process on 64-bit clients: **No**. Enforce script signature check and run script silently: **No**. |
| Dependencies, Supersedence | None. |
| Assignments | Required → Add group → `Continuum Pilot`. |
| Review + create | Create. The upload takes a minute or two. |

## 3. Create the ARM64 app

Only if you manage ARM64 devices. Repeat step 2 with these differences:

- Package file: `Continuum-<version>-arm64.intunewin`.
- Name: `Continuum (ARM64)`, so the two are distinguishable in reports.
- Requirements → Operating system architecture: **ARM64** only.

Same commands, same `Detect.ps1`, same assignment. Intune evaluates the architecture requirement first, so a device only ever installs the app that matches its processor.

## 4. Trigger the install on the test device

Sign in to the device as the test user. Intune checks in on its own schedule; to force it, open Settings → Accounts → Access work or school → the work account → Info → **Sync**, or from an elevated PowerShell:

```powershell
Restart-Service -Name IntuneManagementExtension
```

Within a few minutes Continuum installs silently. It does not launch by itself. Verify on the device:

```powershell
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\814ecc71-30fe-5c71-b9c9-65458b992584" /v DisplayVersion
Test-Path "$env:LOCALAPPDATA\Programs\continuum-electron\Continuum.exe"
Get-Content "$env:LOCALAPPDATA\ContinuumIntuneKit\install.log"
```

Expected: the version you packaged, `True`, and a log with one "Running 'Continuum Setup ...'" line, "Installer exit code 0" and "Installed Continuum ...".

In the admin center, Apps → Windows → Continuum → **Device install status** shows Installed after the device's next report. Reporting lags the device by fifteen minutes to an hour.

## 5. What to check over the following days

| Check | How | Pass |
|---|---|---|
| No prompt for the user | Watch during step 4 | Nothing appears on screen |
| Detection is stable | Sync again the next day | `install.log` has no new "Running" line; the admin center stays Installed |
| App works | Launch Continuum from Start and sign in | Normal behaviour |
| Self-update leaves Intune alone | After Continuum updates itself (tray or in-app prompt), sync again | Version changed; Intune still Installed; no new "Running" line |
| Uninstall | Assignments → remove the group from Required, add it under Uninstall → sync | App and registry key gone; `uninstall.log` ends with "Continuum removed." |

Never assign the same group to both Required and Uninstall at once.

## 6. Roll out

Replace `Continuum Pilot` with your production group, or add the production group as a second Required assignment. For a self-service option instead, use **Available for enrolled devices**; users then install from Company Portal.

When a new Continuum version appears as a release here, no action is required. Devices already running Continuum update themselves. If you want new installs to start on the newer version, edit the app → App information → replace the package file. Commands and detection stay the same.
