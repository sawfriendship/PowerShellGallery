@{
        IncludeDefaultRules = $true

        ExcludeRules = @(
            ,'PSAvoidUsingWriteHost'
            ,'PSAvoidUsingCmdletAliases'
            ,'PSUseDeclaredVarsMoreThanAssignments'
            ,'PSUseShouldProcessForStateChangingFunctions'
            # Do not use wildcard or $null in this field. Explicitly specify a list for FunctionsToExport
            # ☝️ ВНИМАНИЕ FunctionsToExport вычисляется в пайплайне и заменяется автоматически перед публикацией в nuget, поэтому в коде для удобства оставляем *
            ,'PSUseToExportFieldsInManifest'

            # Script definition uses ConvertTo-SecureString with plaintext. This will expose secure information. Encrypted standard strings should be used instead
            # 💡 Eсть необходимость конвертации кредов, но в открытом виде мы их не храним, это нужно, например, для работы с vault или pwst
            ,'PSAvoidUsingConvertToSecureStringWithPlainText'

            # 😁 Просто задолбало) Судя по всему это не починить, вот issue: https://github.com/PowerShell/PSScriptAnalyzer/issues/1472
            ,'PSReviewUnusedParameter'
    )

    Rules = @{
        PSUseCorrectCasing = @{Enable = $true}
        PSUseSingularNouns = @{Enable = $true}
        PSAvoidUsingCmdletAliases = @{
            Whitelist = @('%','?','cd','ls','diff','select')
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
        }
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
        }
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            NoEmptyLineBefore = $true
        }
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $false
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $false
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator = $false
            CheckParameter = $false
            IgnoreAssignmentOperatorInsideHashTable = $false
        }
    }
}
