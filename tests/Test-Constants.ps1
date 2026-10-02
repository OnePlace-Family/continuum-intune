# Detect.ps1 is uploaded to Intune on its own and cannot dot-source Common.ps1, so the
# identifiers that locate the install are deliberately duplicated. This test fails the
# moment the two copies drift.

[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not yet set while parameter defaults are evaluated under 5.1 -File.
if (-not $Root) {
    $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}

$common = Get-Content -Path (Join-Path $Root 'payload\Common.ps1') -Raw
$detect = Get-Content -Path (Join-Path $Root 'Detect.ps1') -Raw

$expected = @{
    Guid       = '814ecc71-30fe-5c71-b9c9-65458b992584'
    ExeName    = 'Continuum.exe'
    FolderName = 'continuum-electron'
    SystemSid  = 'S-1-5-18'
}

$failures = @()
foreach ($name in $expected.Keys) {
    $value = [regex]::Escape($expected[$name])
    if ($common -notmatch "'$value'") {
        $failures += "payload\Common.ps1 does not contain $name '$($expected[$name])'"
    }
    if ($detect -notmatch "'$value'") {
        $failures += "Detect.ps1 does not contain $name '$($expected[$name])'"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error -Message $_ -ErrorAction Continue }
    exit 1
}

Write-Host 'Constants in payload\Common.ps1 and Detect.ps1 match.'
exit 0
