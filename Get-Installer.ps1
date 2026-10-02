# Downloads a Continuum Windows installer from ToDesktop and verifies it before anything
# else touches it. Run on a packaging machine or CI runner, never on end-user devices.
#
#   .\Get-Installer.ps1                     # current release, x64
#   .\Get-Installer.ps1 -Arch arm64         # current release, arm64
#   .\Get-Installer.ps1 -Arch universal     # x64 + arm64 in one file (about twice the size)
#   .\Get-Installer.ps1 -Version 1.3.9      # a specific released version (universal only)
#
# Current release: https://download.todesktop.com/<app>/latest.yml lists every artifact with
# its SHA-512. Specific versions: https://dl.todesktop.com/<app>/versions/<v>/windows/nsis
# serves the universal installer for that version with no manifest, so only SHA-256 is
# recorded on that path.
#
# Two checks gate the result and both throw on failure:
#   1. SHA-512 against latest.yml (current-release path only).
#   2. Authenticode signature must be Valid and the signer's common name must equal
#      -ExpectedSigner. This is what stops a swapped file at the feed from being packaged.
#
# Returns one object on the pipeline: Version, Arch, FileName, Path, Url, Size, Sha256,
# Sha512Base64, SignerSubject. Progress text goes to the host, not the pipeline.

[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64', 'universal')]
    [string]$Arch = 'x64',
    [string]$Version,
    [string]$OutputDirectory = $PSScriptRoot,
    [string]$ExpectedSigner = 'OnePlace Company Inc.'
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 redraws a progress bar per chunk, which turns a 118 MB download
# into minutes. Silencing it is the single biggest speed-up on a runner.
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$appId = '250131q5s29r5'
$feed = "https://download.todesktop.com/$appId"

function Get-Sha512Base64 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA512]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        [Convert]::ToBase64String($sha.ComputeHash($stream))
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

if ($Version) {
    if ($Arch -ne 'universal') {
        Write-Warning 'Version-pinned links only serve the universal installer. Downloading universal.'
        $Arch = 'universal'
    }
    $url = "https://dl.todesktop.com/$appId/versions/$Version/windows/nsis"
    $head = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing
    $disposition = [string]$head.Headers['Content-Disposition']
    if ($disposition -notmatch 'filename="([^"]+)"') {
        throw "Could not read the filename for version $Version from $url"
    }
    $fileName = $Matches[1]
    $expectedSha512 = $null
    $resolvedVersion = $Version
}
else {
    # Served as binary/octet-stream, so Content arrives as bytes rather than text.
    $response = Invoke-WebRequest -Uri "$feed/latest.yml" -UseBasicParsing
    $yaml = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    if ($yaml -notmatch '(?m)^version:\s*(\S+)') {
        throw "No version line in $feed/latest.yml"
    }
    $resolvedVersion = $Matches[1].Trim("'", '"')
    $entries = [regex]::Matches($yaml, '-\s*url:\s*(?<url>.+?)\r?\n\s*sha512:\s*(?<sha>\S+)')
    $suffix = switch ($Arch) {
        'x64' { '-x64.exe' }
        'arm64' { '-arm64.exe' }
        'universal' { $null }
    }
    $entry = $entries | Where-Object {
        $name = $_.Groups['url'].Value.Trim()
        if ($suffix) { $name.EndsWith($suffix) } else { $name -notmatch '-(x64|arm64)\.exe$' }
    } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "No $Arch artifact in $feed/latest.yml"
    }
    $fileName = $entry.Groups['url'].Value.Trim()
    $expectedSha512 = $entry.Groups['sha'].Value.Trim()
    $url = "$feed/" + [uri]::EscapeDataString($fileName)
}

$destination = Join-Path $OutputDirectory $fileName
Write-Host "Downloading $fileName"
Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing

$sha512 = Get-Sha512Base64 -Path $destination
if ($expectedSha512) {
    if ($sha512 -ne $expectedSha512) {
        Remove-Item -Path $destination -Force
        throw "SHA-512 mismatch for $fileName. Expected $expectedSha512, got $sha512"
    }
    Write-Host 'SHA-512 matches latest.yml'
}

$signature = Get-AuthenticodeSignature -FilePath $destination
$signerName = $null
if ($null -ne $signature.SignerCertificate) {
    $signerName = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
}
if ($signature.Status -ne 'Valid' -or $signerName -ne $ExpectedSigner) {
    Remove-Item -Path $destination -Force
    throw "Signature check failed for $fileName. Status '$($signature.Status)', signer '$signerName', expected a Valid signature by '$ExpectedSigner'."
}
Write-Host "Signature Valid by $signerName"

$file = Get-Item -Path $destination
Write-Host "Saved to $destination ($($file.Length) bytes)"

[pscustomobject]@{
    Version       = $resolvedVersion
    Arch          = $Arch
    FileName      = $fileName
    Path          = $destination
    Url           = $url
    Size          = $file.Length
    Sha256        = (Get-FileHash -Path $destination -Algorithm SHA256).Hash
    Sha512Base64  = $sha512
    SignerSubject = $signature.SignerCertificate.Subject
}
