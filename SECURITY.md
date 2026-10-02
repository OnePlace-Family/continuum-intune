# Security

## Reporting

Email **security@oncontinuum.com**. Do not open a public issue for a security problem. You will get an acknowledgement within two business days.

This repository covers the Intune packaging scripts and the automation that publishes them. Vulnerabilities in the Continuum application itself should go to the same address and will be routed to the application team.

## What a released package is made of

Every release on this repository is produced by the `publish.yml` workflow on GitHub-hosted runners, with no secrets involved in the build. The workflow:

1. Downloads the Continuum installer from ToDesktop's production feed and verifies it twice: its SHA-512 must match the value ToDesktop publishes in `latest.yml`, and its Authenticode signature must be valid and issued to `OnePlace Company Inc.`. A file that fails either check is deleted and the build stops.
2. Downloads Microsoft's Win32 Content Prep Tool from a pinned commit of Microsoft's repository and verifies its SHA-256 and its Microsoft Authenticode signature before running it.
3. Packages the installer together with the three scripts in `payload/`, exactly as committed.
4. Installs, detects, re-runs, and uninstalls the result on a clean runner for each architecture before anything is published.
5. Creates the GitHub Release with the SHA-256 of every asset in the notes and attaches a build provenance attestation for each `.intunewin` file.

To verify a download:

```powershell
Get-FileHash .\Continuum-<version>-x64.intunewin        # compare with the release notes
gh attestation verify .\Continuum-<version>-x64.intunewin --owner OnePlace-Family
```

The `.intunewin` container is encrypted with a key generated per build, so two builds of the same inputs do not produce the same bytes. The installer inside it and `Detect.ps1` are reproducible and their hashes are listed in every release.

## What the scripts do on a device

- `Install.ps1`, `Uninstall.ps1` and `Common.ps1` run from Intune's content cache in the signed-in user's context, never elevated. `Install.ps1` refuses to run as SYSTEM.
- They make no network calls. The installer they run is the one inside the package.
- They write a log to `%LOCALAPPDATA%\ContinuumIntuneKit\` containing timestamps, the installer filename, exit codes and the user's SID. Nothing else.
- `Detect.ps1` reads the registry and checks for a file. It writes nothing.

Releases on this repository are immutable once published.
