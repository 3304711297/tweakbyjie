@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseShouldProcessForStateChangingFunctions'
    )
    Rules        = @{
        PSUseCompatibleCommands   = @{ Enable = $true }
        PSUseCompatibleSyntax     = @{ Enable = $true }
        PSAvoidUsingPlainTextForPassword = @{ Enable = $true }
    }
}
