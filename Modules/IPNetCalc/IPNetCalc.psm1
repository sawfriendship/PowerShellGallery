[type[]]$ExportableTypes = @([IPv4Network])
$TypeAcceleratorsClass = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
$ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
$ExportableTypes | ? {$_.FullName -notin $ExistingTypeAccelerators.Keys} | % {$ExportableTypes.ForEach({ $TypeAcceleratorsClass::Add($_.FullName, $_) })}
