@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Progress text is deliberately written to the host so the pipeline carries only data.
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        # Intune runs the payload under Windows PowerShell 5.1; the build tooling must also
        # run under 7 on the Ubuntu release job.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
