@{
    RootModule        = 'IPNetCalc.psm1'
    ModuleVersion     = '1.0.3'
    GUID              = '3f1cbe7f-aede-4855-a0d0-f80cf13aca97'
    Author            = 'saw-friendship'
    CompanyName       = 'Unknown'
    Copyright         = '(c) saw-friendship. All rights reserved.'
    Description       = 'calculation of an ip network based on the powershell class'
    FormatsToProcess  = 'IPNetCalc.ps1xml'
    NestedModules     = @( 'IPNetCalc.ps1' )
    FunctionsToExport = @( 'Get-IPv4Network' )
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{ PSData = @{} }
}

