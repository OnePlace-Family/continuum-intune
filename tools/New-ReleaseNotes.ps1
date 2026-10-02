# Turns the kit-manifest-<arch>.json files from one or more Build-Kit runs into the
# Markdown body of a GitHub Release. Used by the publish workflow and by hand when
# regenerating notes.
#
#   .\tools\New-ReleaseNotes.ps1 -ManifestDir .\build\out -Output .\release-notes.md
#
# The line "Installer SHA-512 (x64): <value>" is read back by the publish workflow to decide
# whether a version already on the release page was rebuilt by ToDesktop. Keep its format.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestDir,
    [Parameter(Mandatory)][string]$Output,
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [string]$RunUrl = $(if ($env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID) { "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID" } else { $null })
)

$ErrorActionPreference = 'Stop'

function Format-Size {
    param([int64]$Bytes)
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    "$Bytes B"
}

$manifestFiles = Get-ChildItem -Path $ManifestDir -Filter 'kit-manifest-*.json' -File | Sort-Object Name
if (-not $manifestFiles) {
    throw "No kit-manifest-*.json in $ManifestDir"
}
$manifests = $manifestFiles | ForEach-Object { Get-Content -Path $_.FullName -Raw | ConvertFrom-Json }
# x64 first so the machine-read SHA-512 line is stable.
$manifests = @($manifests | Sort-Object { if ($_.arch -eq 'x64') { 0 } elseif ($_.arch -eq 'arm64') { 1 } else { 2 } })

# @() keeps a single result an array; a lone string would index by character.
$versions = @($manifests | ForEach-Object { $_.version } | Sort-Object -Unique)
if ($versions.Count -ne 1) {
    throw "Manifests disagree on the version: $($versions -join ', ')"
}
$version = $versions[0]

$detectHashes = @($manifests | ForEach-Object { $_.detect.sha256 } | Sort-Object -Unique)
if ($detectHashes.Count -ne 1) {
    throw "Detect.ps1 differs between architectures: $($detectHashes -join ', ')"
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("## Continuum $version for Microsoft Intune")
$lines.Add('')
$lines.Add('| Asset | Architecture | SHA-256 | Size |')
$lines.Add('|---|---|---|---|')
foreach ($m in $manifests) {
    $lines.Add("| ``$($m.package.fileName)`` | $($m.arch) | ``$($m.package.sha256)`` | $(Format-Size $m.package.size) |")
}
$detectPath = Join-Path $ManifestDir 'Detect.ps1'
$detectSize = if (Test-Path $detectPath) { Format-Size (Get-Item $detectPath).Length } else { '' }
$lines.Add("| ``Detect.ps1`` | any | ``$($manifests[0].detect.sha256)`` | $detectSize |")
foreach ($m in $manifests) {
    foreach ($ext in @('json', 'txt')) {
        $name = "kit-manifest-$($m.arch).$ext"
        $path = Join-Path $ManifestDir $name
        if (Test-Path $path) {
            $lines.Add("| ``$name`` | $($m.arch) | ``$((Get-FileHash -Path $path -Algorithm SHA256).Hash)`` | $(Format-Size (Get-Item $path).Length) |")
        }
    }
}
$lines.Add('')
$lines.Add('### Packaged installers')
$lines.Add('')
foreach ($m in $manifests) {
    $lines.Add("**$($m.arch):** ``$($m.installer.fileName)``  ")
    $lines.Add("Installer SHA-256 ($($m.arch)): ``$($m.installer.sha256)``  ")
    $lines.Add("Installer SHA-512 ($($m.arch)): $($m.installer.sha512)  ")
    $lines.Add("Source: $($m.installer.url)")
    $lines.Add('')
}
$lines.Add("Authenticode signer: ``$($manifests[0].installer.signer)`` (verified at build time).")
$lines.Add('')
$lines.Add('### Build')
$lines.Add('')
$tool = $manifests[0].tool
$built = "Microsoft Win32 Content Prep Tool commit ``$($tool.commit.Substring(0, 8))`` (SHA-256 ``$($tool.sha256)``), kit commit ``$($manifests[0].kitCommit.Substring(0, [Math]::Min(8, $manifests[0].kitCommit.Length)))``"
if ($RunUrl) {
    $built += ", [workflow run]($RunUrl)"
}
$lines.Add("$built.")
$lines.Add('')
$lines.Add('### Deploying')
$lines.Add('')
$lines.Add('Create one Intune app per architecture you manage, with the matching **Operating system architecture** requirement (x64 or ARM64). Both apps use the same `Detect.ps1` and the same install and uninstall commands:')
$lines.Add('')
$lines.Add('```')
$lines.Add($manifests[0].intune.installCommand)
$lines.Add($manifests[0].intune.uninstallCommand)
$lines.Add('```')
$lines.Add('')
$lines.Add('Install behavior **User**, return codes 1 and 2 as Failed, custom detection script `Detect.ps1`. Full settings in the [README](https://github.com/' + $Repository + '#intune-app-settings).')
$lines.Add('')
$lines.Add('### Updates')
$lines.Add('')
$lines.Add('Continuum updates itself after the first install. You do not need to replace the package in Intune when a new version appears here; doing so only changes the version new devices start on. `Detect.ps1` checks presence, not version, and is identical across releases unless the changelog says otherwise.')
$lines.Add('')
$lines.Add('### Verify what you downloaded')
$lines.Add('')
$lines.Add('```powershell')
$lines.Add("Get-FileHash .\$($manifests[0].package.fileName)   # must print the SHA-256 above")
if ($Repository) {
    $owner = $Repository.Split('/')[0]
    $lines.Add("gh attestation verify .\$($manifests[0].package.fileName) --owner $owner")
}
$lines.Add('```')

[System.IO.File]::WriteAllText($Output, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $Output"
