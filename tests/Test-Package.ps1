# Structural check of a .intunewin produced by Build-Kit.ps1. The file is a zip with the
# encrypted payload and a Detection.xml describing it. This does not decrypt the payload;
# the smoke test exercises the same files that were packaged.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$InstallerPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path -Path $Package -PathType Leaf)) {
    throw "Package not found: $Package"
}
$installerSize = (Get-Item -Path $InstallerPath).Length

$zip = [System.IO.Compression.ZipFile]::OpenRead($Package)
try {
    $names = $zip.Entries | ForEach-Object { $_.FullName }
    foreach ($required in @('IntuneWinPackage/Metadata/Detection.xml', 'IntuneWinPackage/Contents/IntunePackage.intunewin')) {
        if ($names -notcontains $required) {
            throw "Package is missing $required. Entries: $($names -join ', ')"
        }
    }

    $entry = $zip.GetEntry('IntuneWinPackage/Metadata/Detection.xml')
    $reader = New-Object System.IO.StreamReader($entry.Open())
    try {
        [xml]$detection = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    $info = $detection.ApplicationInfo
    if ($null -eq $info) {
        throw 'Detection.xml has no ApplicationInfo element'
    }
    if ($info.SetupFile -ne 'Install.ps1') {
        throw "Detection.xml SetupFile is '$($info.SetupFile)', expected Install.ps1"
    }
    if ([string]::IsNullOrWhiteSpace($info.Name)) {
        throw 'Detection.xml Name is empty'
    }
    # UnencryptedContentSize is the zipped source folder before encryption. The installer is
    # already compressed, so the zip lands within a few percent of its size; far below that
    # means the installer was not in the folder.
    $unencrypted = [int64]$info.UnencryptedContentSize
    if ($unencrypted -lt ($installerSize * 0.9)) {
        throw "Detection.xml UnencryptedContentSize $unencrypted is far smaller than the installer ($installerSize bytes); the installer is missing from the package"
    }
    if ([string]::IsNullOrWhiteSpace($info.EncryptionInfo.EncryptionKey)) {
        throw 'Detection.xml has no EncryptionKey'
    }

    $contents = $zip.GetEntry('IntuneWinPackage/Contents/IntunePackage.intunewin')
    if ($contents.Length -lt $unencrypted) {
        throw "Encrypted payload is $($contents.Length) bytes, smaller than the unencrypted content ($unencrypted bytes)"
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Package structure OK: $Package (SetupFile Install.ps1, unencrypted content $($info.UnencryptedContentSize) bytes)"
exit 0
