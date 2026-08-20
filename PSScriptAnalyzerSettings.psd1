@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
    )
    Rules        = @{
        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }
    }
}
