@{
    IncludeDefaultRules = $true

    ExcludeRules = @(
        # Мы вообще против этого, но без этого мы не умеем 😁
        , 'PSAvoidUsingEmptyCatchBlock'


        # Script definition uses ConvertTo-SecureString with plaintext. This will expose secure information. Encrypted standard strings should be used instead
        # 💡 Eсть необходимость конвертации кредов, но в открытом виде мы их не храним, это нужно, например, для работы с vault или pwst
        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/AvoidUsingConvertToSecureStringWithPlainText.cs
        , 'PSAvoidUsingConvertToSecureStringWithPlainText'


        # Просто не согласен
        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/UseSingularNouns.cs
        , 'PSUseSingularNouns'


        # Do not use wildcard or $null in this field. Explicitly specify a list for FunctionsToExport
        # ☝️ ВНИМАНИЕ FunctionsToExport вычисляется в пайплайне и заменяется автоматически перед публикацией в nuget, поэтому в коде для удобства оставляем *
        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/UseToExportFieldsInManifest.cs
        , 'PSUseToExportFieldsInManifest'


        # Просто задолбало 😁
        # Судя по всему это не починить, вот issue: https://github.com/PowerShell/PSScriptAnalyzer/issues/1472

        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/UseDeclaredVarsMoreThanAssignments.cs
        , 'PSUseDeclaredVarsMoreThanAssignments'
        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/ReviewUnusedParameter.cs
        , 'PSReviewUnusedParameter'


        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/UseShouldProcessForStateChangingFunctions.cs
        , 'PSUseShouldProcessForStateChangingFunctions'
        # https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Rules/UseApprovedVerbs.cs
        , 'PSUseApprovedVerbs'
    )

    IncludeRules = @(

        # Правила без настроек (вроде xD )
        , 'PSAvoidDefaultValueForMandatoryParameter'
        , 'PSAvoidDefaultValueSwitchParameter'
        , 'PSAvoidUsingCmdletAliases'
        , 'PSAvoidUsingInvokeExpression'
        , 'PSAvoidUsingPlaintTextForPassword'
        , 'PSAvoidUsingUserNameAndPassWordParams'
        , 'PSAvoidUsingWMICmdlet'
        , 'PSAvoidUsingWriteHost'
        , 'PSMisleadingBacktick'
        , 'PSMissingModuleManifestField'
        , 'PSPossibleIncorrectComparisonWithNull'
        , 'PSReservedCmdletChar'
        , 'PSReservedParams'
        , 'PSShouldProcess'
        , 'PSUseBOMForUnicodeEncodedFile'
        , 'PSUseCmdletCorrectly'
        , 'PSUseCompatibleSyntax'
        , 'PSUseCore'
        , 'PSUseDeclaredVarsMoreThanAssignments'
        , 'PSUseOutputTypeCorrectly'
        , 'PSUserToExportFieldsInManifest'

        # Правила с настройками
        , 'PSAlignAssignmentStatement'
        , 'PSAvoidLongLines'
        , 'PSUseLiteralInitializerForHashtable'
        , 'PSPlaceCloseBrace'
        , 'PSUseConsistentIndentation'
        , 'PSAvoidPositionalParameters'
        , 'PSUseConsistentWhitespace'
        , 'PSUseCorrectCasing'
        , 'PSPlaceOpenBrace'
        , 'PSAvoidOverwritingBuiltInCmdlets'
        , 'PSUseProcessBlockForPipelineCommand'
        , 'PSAvoidUsingDoubleQuotesForConstantString'
        , 'PSAvoidUsingCmdletAliases'
    )

    Rules = @{
        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $false
        }
        PSAvoidUsingCmdletAliases = @{
            AllowList = @('%', '?', 'cd', 'rm', 'mv', 'ls', 'tee', 'diff', 'measure', 'group', 'sort', 'select', 'sleep', 's')
        }

        PSAvoidOverwritingBuiltInCmdlets = @{
            Enable = $true
        }
        PSAvoidLongLines = @{
            Enable = $true
            MaximumLineLength = 480
        }
        PSAvoidPositionalParameters = @{
            Enable = $true
        }
        PSUseLiteralInitializerForHashtable = @{
            Enable = $true
        }
        PSUseProcessBlockForPipelineCommand = @{
            Enable = $true
        }
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }
        PSUseCorrectCasing = @{
            Enable = $true
            CheckOperator = $true
            CheckKeyword = $true
            CheckCommands = $true
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
        }
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            NoEmptyLineBefore = $true
            IgnoreOneLineBlock = $true
        }
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckOpenBrace = $true
            CheckInnerBrace = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckSeparator = $true
            CheckParameter = $true
            CheckHashtable = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
    }
}
