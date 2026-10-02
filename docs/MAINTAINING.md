# Maintaining this repository

Written for Continuum engineering. Customers do not need anything here.

## How a release gets published

1. A `release/vX.Y.Z` PR is merged in the application repository. That tags the version and builds the production desktop app in ToDesktop.
2. A person reviews and clicks **Release** in the ToDesktop dashboard. Only then does `https://download.todesktop.com/250131q5s29r5/latest.yml` change. This can be minutes or days after the tag.
3. `publish.yml` in this repository runs every Monday at 14:23 UTC. Its `check` job reads `latest.yml`, compares the version with the newest published release here, and decides. If the feed is newer, the `build` matrix packages x64 on `windows-latest` and arm64 on `windows-11-arm`, runs the package and smoke tests, and the `release` job publishes a draft, verifies every asset, attaches a provenance attestation, flips the draft to published, and posts to Slack.
4. Want it sooner than Monday? Actions → Publish Intune package → **Run workflow**. Leave both inputs off.

Nothing in the application repository triggers this workflow, by design: the tag does not mean the installer is out.

## Workflow inputs

| Input | Effect |
|---|---|
| `dry_run` | Builds and tests the current feed version and uploads the result as a workflow artifact. Creates no release, posts nothing to Slack. Use it after changing any script. |
| `ignore_failed_marker` | Runs even if a `publish-failed` issue is open for the version. |

## When the check job stops and opens an issue

The `check` job opens or updates an issue titled `Publish failed: v<version>` with the `publish-failed` label and posts to Slack when:

- the feed has no x64 or no arm64 installer,
- the feed version is not a plain `X.Y.Z`,
- the feed version equals the newest published release but its x64 installer SHA-512 differs (ToDesktop re-released the same version with a different build).

The `on-failure` job does the same when a build or publish step fails. While such an issue is open, scheduled runs skip that version. Close the issue to let the next run retry, or dispatch with `ignore_failed_marker`.

For a re-released same version: releases are immutable, so `v1.3.10` cannot be replaced. Decide whether the new build matters for first installs. If it does, the current answer is a manual release named `v1.3.10-kit.2` built with `dry_run` and uploaded by hand; the check job ignores tags that are not plain `vX.Y.Z`, so it will not fight it. A proper scheme for this is a follow-up.

## Pins and how to bump them

| What | Where | How to bump |
|---|---|---|
| Content Prep Tool | `Build-Kit.ps1`: `$ToolCommit`, `$ToolSha256` | Pick the commit of the new release tag in `microsoft/Microsoft-Win32-Content-Prep-Tool`, download `IntuneWinAppUtil.exe` from that commit, record `Get-FileHash` SHA-256, confirm `Get-AuthenticodeSignature` is Valid by Microsoft Corporation. |
| Installer signer | `Get-Installer.ps1`: `$ExpectedSigner` | Only if the code-signing certificate's common name changes. Update it before the first build signed with the new certificate ships. |
| ToDesktop app id | `Get-Installer.ps1`, `publish.yml` env | Only if the production app is recreated in ToDesktop. |
| Action versions | `.github/workflows/*.yml`, SHA-pinned with a version comment | Dependabot opens PRs weekly. |
| Install identity | `payload/Common.ps1` and `Detect.ps1`: GUID, exe name, folder name | Derived from the app's `appId` and package name. If either changes in the application repository, both files must change together; `tests/Test-Constants.ps1` enforces that they match each other. |

## Feed assumptions

`Get-Installer.ps1` and the `check` job assume `latest.yml` has a `version:` line and `files[]` entries whose `url` ends in `-x64.exe` and `-arm64.exe`, each with `sha512`. The pinned-version path assumes `dl.todesktop.com/<app>/versions/<v>/windows/nsis` returns a `Content-Disposition` filename. A format change fails the build with a readable error and opens the failure issue.

## Scheduled workflows in public repositories

GitHub disables scheduled workflows after 60 days without a commit to the repository. This workflow creates releases, not commits, so a quiet repository silently stops polling. If the Slack channel has been silent across two releases, check Actions for a "workflow disabled" banner and re-enable it. Any merged PR (a Dependabot bump counts) resets the clock.

## Test tenant

The kit was validated on an Intune trial tenant with an Entra joined Windows 11 laptop. To repeat that validation:

1. Build locally: `.\Build-Kit.ps1 -Arch x64`.
2. Follow `docs/INTUNE-SETUP.md` with a pilot group containing the test user.
3. Force check-ins with `Restart-Service IntuneManagementExtension` (elevated).
4. Read the agent's decisions in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log`: look for `detection state:`, `execution type:`, `lpExitCode`.
5. To make the agent re-evaluate an app it has already processed, delete `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\<user GUID>` (export it first) and restart the service.

Still open from the original validation: a run as a standard (non-administrator) user, and an ARM64 device. The CI smoke test covers both architectures on clean runners but always as a local administrator and never through Intune itself.

## Re-running a failed publish

1. Read the run. The `build` jobs upload `smoke-logs-<arch>` artifacts even on failure.
2. Fix the cause on a branch; `ci.yml` runs the same build and smoke test on PRs.
3. Merge, close the `publish-failed` issue, and dispatch the workflow.
