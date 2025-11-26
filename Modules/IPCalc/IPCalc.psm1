[type[]]$ExportableTypes = @([IPv4Network])

$TypeAcceleratorsClass = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')

$ExistingTypeAccelerators = $TypeAcceleratorsClass::Get

foreach ($Type in $ExportableTypes) {
    if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
        $Message = "Unable to register type accelerator '$($Type.FullName)' Accelerator already exists."
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($Message),
            'TypeAcceleratorAlreadyExists',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Type.FullName
        )
    }
}

[void]$ExportableTypes.ForEach({ $TypeAcceleratorsClass::Add($_.FullName, $_) })

$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = { $ExportableTypes.ForEach({ $TypeAcceleratorsClass::Remove($_) }) }
