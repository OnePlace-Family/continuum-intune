# Changelog

Changes to the packaging scripts and automation. Continuum application versions are not listed here; each GitHub Release names the version it packages.

## 2026-10-02

- Moved the kit out of the private application repository (previously `continuum-web`, commit `5c1a0487`) into this public repository.
- `Get-Installer.ps1` now refuses an installer whose Authenticode signature is not valid or not issued to `OnePlace Company Inc.`, and returns a structured result.
- `Build-Kit.ps1` pins Microsoft's Content Prep Tool to a commit and verifies its SHA-256 and signature; names the package `Continuum-<version>-<arch>.intunewin`; writes `kit-manifest-<arch>.json` next to the text manifest; accepts `-ExpectedVersion`.
- Added `tests/` (constants drift, package structure, smoke test) and `tools/New-ReleaseNotes.ps1`.
- Added the weekly publish workflow and CI.
- No change to `Install.ps1`, `Uninstall.ps1`, `Common.ps1` or `Detect.ps1`.
