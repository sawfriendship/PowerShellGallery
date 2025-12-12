function Get-IPv4Network {
    <#
	.DESCRIPTION
	calculation of an ip network

	.EXAMPLE
	Get-IPv4Network -CIDR 198.18.0.0/28

    IPAddress        CIDR                 Subnet           Mask             Count
    ---------        ----                 ------           ----             -----
    198.18.0.0       198.18.0.0/28        198.18.0.0       255.255.255.240  16


	.EXAMPLE
	Get-IPv4Network -CIDR 198.18.0.0/15 | % Contains 198.19.1.1
	True

	.EXAMPLE
	Get-IPv4Network -CIDR 198.18.0.0/30 | % GetIPArray | ft IPAddressToString

	IPAddressToString
	-----------------
	198.18.0.0
	198.18.0.1
	198.18.0.2
	198.18.0.3

	.EXAMPLE
    Get-NetRoute -AddressFamily IPv4 | Get-IPv4Network | ? PrefixLength -ge 25

    CIDR                     Subnet               Mask                 Count
    ----                     ------               ----                 -----
    127.0.0.1/32             127.0.0.1            255.255.255.255      1
    127.255.255.255/32       127.255.255.255      255.255.255.255      1
    192.168.36.17/32         192.168.36.17        255.255.255.255      1

	.EXAMPLE
	Get-NetRoute -AddressFamily IPv4 | Select-Object -Property *,@{n='net';e={Get-IPv4Network -CIDR $_.DestinationPrefix}} | ? {$_.net.Contains('8.8.8.8')} | Sort-Object -Property @{e={$_.net.PrefixLength};asc=$false},ifMetric | ft InterfaceMetric,DestinationPrefix,NextHop

	InterfaceMetric DestinationPrefix NextHop
	--------------- ----------------- -------
    35 0.0.0.0/0         192.168.0.1
    25 0.0.0.0/0         192.168.0.1

    .EXAMPLE
    [ipv4Network]'10.0.0.0/30' | % GetIPArray | % ToString

    10.0.0.0
    10.0.0.1
    10.0.0.2
    10.0.0.3

    .EXAMPLE
    [ipv4Network]::get_subnet('198.19.1.1','255.254.0.0') | % ToString

    198.18.0.0

    .EXAMPLE
    [ipv4Network]::get_mask_from_prefixlength(23) | % ToString

    255.255.254.0

    .EXAMPLE
    [ipv4Network]::get_wildcard('255.255.248.0') | % ToString

    0.0.7.255

    .EXAMPLE
    [ipv4Network]::check_mask('240.240.240.0')

    False

    .EXAMPLE
    ([ipv4Network[]]('10.0.1.0/24','10.0.2.0/24','10.0.3.0/24')).Includes('10.0.2.100')

    False
    True
    False

    .EXAMPLE
    ([ipv4Network[]]('10.0.1.0/24','10.0.2.0/24','10.0.3.0/24')).WhereIncludes('10.0.2.100')

    IPAddress        CIDR                 Subnet           Mask             Count
    ---------        ----                 ------           ----             -----
    10.0.2.0         10.0.2.0/24          10.0.2.0         255.255.255.0    256

	#>

    [CmdletBinding()]
    [Alias("ipcalc")]
    param(
        [Parameter(Mandatory, ParameterSetName = 'CIDR', Position = 0, ValueFromPipelineByPropertyName)][Alias('DestinationPrefix')][string]$CIDR,
        [Parameter(Mandatory, ParameterSetName = 'Mask', Position = 1)][Parameter(Mandatory, ParameterSetName = 'PrefixLength', Position = 1)][IPAddress]$IPAddress,
        [Parameter(Mandatory, ParameterSetName = 'Mask', Position = 2)][IPAddress]$Mask,
        [Parameter(Mandatory, ParameterSetName = 'PrefixLength', Position = 2)][int]$PrefixLength
    )
    process {
        New-Object -TypeName IPv4Network -ArgumentList ([object[]]$PSBoundParameters.Values)
    }
}
