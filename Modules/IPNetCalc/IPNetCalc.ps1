class IPv4Network {
    [ipaddress]$IPAddress
    [string]$CIDR
    [ipaddress]$Mask
    [ValidateRange(0, 32)][int]$PrefixLength
    [ipaddress]$Subnet
    [ipaddress]$WildCard
    [ipaddress]$Broadcast
    [int64]$Count

    IPv4Network([string]$CIDR) {
        $this.IPAddress, $this.PrefixLength = $CIDR.Split([char[]]'\/')
        if (![IPv4Network]::ip_is_v4($this.IPAddress)) {
            throw "is not ipv4 $($this.IPAddress)"
        }

        $this.Mask = [IPAddress][string](4gb - [bigint]::Pow(2, 32 - $this.PrefixLength))
        $this.WildCard = [byte[]]$this.Mask.GetAddressBytes().ForEach({ 255 - $_ })
        $this.Subnet = $this.IPAddress.Address -band $this.Mask.Address
        $this.Broadcast = $this.IPAddress.Address -bor $this.WildCard.Address
        $this.CIDR = "$($this.Subnet)/$($this.PrefixLength)"
        $this.Count = $this.GetCount()
    }

    IPv4Network([ipaddress]$IPAddress, [int16]$PrefixLength) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) { throw "is not ipv4 $IPAddress" } else {
            $this.IPAddress = $IPAddress
        }

        $this.PrefixLength = $PrefixLength
        $this.Mask = [IPAddress][string](4gb - [bigint]::Pow(2, 32 - $this.PrefixLength))
        $this.WildCard = [byte[]]$this.Mask.GetAddressBytes().ForEach({ 255 - $_ })
        $this.Subnet = $this.IPAddress.Address -band $this.Mask.Address
        $this.Broadcast = $this.IPAddress.Address -bor $this.WildCard.Address
        $this.CIDR = "$($this.Subnet)/$PrefixLength"
        $this.Count = $this.GetCount()
    }

    IPv4Network([ipaddress]$IPAddress, [ipaddress]$Mask) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) { throw "is not ipv4 $IPAddress" } else {
            $this.IPAddress = $IPAddress
        }
        if (![IPv4Network]::check_mask($Mask)) { throw "invalid mask $Mask" } else {
            $this.PrefixLength = [IPv4Network]::get_bin_string($Mask).TrimEnd('0').Length
            $this.Mask = $Mask
        }

        $this.WildCard = [byte[]]$this.Mask.GetAddressBytes().ForEach({ 255 - $_ })
        $this.Subnet = $IPAddress.Address -band $Mask.Address
        $this.Broadcast = $this.IPAddress.Address -bor $this.WildCard.Address
        $this.CIDR = "$($this.Subnet)/$($this.PrefixLength)"
        $this.Count = $this.GetCount()
    }

    [bool] Contains([ipaddress]$ip) {
        [int64]$i_ip = [IPv4Network]::get_ip_int64($ip)
        [int64]$i_Subnet = [IPv4Network]::get_ip_int64($this.Subnet)
        [int64]$i_Broadcast = [IPv4Network]::get_ip_int64($this.Broadcast)
        return ($i_Subnet -le $i_ip) -and ($i_ip -le $i_Broadcast)
    }

    [ipaddress[]] GetIParray() {
        [System.Collections.Generic.List[string]]$ipaddresses = @()
        [int64]$a = [IPv4Network]::get_ip_int64($this.Subnet)
        [int64]$z = [IPv4Network]::get_ip_int64($this.Broadcast)
        for ([int64]$i = $a; $i -le $z; $i++) {
            $ipaddresses.Add($i)
        }
        return $ipaddresses
    }

    [IPv4Network] Add([int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_int64($this.IPAddress) + $i
        $this.IPAddress = [IPv4Network]::get_reversed_ip($r_ip)
        return $this
    }

    [IPv4Network] Subtract([int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_int64($this.IPAddress) - $i
        $this.IPAddress = [IPv4Network]::get_reversed_ip($r_ip)
        return $this
    }

    [int64] GetCount() {
        $o1, $o2, $o3, $o4 = $this.WildCard.GetAddressBytes()
        return $o1 * 16mb + $o2 * 64kb + $o3 * 256 + $o4 + 1
    }

    [string] ToString() {
        return $this.CIDR
    }

    [bool] Equals($other) {
        return ($this.CIDR -eq $other.CIDR)
    }

    static [IPv4Network] op_Addition([IPv4Network]$ip, [int64]$i) {
        return $ip.Add($i)
    }

    static [IPv4Network] op_Subtraction([IPv4Network]$ip, [int64]$i) {
        return $ip.Subtract($i)
    }

    static [ipaddress] get_reversed_ip([ipaddress]$ip) {
        return [string]$ip.Address
    }

    static [int64] get_ip_int64([ipaddress]$ip) {
        return [IPv4Network]::get_reversed_ip($ip).Address
    }

    static [int64] get_net_int64([IPv4Network]$net) {
        return [IPv4Network]::get_ip_int64($net.Subnet) -band [IPv4Network]::get_ip_int64($net.Broadcast)
    }

    static [string] get_bin_string([ipaddress]$ip) {
        return [System.Convert]::ToString([IPv4Network]::get_ip_int64($ip), 2)
    }

    static [bool] check_mask([ipaddress]$ip) {
        return ![IPv4Network]::get_bin_string($ip).TrimEnd('0').Contains('0')
    }

    static [bool] ip_is_v4([ipaddress]$ip) {
        return $ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
    }

}

Function Get-IPv4Network {
    <#
	.DESCRIPTION
	calculation of an ip network

	.EXAMPLE
	Get-IPv4Network -CIDR 198.18.0.0/28

	IPAddress    : 198.18.0.0
	CIDR         : 198.18.0.0/28
	Mask         : 255.255.255.240
	PrefixLength : 28
	Subnet       : 198.18.0.0
	WildCard     : 0.0.0.15
	Broadcast    : 198.18.0.15
	Count        : 16

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
	Get-NetRoute -AddressFamily IPv4 | Select-Object -Property *,@{n='net';e={Get-IPv4Network -CIDR $_.DestinationPrefix}} | ? {$_.net.Contains('8.8.8.8')} | Sort-Object -Property @{e={$_.net.PrefixLength};asc=$false},ifMetric | ft InterfaceMetric,DestinationPrefix,NextHop

	InterfaceMetric DestinationPrefix NextHop
	--------------- ----------------- -------
				 35 0.0.0.0/0         192.168.0.1
				 25 0.0.0.0/0         192.168.0.1
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
