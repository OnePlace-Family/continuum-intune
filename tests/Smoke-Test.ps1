# Runs the kit scripts on this machine the way Intune runs them: each script in its own
# Windows PowerShell process, judged by exit code and STDOUT only. Installs and removes
# Continuum for the current user, so run it on a clean machine (a CI runner), never on a
# machine where Continuum is in use.
#
#   .\tests\Smoke-Test.ps1 -SourceDir .\build\source -DetectScript .\build\out\Detect.ps1 -ExpectedVersion 1.3.10 -Arch x64
#
# Sequence: detect (absent), install, detect (present), install again (no-op),
# uninstall, detect (absent), uninstall again (no-op).

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$DetectScript,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [ValidateSet('x64', 'arm64', 'universal')]
    [string]$Arch = 'x64'
)

$ErrorActionPreference = 'Stop'

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$guid = '814ecc71-30fe-5c71-b9c9-65458b992584'
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
$exePath = Join-Path $env:LOCALAPPDATA 'Programs\continuum-electron\Continuum.exe'
$logDir = Join-Path $env:LOCALAPPDATA 'ContinuumIntuneKit'
$installLog = Join-Path $logDir 'install.log'
$uninstallLog = Join-Path $logDir 'uninstall.log'
$script:step = 0

function Invoke-KitScript {
    param([string]$Path)
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $powershell `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$Path`"") `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = (Get-Content -Path $out -Raw -ErrorAction SilentlyContinue)
            StdErr   = (Get-Content -Path $err -Raw -ErrorAction SilentlyContinue)
        }
    }
    finally {
        Remove-Item -Path $out, $err -Force -ErrorAction SilentlyContinue
    }
}

function Assert {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Step $($script:step) failed: $Message"
    }
}

function Step {
    param([string]$Title)
    $script:step++
    Write-Host ''
    Write-Host "== Step $($script:step): $Title"
}

function Get-PeMachine {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45) {
        throw "$Path is not a PE file"
    }
    [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

function Get-LogLineCount {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path -Path $Path)) {
        return 0
    }
    @(Select-String -Path $Path -Pattern $Pattern -SimpleMatch).Count
}

$installScript = Join-Path $SourceDir 'Install.ps1'
$uninstallScript = Join-Path $SourceDir 'Uninstall.ps1'
foreach ($required in @($installScript, $uninstallScript, (Join-Path $SourceDir 'Common.ps1'), $DetectScript)) {
    if (-not (Test-Path -Path $required -PathType Leaf)) {
        throw "Missing $required"
    }
}
if (-not (Get-ChildItem -Path $SourceDir -Filter 'Continuum Setup*.exe' -File)) {
    throw "No Continuum Setup*.exe in $SourceDir"
}

Write-Host "Smoke test as $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name), expecting Continuum $ExpectedVersion ($Arch)"

# Pre-checks: this must be a clean machine.
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($sid -eq 'S-1-5-18') {
    throw 'Smoke test must run as a normal user, not SYSTEM'
}
if (Get-Process -Name Continuum -ErrorAction SilentlyContinue) {
    throw 'Continuum is running on this machine. Refusing to run the smoke test here.'
}
$pre = Invoke-KitScript -Path $DetectScript
if ($pre.ExitCode -ne 1 -or -not [string]::IsNullOrWhiteSpace($pre.StdOut)) {
    throw "Machine is not clean: Detect.ps1 exited $($pre.ExitCode) with output '$($pre.StdOut)'. Continuum appears to be installed."
}
Remove-Item -Path $installLog, $uninstallLog -Force -ErrorAction SilentlyContinue

Step 'Install.ps1 on a clean machine'
$r = Invoke-KitScript -Path $installScript
Write-Host $r.StdOut
Assert ($r.ExitCode -eq 0) "exit code $($r.ExitCode)"
$reg = Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue
Assert ($null -ne $reg) 'uninstall registry key missing'
Assert ($reg.DisplayVersion -eq $ExpectedVersion) "DisplayVersion is '$($reg.DisplayVersion)'"
Assert (Test-Path -Path $exePath -PathType Leaf) "exe missing at $exePath"
Assert ((Get-LogLineCount -Path $installLog -Pattern "Installed Continuum $ExpectedVersion") -eq 1) 'install.log lacks the Installed line'
if ($Arch -ne 'universal') {
    $machine = Get-PeMachine -Path $exePath
    $expectedMachine = if ($Arch -eq 'arm64') { 0xAA64 } else { 0x8664 }
    Assert ($machine -eq $expectedMachine) ('exe machine type is 0x{0:X4}, expected 0x{1:X4}' -f $machine, $expectedMachine)
}
$installedAt = (Get-Item -Path $exePath).LastWriteTimeUtc

Step 'Detect.ps1 reports installed'
$r = Invoke-KitScript -Path $DetectScript
Assert ($r.ExitCode -eq 0) "exit code $($r.ExitCode)"
Assert ($r.StdOut -match "^Continuum $([regex]::Escape($ExpectedVersion)) installed at ") "stdout was '$($r.StdOut)'"
Assert ([string]::IsNullOrWhiteSpace($r.StdErr)) "stderr was '$($r.StdErr)'"
Write-Host $r.StdOut.Trim()

Step 'Install.ps1 again is a no-op'
$r = Invoke-KitScript -Path $installScript
Write-Host $r.StdOut
Assert ($r.ExitCode -eq 0) "exit code $($r.ExitCode)"
Assert ((Get-LogLineCount -Path $installLog -Pattern 'Already installed') -eq 1) 'install.log lacks the Already installed line'
Assert ((Get-LogLineCount -Path $installLog -Pattern "Running 'Continuum Setup") -eq 1) 'installer ran more than once'
Assert ((Get-Item -Path $exePath).LastWriteTimeUtc -eq $installedAt) 'exe was rewritten by the second run'

Step 'Uninstall.ps1 removes the install'
Stop-Process -Name Continuum -Force -ErrorAction SilentlyContinue
$r = Invoke-KitScript -Path $uninstallScript
Write-Host $r.StdOut
Assert ($r.ExitCode -eq 0) "exit code $($r.ExitCode)"
Assert ((Get-LogLineCount -Path $uninstallLog -Pattern 'Continuum removed.') -eq 1) 'uninstall.log lacks the removed line'
Assert (-not (Test-Path -Path $uninstallKey)) 'uninstall registry key still present'
Assert (-not (Test-Path -Path $exePath)) 'exe still present'

Step 'Detect.ps1 reports absent'
$r = Invoke-KitScript -Path $DetectScript
Assert ($r.ExitCode -eq 1) "exit code $($r.ExitCode)"
Assert ([string]::IsNullOrWhiteSpace($r.StdOut)) "stdout was '$($r.StdOut)'"

Step 'Uninstall.ps1 again is a no-op'
$r = Invoke-KitScript -Path $uninstallScript
Write-Host $r.StdOut
Assert ($r.ExitCode -eq 0) "exit code $($r.ExitCode)"
Assert ((Get-LogLineCount -Path $uninstallLog -Pattern 'not installed for this user') -eq 1) 'uninstall.log lacks the not-installed line'

Write-Host ''
Write-Host '== install.log'
Get-Content -Path $installLog | ForEach-Object { Write-Host "   $_" }
Write-Host '== uninstall.log'
Get-Content -Path $uninstallLog | ForEach-Object { Write-Host "   $_" }
Write-Host ''
Write-Host "Smoke test passed for Continuum $ExpectedVersion ($Arch)."
exit 0
