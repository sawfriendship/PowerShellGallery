Update-FormatData -AppendPath "$PSScriptRoot\MontyHallProblemBurster.ps1xml"

Function Invoke-MasterStart {
	$R = Get-Random -InputObject @(0,0,1) -Count 3; 
	@{'a' = $R[0];'b' = $R[1];'c' = $R[2]}
}

Function Invoke-PlayerStart {Get-Random -InputObject @('a','b','c')}

Function Invoke-MasterRestart {
	param (
		[HashTable]$MasterStart,
		[String]$PlayerStart
	)
	$MasterStart.GetEnumerator().Where({$_.Value -ne 1 -and $_.Name -ne $PlayerStart})[0].Name
}

Function Invoke-PlayerRestart {
	param (
		[String]$MasterRestart,
		[String]$PlayerStart,
		[Parameter(Mandatory=$true)][bool]$Change
	)
	if (!$Change) {$PlayerStart} else {@('a','b','c').Where({$_ -ne $PlayerStart -and $_ -ne $MasterRestart})}
}

Function Start-MontyHallProblemBurster {
	param ($Count = 100)
	$Objects = @()
	
	for ($i = 1 ; $i -le $Count ; $i++) {
		
		# Master
		$MasterStart = Invoke-MasterStart
		
		# Player1
		$Player1Start = Invoke-PlayerStart 
		$Master1Restart = Invoke-MasterRestart -MasterStart $MasterStart -PlayerStart $Player1Start
		$Player1Restart = Invoke-PlayerRestart -MasterRestart $Master1Restart -PlayerStart $Player1Start -Change:$true
		$Player1Result = [bool]$MasterStart[$Player1Restart]
		
		# Player2
		$Player2Start = Invoke-PlayerStart 
		$Master2Restart = Invoke-MasterRestart -MasterStart $MasterStart -PlayerStart $Player2Start
		$Player2Restart = Invoke-PlayerRestart -MasterRestart $Master2Restart -PlayerStart $Player2Start -Change:$false
		$Player2Result = [bool]$MasterStart[$Player2Restart]
		
		# Current Game Result
		$Object = Select-Object -InputObject $i -Property @(
			,@{Name = 'GameNumber';Expression = {$i}}
			,@{Name = 'Doors'; Expression = {"A:$($MasterStart['a']),B:$($MasterStart['b']),C:$($MasterStart['c'])"}}
			,@{Name = 'Player1(change_true)';Expression = {$Player1Result}}
			,@{Name = 'Player2(change_false)';Expression = {$Player2Result}}
			,@{Name = 'Player1Steps';Expression	= {"$Player1Start=>$Master1Restart=>$Player1Restart"}}
			,@{Name = 'Player2Steps';Expression	= {"$Player2Start=>$Master2Restart=>$Player2Restart"}}
		)
		
		$Object.psobject.Typenames.Insert(0,'MontyHall.Stat')
		$Objects += $Object
		$Object
		
	}
	
	# Games Result
	Write-Verbose -Verbose -Message "Win Stat:"
	Write-Verbose -Verbose -Message "Player1(change_true): $($Objects.Where({$_.'Player1(change_true)'}).Count)"
	Write-Verbose -Verbose -Message "Player2(change_false): $($Objects.Where({$_.'Player2(change_false)'}).Count)"
	
}

