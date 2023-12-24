[string]$Uri = 'http://standards-oui.ieee.org/oui.txt'
[System.Collections.Generic.Dictionary[System.String,System.Object]]$MacAddressDatabase = @{}

[string]$OuiFilePath =  Join-Path -Path $PSScriptRoot -ChildPath 'oui.txt'
[string]$CsvFilePath =  Join-Path -Path $PSScriptRoot -ChildPath 'oui.csv'

$ProgressPreference_ = $ProgressPreference
	
Update-TypeData -Force -TypeName 'MacAddress' -MemberType ScriptMethod -MemberName ToString -Value {$this.Vendor}

Function Get-MacAddressVendor {
<#
	.EXAMPLE
	Get-NetAdapter | Resolve-MacAddress | ft

	MacAddress Vendor                    Country Address                                                  POBox
	---------- ------                    ------- -------                                                  -----
	D8BBC1     Micro-Star INTL CO., LTD. TW      No.69, Lide St.,                                         New Taipei City  Taiwan  235
	00155D     Microsoft Corporation     US      One Microsoft Way                                        Redmond  WA  98052-8300
	D8BBC1     Micro-Star INTL CO., LTD. TW      No.69, Lide St.,                                         New Taipei City  Taiwan  235
	001A7D     cyber-blue(HK)Ltd         CN      Room 1408 block C stars Plaza HongLiRoad,FuTian District Shenzhen  GuangDong  518028
	00155D     Microsoft Corporation     US      One Microsoft Way                                        Redmond  WA  98052-8300
	
	.EXAMPLE
	Get-NetNeighbor | Resolve-MacAddress | ft

	MacAddress Vendor                Country Address                                               POBox
	---------- ------                ------- -------                                               -----
	000000     XEROX CORPORATION     US      M/S 105-50C                                           WEBSTER  NY  14580
	000000     XEROX CORPORATION     US      M/S 105-50C                                           WEBSTER  NY  14580
	000000     XEROX CORPORATION     US      M/S 105-50C                                           WEBSTER  NY  14580
	00155D     Microsoft Corporation US      One Microsoft Way                                     Redmond  WA  98052-8300
	000000     XEROX CORPORATION     US      M/S 105-50C                                           WEBSTER  NY  14580
	00155D     Microsoft Corporation US      One Microsoft Way                                     Redmond  WA  98052-8300
	00155D     Microsoft Corporation US      One Microsoft Way                                     Redmond  WA  98052-8300
	001018     Broadcom              US      16215 ALTON PARKWAY                                   IRVINE  CA  92619-7013
	00155D     Microsoft Corporation US      One Microsoft Way                                     Redmond  WA  98052-8300
	00155D     Microsoft Corporation US      One Microsoft Way                                     Redmond  WA  98052-8300
	50FF20     Keenetic Limited      HK      1202, 12/F., AT TOWER, 180 ELECTRIC ROAD, NORTH POINT HONG KONG    852
	000000     XEROX CORPORATION     US      M/S 105-50C                                           WEBSTER  NY  14580
	
	.EXAMPLE
	Get-NetNeighbor | select IPAddress,LinkLayerAddress,@{n='Vendor';e={Get-MacAddressVendor $_.LinkLayerAddress}} | ? Vendor

	IPAddress    LinkLayerAddress  Vendor
	---------    ----------------  ------
	192.168.0.155 00-00-00-00-00-00 XEROX CORPORATION
	192.168.0.30  00-00-00-00-00-00 XEROX CORPORATION
	192.168.0.20  00-15-5D-19-10-02 Microsoft Corporation
	192.168.0.15  00-00-00-00-00-00 XEROX CORPORATION
	192.168.0.13  00-15-5D-19-10-04 Microsoft Corporation
	192.168.0.12  00-15-5D-00-6E-0E Microsoft Corporation
	192.168.0.10  00-10-18-A0-B3-06 Broadcom
	192.168.0.8   00-15-5D-19-10-00 Microsoft Corporation
	192.168.0.6   00-15-5D-19-10-01 Microsoft Corporation
#>
	[CmdletBinding()]
	param(
		[CmdletBinding()]
		[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
		[Alias('LinkLayerAddress','PhysicalAddress','ClientId','Mac','MacAddress')]
		[ValidateScript({$_ -match '^$' -or $_ -replace '[^0-9a-f]' -match '^([0-9a-f]{6})([0-9a-f]{6})?$'})]
		[AllowEmptyString()]
		[System.String[]]$InputObject
	)
	begin {}
	process {
		$InputObject | % {
			$MAC = ("$_") -replace '[^0-9a-f]' -replace '(?<=[0-9a-f]{6}).+'
			$MacAddressDatabase[$MAC.ToUpper()]
		}
	}
	end {}
}

Function Update-MacAddressDatabase {
	[CmdletBinding()]
	param()

	$ProgressPreference = 'SilentlyContinue'
    
	Write-Verbose -Message "Downloading from $Uri" -Verbose
	
	try {
		Invoke-WebRequest -Uri $Uri -OutFile $OuiFilePath
	} catch {
		throw $_.Exception
	}
	
	Write-Verbose -Message "Parsing raw file to $OuiFilePath" -Verbose
	
	Select-String -Path $OuiFilePath -Pattern '^(?<MAC>[0-9a-fA-F]{6})\s+\(base\s+16\)\s+(?<VEN>.+)' -Context 3 | Select-Object -Property @(
		,@{Name = 'MacAddress'; Expression = {$_.Matches.Captures.Groups['MAC'].Value.ToUpper()}}
		,@{Name = 'Vendor'; Expression = {$_.Matches.Captures.Groups['VEN'].Value}}
		,'Context'
	) | Select-Object -Property @(
		,'MacAddress'
		,'Vendor'
		,@{Name = 'Country'; Expression = {if ($_.Vendor -ne 'Private') {$_.Context.PostContext[2].Trim()} else {''}}}
		,@{Name = 'Address'; Expression = {if ($_.Vendor -ne 'Private') {$_.Context.PostContext[0].Trim()} else {''}}}
		,@{Name = 'POBox'; Expression = {if ($_.Vendor -ne 'Private') {$_.Context.PostContext[1].Trim()} else {''}}}
	) | % {
		$_.PSTypeNames.Add('MacAddress')
		$MacAddressDatabase[$_.MacAddress] = $_
	}
	
	Write-Verbose -Message "Saving $($MacAddressDatabase.Count) records to $CsvFilePath" -Verbose
	
	$MacAddressDatabase.Values | Export-Csv -Delimiter ';' -NoTypeInformation -Path $CsvFilePath
	
	$ProgressPreference = $ProgressPreference_
}

Function Import_MacAddressDatabase {
	[CmdletBinding()]
	param()
	Import-Csv -Path $CsvFilePath -Delimiter ';' | % {
		$_.PSTypeNames.Add('MacAddress')
		$MacAddressDatabase[$_.MacAddress] = $_
	}
}

Import_MacAddressDatabase

Set-Alias -Name 'Resolve-MacAddress' -Value 'Get-MacAddressVendor'
