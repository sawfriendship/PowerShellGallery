@{
    IncludeDefaultRules = $true
    Severity = @(
        ,'Error'
        ,'Warning'
        ,'ParseError'
    )
    ExcludeRules = @(
        ,'PSAvoidUsingWriteHost'
        ,'PSReviewUnusedParameter'
        ,'PSAvoidUsingCmdletAliases'
        ,'PSUseToExportFieldsInManifest'
        ,'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
