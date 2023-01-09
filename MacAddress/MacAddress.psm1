$MacAddressDatabase = [System.Collections.Generic.Dictionary[System.String,System.Object]]::new()
Update-TypeData -Force -TypeName 'MacAddress' -MemberType ScriptMethod -MemberName ToString -Value {$this.Vendor}

Function Update-MacAddressDatabase {
    [string]$Uri = 'http://standards-oui.ieee.org/oui.txt'

    $OuiFilePath =  Join-Path -Path $PSScriptRoot -ChildPath 'oui.txt'
    $CsvFilePath =  Join-Path -Path $PSScriptRoot -ChildPath 'oui.csv'
	
    try {Invoke-WebRequest -Uri $Uri -OutFile $OuiFilePath} catch {throw $_.Exception}
	
	$OuiFile = Select-String -Path $OuiFilePath -Pattern '[0-9a-fA-F]{6}\s*\(base\s*16\).*' -Context 3 | Select-Object -Property @(
		,@{Name = 'MacAddress'; Expression = {$_.Line.ToUpper() -replace '\s*\(base\s*16\).*'}}
		,@{Name = 'Vendor'; Expression = {$_.Line -replace '.*\s*\(base\s*16\)\s*'}}
		,@{Name = 'Context'; Expression = {$_.Context.PostContext.Trim()}}
	) | Select-Object -Property @(
		,'MacAddress'
		,'Vendor'
		,@{Name = 'Country'; Expression = {$_.Context[2]}}
		,@{Name = 'Address'; Expression = {$_.Context[0]}}
		,@{Name = 'POBox'; Expression = {$_.Context[1]}}
	)
		
	$OuiFile | Export-Csv -Delimiter ';' -NoTypeInformation -Path $CsvFilePath
	
	Import-MacAddressDatabase
}

Function Import-MacAddressDatabase {
    $CsvFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'oui.csv'
	Import-Csv -Path $CsvFilePath -Delimiter ';' | % {
		$_.PSTypeNames.Add('MacAddress')
		$MacAddressDatabase[$_.MacAddress] = $_
	}
}

Function Get-MacAddressVendor {
<#
.EXAMPLE
Get-NetNeighbor -IPAddress 192* | Get-MacAddressVendor
HTC Corporation
Microsoft Corporation
D-Link International
ZyXEL Communications Corporation
.EXAMPLE
Get-NetNeighbor -IPAddress 192* | Get-MacAddressVendor -PassThru | Select-Object IPAddress,LinkLayerAddress,Vendor
IPAddress    LinkLayerAddress Vendor
---------    ---------------- ------
192.168.0.255 ffffffffffff
192.168.0.106 1c659d7cb596     Liteon Technology Corporation
192.168.0.101 000000000000
192.168.0.92  f079606a3eda     Apple, Inc.
192.168.0.51  00155d003200     Microsoft Corporation
192.168.0.1   588bf34b5e10     ZyXEL Communications Corporation
#>
	param(
		[Parameter(Mandatory=$true,ValueFromPipeline=$true)]$InputObject,
		[switch]$PassThru
	)
	Begin{
		Function Resolve-MacAddress {
		param(
			[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][alias('LinkLayerAddress','PhysicalAddress','ClientId')][AllowEmptyString()][string[]]$MAC
		)
		Begin {}
		Process {
			$MAC | % {
				$MAC6 = [string]''
				$MAC6 = $_.ToUpper() -replace '[^\w\d]' -replace '(......)(.+)','$1'
					if( ($MAC6 -match '^[\d\w]{6}$') -and  ($MAC6 -notmatch '^(0){6}$') -and ($MAC6 -notmatch '^(f){6}$')) {
						$MacAddressDatabase[$MAC6]
					}
			}
		}
		End {}
		}
	}
	Process{
		$InputObject | % {
			if (![bool]$PassThru) {
				$($_ | Resolve-MacAddress)
			} else {
				Add-Member -InputObject $_ -MemberType NoteProperty -Name 'Vendor' -Value $($_ | Resolve-MacAddress) -Force -PassThru
			}
		}
	}
	End{}
}

Import-MacAddressDatabase
