# Maintaining this repository

For the people who operate the publish workflow. Customers do not need anything here.

## How a release gets published

`publish.yml` runs every Monday at 14:23 UTC and on manual dispatch. Its `check` job reads ToDesktop's production feed (`latest.yml`), compares the version with the newest published release here, and decides. If the feed is newer, the `build` matrix packages x64 on `windows-latest` and arm64 on `windows-11-arm`, runs the package and smoke tests, and the `release` job publishes a draft, verifies every asset, attaches a provenance attestation, flips the draft to published, and posts a notification.

To publish sooner than the next Monday: Actions → Publish Intune package → **Run workflow**, both inputs off.

## Workflow inputs

| Input | Effect |
|---|---|
| `dry_run` | Builds and tests the current feed version and uploads the result as a workflow artifact. Creates no release and sends no notification. Use it after changing any script. |
| `ignore_failed_marker` | Runs even if a `publish-failed` issue is open for the version. |

## When the check job stops and opens an issue

The `check` job opens or updates an issue titled `Publish failed: v<version>` with the `publish-failed` label when:

- the feed has no x64 or no arm64 installer,
- the feed version is not a plain `X.Y.Z`,
- the feed version equals the newest published release but its x64 installer SHA-512 differs (the same version was rebuilt upstream).

The `on-failure` job does the same when a build or publish step fails. While such an issue is open, scheduled runs skip that version. Close the issue to let the next run retry, or dispatch with `ignore_failed_marker`.

Releases are immutable, so a version that is already published cannot be replaced. If a rebuilt same-version installer matters for first installs, publish it under a distinct tag that is not a plain `vX.Y.Z`; the check job ignores such tags.

## Pins and how to bump them

| What | Where | How to bump |
|---|---|---|
| Content Prep Tool | `Build-Kit.ps1`: `$ToolCommit`, `$ToolSha256` | Pick the commit of the new release tag in `microsoft/Microsoft-Win32-Content-Prep-Tool`, download `IntuneWinAppUtil.exe` from that commit, record `Get-FileHash` SHA-256, confirm `Get-AuthenticodeSignature` is Valid by Microsoft Corporation. |
| Installer signer | `Get-Installer.ps1`: `$ExpectedSigner` | Only if the code-signing certificate's common name changes. Update it before the first build signed with the new certificate ships. |
| ToDesktop app id | `Get-Installer.ps1`, `publish.yml` env | Only if the production app is recreated. |
| Action versions | `.github/workflows/*.yml`, SHA-pinned with a version comment | Dependabot opens PRs weekly. |
| Install identity | `payload/Common.ps1` and `Detect.ps1`: GUID, exe name, folder name | Change both files together; `tests/Test-Constants.ps1` enforces that they match. |

## Feed assumptions

`Get-Installer.ps1` and the `check` job assume `latest.yml` has a `version:` line and `files[]` entries whose `url` ends in `-x64.exe` and `-arm64.exe`, each with `sha512`. The pinned-version path assumes `dl.todesktop.com/<app>/versions/<v>/windows/nsis` returns a `Content-Disposition` filename. A format change fails the build with a readable error and opens the failure issue.

## Scheduled workflows in public repositories

GitHub disables scheduled workflows after 60 days without a commit to the repository. This workflow creates releases, not commits, so a quiet repository silently stops polling. If no release has appeared for a while, check Actions for a "workflow disabled" banner and re-enable it. Any merged PR (a Dependabot bump counts) resets the clock.

## Re-running a failed publish

1. Read the run. The `build` jobs upload `smoke-logs-<arch>` artifacts even on failure.
2. Fix the cause on a branch; `ci.yml` runs the same build and smoke test on PRs.
3. Merge, close the `publish-failed` issue, and dispatch the workflow.
