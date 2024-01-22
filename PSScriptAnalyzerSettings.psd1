@{
    IncludeDefaultRules = $true
    Severity=@('Error','Warning','ParseError')
    ExcludeRules = @(
        ,'PSAvoidUsingWriteHost'
        ,'PSAvoidUsingCmdletAliases'
    )
}
