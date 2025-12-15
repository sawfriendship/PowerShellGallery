class IPv4Network {
    [ipaddress]$IPAddress
    [string]$CIDR
    [ipaddress]$Mask
    [ipaddress]$Subnet
    [ipaddress]$Broadcast
    [ipaddress]$WildCard
    [ValidateRange(0,32)][int16]$PrefixLength
    [int64]$Count
    [int64]$Address
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
        $this.Broadcast = [IPv4Network]::get_broadcast($this.IPAddress,$this.Mask)
        $this.CIDR = "$($this.Subnet)/$($this.PrefixLength)"
        $this.Count = $this.GetCount()
        $this.Address = [IPv4Network]::get_address($this.IPAddress)
        $this.ReversedAddress = [IPv4Network]::get_address_reversed($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    IPv4Network([ipaddress]$IPAddress, [int16]$PrefixLength) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) {
            throw "is not ipv4 $IPAddress"
        }
        $this.IPAddress = $IPAddress
        $this.PrefixLength = $PrefixLength
        $this.Mask = [IPv4Network]::get_mask_from_prefixlength($this.PrefixLength)
        $this.WildCard = [IPv4Network]::get_wildcard($this.Mask)
        $this.Subnet = [IPv4Network]::get_subnet($this.IPAddress,$this.Mask)
        $this.Broadcast = [IPv4Network]::get_broadcast($this.IPAddress,$this.Mask)
        $this.CIDR = "$($this.Subnet)/$PrefixLength"
        $this.Count = $this.GetCount()
        $this.Address = [IPv4Network]::get_address($this.IPAddress)
        $this.ReversedAddress = [IPv4Network]::get_address_reversed($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    IPv4Network([ipaddress]$IPAddress, [ipaddress]$Mask) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) {
            throw "is not ipv4 $IPAddress"
        }
        if (![IPv4Network]::check_mask($Mask)) {
            throw "invalid mask $Mask"
        }
        $this.IPAddress = $IPAddress
        $this.PrefixLength = [IPv4Network]::get_bin_string($Mask).TrimEnd('0').Length
        $this.Mask = $Mask
        $this.WildCard = [IPv4Network]::get_wildcard($this.Mask)
        $this.Subnet = [IPv4Network]::get_subnet($this.IPAddress,$this.Mask)
        $this.Broadcast = [IPv4Network]::get_broadcast($this.IPAddress,$this.Mask)
        $this.CIDR = "$($this.Subnet)/$($this.PrefixLength)"
        $this.Count = $this.GetCount()
        $this.Address = [IPv4Network]::get_address($this.IPAddress)
        $this.ReversedAddress = [IPv4Network]::get_address_reversed($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    [bool] Includes([ipaddress]$IPAddress) {
        [int64]$i = [IPv4Network]::get_address_reversed($IPAddress)
        [int64]$a = [IPv4Network]::get_address_reversed($this.Subnet)
        [int64]$z = [IPv4Network]::get_address_reversed($this.Broadcast)
        return ($i -ge $a) -and ($i -le $z)
    }

    [ipaddress[]] GetIParray() {
        [System.Collections.Generic.List[string]]$ipaddresses = @()
        [int64]$a = [IPv4Network]::get_address_reversed($this.Subnet)
        [int64]$z = [IPv4Network]::get_address_reversed($this.Broadcast)
        for ([int64]$i = $a; $i -le $z; $i++) {
            $ipaddresses.Add($i)
        }
        return $ipaddresses
    }

    [void] SetIPAddress([ipaddress]$IPAddress) {
        if (![IPv4Network]::ip_is_v4($IPAddress)) {
            throw "is not ipv4 $($IPAddress)"
        }
        $this.IPAddress = $IPAddress
        $this.Address = [IPv4Network]::get_address($this.IPAddress)
        $this.ReversedAddress = [IPv4Network]::get_address_reversed($IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    [PSCustomObject] GetBinaryNotation() {
        return [PSCustomObject][ordered]@{
            IPAddress = [IPv4Network]::get_bin_string($this.IPAddress)
            Mask = [IPv4Network]::get_bin_string($this.Mask)
            Subnet = [IPv4Network]::get_bin_string($this.Subnet)
            Broadcast = [IPv4Network]::get_bin_string($this.Broadcast)
        }
    }

    [void] Add([int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_reversed($this.IPAddress) + $i
        $this.IPAddress = [IPv4Network]::get_ip_reversed($r_ip)
        $this.Address = [IPv4Network]::get_address($this.IPAddress)
        $this.ReversedAddress = [IPv4Network]::get_address_reversed($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    [void] Subtract([int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_reversed($this.IPAddress) - $i
        $this.IPAddress = [IPv4Network]::get_ip_reversed($r_ip)
        $this.Address = [IPv4Network]::get_address($this.IPAddress)
        $this.ReversedAddress = [IPv4Network]::get_address_reversed($this.IPAddress)
        $this.NetworkContainsIPAddress = $this.Includes($this.IPAddress)
    }

    [int64] GetCount() {
        return 1 + (-bnot [bigint]::new(([IPv4Network]::get_bytes_reversed($this.Mask))))
    }

    [string] ToString() {
        return $this.CIDR
    }

    [bool] Equals($other) {
        return ($this.CIDR -eq $other.CIDR)
    }

    hidden static [object] op_Addition([IPv4Network]$IPv4Network, [int64]$i) {
        [int64]$r_ip = $IPv4Network.IPAddress.Address + $i
        # $IPv4Network.IPAddress = [IPv4Network]::get_ip_reversed($r_ip)
        # $IPv4Network.Address = [IPv4Network]::get_address($IPv4Network.IPAddress)
        # $IPv4Network.ReversedAddress = [IPv4Network]::get_address_reversed($IPv4Network.IPAddress)
        # $IPv4Network.NetworkContainsIPAddress = $IPv4Network.Includes($IPv4Network.IPAddress)
        return $r_ip
    }

    hidden static [IPv4Network] op_Subtraction([IPv4Network]$IPv4Network, [int64]$i) {
        [ipaddress]$r_ip = [IPv4Network]::get_ip_reversed($IPv4Network.IPAddress) - $i
        $IPv4Network.IPAddress = [IPv4Network]::get_ip_reversed($r_ip)
        $IPv4Network.Address = [IPv4Network]::get_address($IPv4Network.IPAddress)
        $IPv4Network.ReversedAddress = [IPv4Network]::get_address_reversed($IPv4Network.IPAddress)
        $IPv4Network.NetworkContainsIPAddress = $IPv4Network.Includes($IPv4Network.IPAddress)
        return $IPv4Network
    }

    static [byte[]] get_bytes_reversed([ipaddress]$IPAddress) {
        $bytes = $IPAddress.GetAddressBytes()
        [array]::Reverse($bytes)
        return $bytes
    }

    static [int64] get_address([ipaddress]$IPAddress) {
        return [bigint]::new($IPAddress.GetAddressBytes())
    }

    static [int64] get_address_reversed([ipaddress]$IPAddress) {
        return [bigint]::new([IPv4Network]::get_bytes_reversed($IPAddress)) + 4gb
    }

    static [ipaddress] get_ip_reversed([ipaddress]$IPAddress) {
        return [ipaddress]::new([IPv4Network]::get_bytes_reversed($IPAddress))
    }

    static [ipaddress] get_wildcard([ipaddress]$IPAddress) {
        return (4gb + (-bnot $IPAddress.Address))
    }

    static [ipaddress] get_subnet([ipaddress]$IPAddress,[ipaddress]$Mask) {
        return [IPv4Network]::get_address($IPAddress) -band [IPv4Network]::get_address($Mask)
    }

    static [ipaddress] get_broadcast([ipaddress]$IPAddress,[ipaddress]$Mask) {
        return [IPv4Network]::get_subnet($IPAddress,$Mask).Address -bor [IPv4Network]::get_wildcard($Mask).Address
    }

    static [ipaddress] get_mask_from_prefixlength([int16]$PrefixLength) {
        return [string](4gb - [bigint]::Pow(2, 32 - $PrefixLength))
    }

    static [string] get_bin_string([ipaddress]$IPAddress) {
        return [System.Convert]::ToString([IPv4Network]::get_address_reversed($IPAddress), 2)
    }

    static [bool] check_mask([ipaddress]$IPAddress) {
        return ![IPv4Network]::get_bin_string($IPAddress).TrimEnd('0').Contains('0')
    }

    static [bool] ip_is_v4([ipaddress]$IPAddress) {
        return $IPAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
    }

}
