@{
    RootModule = 'MacAddress.psm1'
    ModuleVersion = '2.0.3'
    GUID = 'ee2dd8a5-8439-4156-8073-583864eb2d25'
    Author = 'Saw-Friendship'
    Copyright = 'Saw-Friendship'
    Description = 'Get Hardware Vendor by MacAddress. Contains Database from IEEE site for offline using. Use Update-MacAddressDatabase commandlet for update Database'
    FunctionsToExport = @('Get-MacAddressVendor', 'Update-MacAddressDatabase')
    AliasesToExport = 'Resolve-MacAddress'
    CmdletsToExport = '*-*'
    PrivateData = @{}
}
