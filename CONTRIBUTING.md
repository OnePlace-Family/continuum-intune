# Contributing

Issues are welcome, especially reports from real tenants with the kit logs attached. Use the issue template.

Pull requests are reviewed by the Continuum engineering team. Before opening one:

- Keep every script compatible with Windows PowerShell 5.1. Intune runs the payload under 5.1, and CI runs the build and tests under it on purpose.
- Run `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` and `.\tests\Test-Constants.ps1` locally.
- Changes to anything in `payload/` or to `Detect.ps1` change what runs on customers' devices. They are merged only after a maintainer has verified them on an Intune test tenant, not just in CI.
- Do not commit anything under `build/`, any installer, or any `.intunewin` file.

The publish workflow never runs from a fork or a pull request, and CI for pull requests from outside the organisation waits for a maintainer's approval before it starts.
