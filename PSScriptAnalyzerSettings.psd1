@{
    IncludeDefaultRules = $true
    Severity = @(
        ,'Error'
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
