# Builds the Intune package for Continuum on a Windows machine.
#
#   .\Build-Kit.ps1                   # current release, x64
#   .\Build-Kit.ps1 -Arch arm64       # current release, arm64
#   .\Build-Kit.ps1 -Arch universal   # one package carrying both builds (twice the size)
#   .\Build-Kit.ps1 -Version 1.3.9    # pinned version (universal only, see Get-Installer.ps1)
#
# Output in .\build\out\:
#   Continuum-<version>-<arch>.intunewin   upload as the app package
#   Detect.ps1                             upload as the custom detection script
#   kit-manifest-<arch>.txt / .json        hashes and the two Intune command lines
#
# Everything downloaded is verified before use: the installer against ToDesktop's SHA-512
# and its Authenticode signer (Get-Installer.ps1), and Microsoft's Content Prep Tool against
# a pinned commit, SHA-256 and signer.

[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64', 'universal')]
    [string]$Arch = 'x64',
    [string]$Version,
    # Fail if the feed serves a different version than the caller decided to publish.
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Microsoft Win32 Content Prep Tool, release v1.8.7. The repository ships the exe in-tree and
# its releases carry no assets, so the raw file at a commit is the only pinnable download.
$ToolCommit = '1d6cfcbdf8c28edc596337031f74df951f38f718'
$ToolSha256 = 'C1BA45B5CB939E84AF064BB7FF4B38FB3DFE33C8DC1078FD9B157672EAE671F6'
$ToolUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/$ToolCommit/IntuneWinAppUtil.exe"
$ToolSigner = 'Microsoft Corporation'

$InstallCommand = '%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install.ps1'
$UninstallCommand = '%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall.ps1'

$buildDir = Join-Path $PSScriptRoot 'build'
$sourceDir = Join-Path $buildDir 'source'
$outDir = Join-Path $buildDir 'out'
$toolPath = Join-Path $buildDir 'IntuneWinAppUtil.exe'
$payloadDir = Join-Path $PSScriptRoot 'payload'

function Test-Tool {
    param([string]$Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $false
    }
    $hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    if ($hash -ne $ToolSha256) {
        Write-Warning "IntuneWinAppUtil.exe SHA-256 is $hash, expected $ToolSha256"
        return $false
    }
    $signature = Get-AuthenticodeSignature -FilePath $Path
    $signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) } else { $null }
    if ($signature.Status -ne 'Valid' -or $signer -ne $ToolSigner) {
        Write-Warning "IntuneWinAppUtil.exe signature is '$($signature.Status)' by '$signer', expected Valid by '$ToolSigner'"
        return $false
    }
    return $true
}

foreach ($dir in @($sourceDir, $outDir)) {
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force
    }
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Tool -Path $toolPath)) {
    if (Test-Path $toolPath) {
        Remove-Item -Path $toolPath -Force
    }
    Write-Host "Downloading IntuneWinAppUtil.exe from commit $ToolCommit"
    Invoke-WebRequest -Uri $ToolUrl -OutFile $toolPath -UseBasicParsing
    if (-not (Test-Tool -Path $toolPath)) {
        Remove-Item -Path $toolPath -Force
        throw 'Downloaded IntuneWinAppUtil.exe failed the hash or signature check. Refusing to build.'
    }
}

foreach ($file in @('Install.ps1', 'Uninstall.ps1', 'Common.ps1')) {
    Copy-Item -Path (Join-Path $payloadDir $file) -Destination $sourceDir
}

$getInstaller = @{ Arch = $Arch; OutputDirectory = $sourceDir }
if ($Version) {
    $getInstaller.Version = $Version
}
$installer = & (Join-Path $PSScriptRoot 'Get-Installer.ps1') @getInstaller
if ($null -eq $installer -or -not (Test-Path -Path $installer.Path)) {
    throw 'Installer download did not produce a file'
}
if ($ExpectedVersion -and $installer.Version -ne $ExpectedVersion) {
    throw "Feed served version $($installer.Version) but $ExpectedVersion was expected. The feed moved; rerun."
}
# A pinned -Version always yields the universal installer.
$Arch = $installer.Arch

Write-Host 'Packaging with IntuneWinAppUtil'
& $toolPath -c $sourceDir -s 'Install.ps1' -o $outDir -q
if ($LASTEXITCODE -ne 0) {
    throw "IntuneWinAppUtil exited with $LASTEXITCODE"
}

$packageName = "Continuum-$($installer.Version)-$Arch.intunewin"
Rename-Item -Path (Join-Path $outDir 'Install.intunewin') -NewName $packageName
$package = Get-Item -Path (Join-Path $outDir $packageName)

Copy-Item -Path (Join-Path $PSScriptRoot 'Detect.ps1') -Destination $outDir
$detect = Get-Item -Path (Join-Path $outDir 'Detect.ps1')

$kitCommit = $env:GITHUB_SHA
if (-not $kitCommit) {
    try { $kitCommit = (& git -C $PSScriptRoot rev-parse HEAD 2>$null) } catch { $kitCommit = $null }
}
if (-not $kitCommit) {
    $kitCommit = 'unknown'
}

$packageSha256 = (Get-FileHash -Path $package.FullName -Algorithm SHA256).Hash
$detectSha256 = (Get-FileHash -Path $detect.FullName -Algorithm SHA256).Hash

$manifest = [ordered]@{
    version   = $installer.Version
    arch      = $Arch
    builtUtc  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    kitCommit = $kitCommit
    installer = [ordered]@{
        fileName = $installer.FileName
        url      = $installer.Url
        size     = $installer.Size
        sha256   = $installer.Sha256
        sha512   = $installer.Sha512Base64
        signer   = $installer.SignerSubject
    }
    package   = [ordered]@{
        fileName = $package.Name
        size     = $package.Length
        sha256   = $packageSha256
    }
    detect    = [ordered]@{
        fileName = $detect.Name
        sha256   = $detectSha256
    }
    tool      = [ordered]@{
        commit = $ToolCommit
        sha256 = $ToolSha256
    }
    intune    = [ordered]@{
        installCommand   = $InstallCommand
        uninstallCommand = $UninstallCommand
    }
}

$jsonPath = Join-Path $outDir "kit-manifest-$Arch.json"
# WriteAllText with an explicit encoding avoids the UTF-8 BOM that Set-Content adds on 5.1.
[System.IO.File]::WriteAllText($jsonPath, ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

$text = @(
    "Built        $($manifest.builtUtc)"
    "Version      $($installer.Version) ($Arch)"
    "Installer    $($installer.FileName)"
    "Installer    SHA-256 $($installer.Sha256)"
    "Installer    SHA-512 $($installer.Sha512Base64)"
    "Package      $($package.Name)"
    "Package      SHA-256 $packageSha256"
    "Detection    Detect.ps1 SHA-256 $detectSha256"
    "Kit commit   $kitCommit"
    ''
    'Intune install command:'
    $InstallCommand
    'Intune uninstall command:'
    $UninstallCommand
)
[System.IO.File]::WriteAllText((Join-Path $outDir "kit-manifest-$Arch.txt"), (($text -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

$text | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Done. Upload $($package.FullName) and $($detect.FullName) to Intune. See README.md."
