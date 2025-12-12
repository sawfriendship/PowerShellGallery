class IPv4Network {
    [ipaddress]$IPAddress
    [string]$CIDR
    [ipaddress]$Mask
    [ipaddress]$Subnet
    [ipaddress]$Broadcast
    [ipaddress]$WildCard
    [ValidateRange(0, 32)][int]$PrefixLength
    [int64]$Count
    [int64]$ReversedAddress
    [bool]$NetworkContainsIPAddress

    IPv4Network([string]$CIDR) {
        $this.IPAddress, $this.PrefixLength = $CIDR.Split([char[]]'\/')
        if (![IPv4Network]::ip_is_v4($this.IPAddress)) {
            throw "is not ipv4 $($this.IPAddress)"
        }

        $this.Mask = [IPv4Network]::get_mask_from_prefixlength($this.PrefixLength)
        $this.WildCard = [IPv4Network]::get_wildcard($this.Mask)
        $this.Subnet = [IPv4Network]::get_subnet($this.IPAddress,$this.Mask)
        $this.Broadcast = [IPv4Network]::get_broadcast($this.IPAddress,$this.WildCard)
        $this.CIDR = "$($this.Subnet)/$($this.PrefixLength)"
        $this.Count = $this.GetCount()
        $this.ReversedAddress = [IPv4Network]::get_reversed_address($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    IPv4Network([ipaddress]$IPAddress, [int16]$PrefixLength) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) { throw "is not ipv4 $IPAddress" } else {
            $this.IPAddress = $IPAddress
        }

        $this.PrefixLength = $PrefixLength
        $this.Mask = [IPv4Network]::get_mask_from_prefixlength($this.PrefixLength)
        $this.WildCard = [IPv4Network]::get_wildcard($this.Mask)
        $this.Subnet = [IPv4Network]::get_subnet($this.IPAddress,$this.Mask)
        $this.Broadcast = [IPv4Network]::get_broadcast($this.IPAddress,$this.WildCard)
        $this.CIDR = "$($this.Subnet)/$PrefixLength"
        $this.Count = $this.GetCount()
        $this.ReversedAddress = [IPv4Network]::get_reversed_address($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    IPv4Network([ipaddress]$IPAddress, [ipaddress]$Mask) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) { throw "is not ipv4 $IPAddress" } else {
            $this.IPAddress = $IPAddress
        }
        if (![IPv4Network]::check_mask($Mask)) { throw "invalid mask $Mask" } else {
            $this.PrefixLength = [IPv4Network]::get_bin_string($Mask).TrimEnd('0').Length
            $this.Mask = $Mask
        }

        $this.WildCard = [IPv4Network]::get_wildcard($this.Mask)
        $this.Subnet = [IPv4Network]::get_subnet($this.IPAddress,$this.Mask)
        $this.Broadcast = [IPv4Network]::get_broadcast($this.IPAddress,$this.WildCard)
        $this.CIDR = "$($this.Subnet)/$($this.PrefixLength)"
        $this.Count = $this.GetCount()
        $this.ReversedAddress = [IPv4Network]::get_reversed_address($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    [bool] Includes([ipaddress]$ip) {
        [int64]$i_ip = [IPv4Network]::get_ip_int64($ip)
        [int64]$i_Subnet = [IPv4Network]::get_ip_int64($this.Subnet)
        [int64]$i_Broadcast = [IPv4Network]::get_ip_int64($this.Broadcast)
        return ($i_Subnet -le $i_ip) -and ($i_ip -le $i_Broadcast)
    }

    [IPv4Network] WhereIncludes([ipaddress]$ip) {
        [int64]$i_ip = [IPv4Network]::get_ip_int64($ip)
        [int64]$i_Subnet = [IPv4Network]::get_ip_int64($this.Subnet)
        [int64]$i_Broadcast = [IPv4Network]::get_ip_int64($this.Broadcast)
        if (($i_Subnet -le $i_ip) -and ($i_ip -le $i_Broadcast)) {
            return $this
        } else {
            return $null
        }
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

    [void] SetIPAddress([ipaddress]$ip) {
        if (![IPv4Network]::ip_is_v4($ip)) {
            throw "is not ipv4 $($ip)"
        }
        $this.IPAddress = $ip
        $this.ReversedAddress = [IPv4Network]::get_reversed_address($ip)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    [IPv4Network] Add([int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_int64($this.IPAddress) + $i
        $this.IPAddress = [IPv4Network]::get_reversed_ip($r_ip)
        $this.ReversedAddress = [IPv4Network]::get_reversed_address($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
        return $this
    }

    [IPv4Network] Subtract([int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_int64($this.IPAddress) - $i
        $this.IPAddress = [IPv4Network]::get_reversed_ip($r_ip)
        $this.ReversedAddress = [IPv4Network]::get_reversed_address($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
        return $this
    }

    [int64] GetCount() {
        return [IPv4Network]::get_reversed_address($this.WildCard) + 1
    }

    [string] ToString() {
        return $this.CIDR
    }

    [bool] Equals($other) {
        return ($this.CIDR -eq $other.CIDR)
    }

    hidden static [IPv4Network] op_Addition([IPv4Network]$ip, [int64]$i) {
        return [IPv4Network]::new($ip.IPAddress,$ip.Mask).Add($i)
    }

    hidden static [IPv4Network] op_Subtraction([IPv4Network]$ip, [int64]$i) {
        return [IPv4Network]::new($ip.IPAddress,$ip.Mask).Subtract($i)
    }

    static [ipaddress] get_reversed_ip([ipaddress]$ip) {
        return [string]$ip.Address
    }

    static [int64] get_reversed_address([ipaddress]$ip) {
        return ([ipaddress][IPv4Network]::get_reversed_ip($ip)).Address
    }

    static [int64] get_ip_int64([ipaddress]$ip) {
        return [IPv4Network]::get_reversed_ip($ip).Address
    }

    static [int64] get_net_int64([IPv4Network]$net) {
        return [IPv4Network]::get_ip_int64($net.Subnet) -band [IPv4Network]::get_ip_int64($net.Broadcast)
    }

    static [ipaddress] get_wildcard([ipaddress]$ip) {
        return (4gb + (-bnot $ip.Address))
    }

    static [ipaddress] get_subnet([ipaddress]$ip,[ipaddress]$mask) {
        return $ip.Address -band $mask.Address
    }

    static [ipaddress] get_broadcast([ipaddress]$ip,[ipaddress]$wildcard) {
        return $ip.Address -bor $wildcard.Address
    }

    static [ipaddress] get_mask_from_prefixlength([int16]$PrefixLength) {
        return [string](4gb - [bigint]::Pow(2, 32 - $PrefixLength))
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
