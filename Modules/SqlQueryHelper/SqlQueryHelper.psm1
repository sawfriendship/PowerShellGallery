using namespace System.Collections.Generic

[string[]]$PassThruSqlcmdParam = @('Server','Database','Credential','CommandTimeout','OnlyShowQuery')
$q = "'"
$qq = "''"
function EscapeName ([string]$String) {"[$($String.Trim('[').Trim(']'))]"}

[System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('strbuilder', 'System.Text.StringBuilder')
[System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('objectlist', 'List[System.Object]')
[System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('stringlist', 'List[System.String]')
[System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('stringhashset', 'HashSet[System.String]')
[System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('dict', 'Dictionary[string,object]')

Function Invoke-SqlCommand {
<#
.EXAMPLE
Invoke-SqlCommand -Server sql -Database test1 -Query "SELECT Name,ServiceName FROM ps WHERE Name LIKE '%time%'"

Name          ServiceName
----          -----------
autotimesvc   autotimesvc
TimeBrokerSvc TimeBrokerSvc
vmictimesync  vmictimesync
W32Time       W32Time
#>
    [CmdletBinding()]
    param(
         [Parameter(Mandatory)][Alias('ServerInstance','SqlServer')][string]$Server
        ,[Parameter(Mandatory)][Alias('SqlDatabase')][string]$Database
        ,[Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][string[]]$Query
        ,[PSCredential]$Credential
        ,[Alias('QueryTimeout')][int]$CommandTimeout = 30
        ,[switch]$OnlyShowQuery
        ,[switch]$Raw
    )

    begin {
        $Table = EscapeName -String $Table
        $Database = EscapeName -String $Database
        $Counter = 1

        [System.Data.SqlClient.SqlConnectionStringBuilder]$SqlConnectionStringBuilder = @{
            InitialCatalog = $Database
            DataSource = $Server
            IntegratedSecurity = $true
            PersistSecurityInfo = $true
        }

        if ($Credential) {
            $SqlConnectionStringBuilder.Add('Integrated Security', $false)
            $SqlConnectionStringBuilder.Add('User ID', $Credential.UserName.TrimStart('\'))
            $SqlConnectionStringBuilder.Add('Password', $Credential.GetNetworkCredential().Password)
        }

        [System.Data.SqlClient.SqlConnection]$SqlConnection = [System.Data.SqlClient.SqlConnection]::new($SqlConnectionStringBuilder.ConnectionString)
        [System.Data.SqlClient.SqlCommand]$SqlCommand = [System.Data.SqlClient.SqlCommand]@{Connection = $SqlConnection; CommandTimeout = $CommandTimeout}
        [System.Data.SqlClient.SqlDataAdapter]$SqlDataAdapter = [System.Data.SqlClient.SqlDataAdapter]@{SelectCommand = $SqlCommand}

        if (!$OnlyShowQuery) {
            $SqlDataAdapter.SelectCommand.Connection.Open()
            Write-Verbose -Message "ConnectionState: $($SqlDataAdapter.SelectCommand.Connection.State)"
        }
    }

    process {
        $Query | % {
            Write-Verbose -Message "CommandNumber: $Counter"

            if ($OnlyShowQuery) {
                $_
            } else {
                $SqlDataAdapter.SelectCommand.CommandText = $_
                [System.Data.DataSet]$DataSet = [System.Data.DataSet]::new()
                $RowCount = $SqlDataAdapter.Fill($DataSet)
                Write-Verbose -Message "Query: $_`n ReturnedRows: $RowCount"
                Write-Debug -Message "ConnectionString: '$($SqlConnectionStringBuilder.ConnectionString))'"
                if ($Raw) {
                    $DataSet
                } else {
                    $DataSet.Tables | % {$_.Rows}
                }
            }
            $Counter++
        }
    }

    end {
        Write-Verbose -Message "ConnectionState: $($SqlDataAdapter.SelectCommand.Connection.State)"
        if ($SqlDataAdapter.SelectCommand.Connection.State -ne [System.Data.ConnectionState]::Closed) {
            $SqlDataAdapter.SelectCommand.Connection.Close()
        }
        Write-Verbose -Message "ConnectionState: $($SqlDataAdapter.SelectCommand.Connection.State)"
    }
}

Function Add-SqlTable {
<#
.EXAMPLE
Get-Service | Create-SqlTable -Server sql -Database [test1] -Table [ps] -IdentityName id -OnlyShowQuery
CREATE TABLE ps (
    [id] [int] IDENTITY(1,1) NOT NULL,
    [Name] nvarchar(62) NOT NULL,
    [RequiredServices] nvarchar(MAX) NOT NULL,
    [CanPauseAndContinue] nvarchar(8) NOT NULL,
    [CanShutdown] nvarchar(8) NOT NULL,
    [CanStop] nvarchar(6) NOT NULL,
    [DisplayName] nvarchar(178) NOT NULL,
    [DependentServices] nvarchar(MAX) NULL,
    [MachineName] nvarchar(2) NOT NULL,
    [ServiceName] nvarchar(62) NOT NULL,
    [ServicesDependedOn] nvarchar(MAX) NOT NULL,
    [ServiceHandle] nvarchar(MAX) NULL,
    [Status] nvarchar(10) NOT NULL,
    [ServiceType] nvarchar(51) NOT NULL,
    [StartType] nvarchar(9) NOT NULL,
    [Site] nvarchar(MAX) NULL,
    [Container] nvarchar(MAX) NULL
) ON [PRIMARY]
#>
    [CmdletBinding()]
    [Alias('Create-SqlTable','New-SqlTable')]
    param(
         [Parameter(Mandatory)][Alias('ServerInstance','SqlServer')][string]$Server
        ,[Parameter(Mandatory)][Alias('SqlDatabase')][string]$Database
        ,[Parameter(Mandatory)][Alias('SqlTable')][string]$Table
        ,[string]$IdentityName
        ,[double]$StringReserveMultiple
        ,[int]$TruncateString = 4000
        ,[ValidateCount(2,2)][int64[]]$IdentitySettings = @(1,1)
        ,[Parameter(Mandatory,ValueFromPipeline)][ValidateScript({@($_.psobject.Properties).Count})][Alias('Data')][object[]]$InputObject
        ,[switch]$OnlyShowQuery
    )

    begin {
        $Table = EscapeName -String $Table
        $Database = EscapeName -String $Database
        [hashtable]$AllowNullMap = @{$true = ' NULL'; $false = ' NOT NULL'}
        [objectlist]$InputObjects = @()
        [stringhashset]$PropertiesSet = [stringhashset]::new([StringComparer]::OrdinalIgnoreCase)
        [string]$ReturnChar = [string][char]10
        [string]$JoinChar = ',' + [string][char]10
        [string]$TabChar = [string][char]9
        [hashtable]$SqlQueryParam = @{}
        [hashtable]$ImportDataParam = @{}
        $PSBoundParameters.Keys -as [string[]] | % {
            if ($PassThruSqlcmdParam.Contains($_)) {$SqlQueryParam[$_] = $PSBoundParameters[$_]}
            if (@('StringReserveMultiple','TruncateString').Contains($_)) {$ImportDataParam[$_] = $PSBoundParameters[$_]}
        }
        Write-Verbose -Message "Collecting Properties StartTime: `n $([datetime]::Now.ToString('o'))"
    }
    process {
        $InputObject | % {
            $InputObjects.Add($_)
            $PropertiesSet.UnionWith([string[]]$_.psobject.Properties.Name)
        }
    }
    end {
        [string[]]$Properties = $PropertiesSet
        Write-Verbose -Message "`n Collecting Properties EndTime: `n $([datetime]::Now.ToString('o'))"
        Write-Verbose -Message "`n Property Count: $($Properties.Count)`n Property List:`n  $($Properties -join ',')"
        $TableTypes = $InputObjects | Select-Object -Property $Properties | ConvertToHashTable | ImportData -CreateTable @ImportDataParam -WarningAction SilentlyContinue
        $Types = $TableTypes.Types
        [string[]]$Lines = @()
        $Query = $Properties | % -Begin {
            if ($IdentityName) {$Lines += ($TabChar + "[$IdentityName] [bigint] IDENTITY($($IdentitySettings -join ',')) $($AllowNullMap[$false])")}
            "CREATE TABLE $Table (" + $ReturnChar
        } -Process {
            if ($Types.ContainsKey($_)) {
                $Lines += ($TabChar + "[$_] " + $Types[$_]['Type'] + $AllowNullMap[$Types[$_]['AllowNull']])
            }
        } -End {
            $Lines -join $JoinChar
            $ReturnChar
            ') ON [PRIMARY]'
        }

        Invoke-SqlCommand @SqlQueryParam -Query (-join $Query)
    }
}

Function Add-SqlRecord {
<#
.EXAMPLE
Get-Service | select -f 3 | Insert-SqlRecord -Server sql -Database test1 -Table ps -PassThru | select Name,ServiceName
Name          ServiceName
----          -----------
AarSvc_45a9d9 AarSvc_45a9d9
AJRouter      AJRouter
ALG           ALG
.EXAMPLE
Get-Service | select -f 3 -p Name,ServiceName | Insert-SqlRecord -Server sql -Database test1 -Table ps -PassThru -OnlyShowQuery
 INSERT INTO ps ([Name],[ServiceName]) OUTPUT INSERTED.* VALUES ('AarSvc_45a9d9','AarSvc_45a9d9')
 INSERT INTO ps ([Name],[ServiceName]) OUTPUT INSERTED.* VALUES ('AJRouter','AJRouter')
 INSERT INTO ps ([Name],[ServiceName]) OUTPUT INSERTED.* VALUES ('ALG','ALG')
.EXAMPLE
Get-Service | ? {!$_.DependentServices} | select -f 3 -p Name,ServiceName,DependentServices | Insert-SqlRecord -Server sql -Database test1 -Table ps -PassThru -OnlyShowQuery
 INSERT INTO ps ([ServiceName],[Name],[DependentServices]) OUTPUT INSERTED.* VALUES ('AarSvc_45a9d9','AarSvc_45a9d9','')
 INSERT INTO ps ([ServiceName],[Name],[DependentServices]) OUTPUT INSERTED.* VALUES ('AJRouter','AJRouter','')
 INSERT INTO ps ([ServiceName],[Name],[DependentServices]) OUTPUT INSERTED.* VALUES ('ALG','ALG','')
.EXAMPLE
Get-Service | ? {!$_.DependentServices} | select -f 3 -p Name,ServiceName,DependentServices | Insert-SqlRecord -Server sql -Database test1 -Table ps -PassThru -OnlyShowQuery -SkipNullOrEmpty -SkipNullOrWhiteSpace
 INSERT INTO ps ([Name],[ServiceName]) OUTPUT INSERTED.* VALUES ('AarSvc_45a9d9','AarSvc_45a9d9')
 INSERT INTO ps ([Name],[ServiceName]) OUTPUT INSERTED.* VALUES ('AJRouter','AJRouter')
 INSERT INTO ps ([Name],[ServiceName]) OUTPUT INSERTED.* VALUES ('ALG','ALG')
.EXAMPLE
Get-Service | % {Update-SqlRecord -Server sql -Database test1 -Table ps -Data $_ -Filter @{ServiceName = $_.ServiceName} -PassThru -InsertIfNotFound}
ACTION Name
------ ----
UPDATE MicrosoftEdgeElevationService
UPDATE MicrosoftSearchInBing
INSERT W32Time

#>
    [CmdletBinding()]
    [Alias('New-SqlRecord','Insert-SqlRecord')]
    param (
         [Parameter(Mandatory=$true)][Alias('ServerInstance','SqlServer')][String]$Server
        ,[Parameter(Mandatory=$true)][Alias('SqlDatabase')][String]$Database
        ,[Parameter(Mandatory=$true)][Alias('SqlTable')][String]$Table
        ,[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
            [ValidateScript({@($_.psobject.Properties).Count})]
            [Alias('Data')]
            [System.Array]$InputObject
        ,[alias('RowCount')][int]$Limit
        ,[Parameter(Mandatory=$false)][switch]$PassThru
        ,[PSCredential]$Credential
        ,[int]$CommandTimeout
        ,[string[]]$Property
        ,[switch]$SkipNullOrEmpty
        ,[switch]$SkipNullOrWhiteSpace
        ,[int]$TruncateString = 4000
        ,[switch]$OnlyShowQuery
    )

    Begin {
        $Table = EscapeName -String $Table
        $Database = EscapeName -String $Database

        $PSBoundParameters.Keys | ? {$PassThruSqlcmdParam.Contains($_)} | % -Begin {$SqlQueryParam = @{}} -Process {$SqlQueryParam[$_] = $PSBoundParameters[$_]}


        $PSBoundParameters.Keys -like 'SkipNull*' | % -Begin {$ConvertToHashTableParam = @{}} -Process {$ConvertToHashTableParam[$_] = [bool]($PSBoundParameters[$_].IsPresent)}
        if ($PSBoundParameters.ContainsKey('Property')) {$ConvertToHashTableParam['Property'] = $Property}
        $PSBoundParameters.Keys | ? {$('CreateTable','TruncateString').Contains($_)} | % -Begin {$ImportDataParam = @{}} -Process {$ImportDataParam[$_] = $PSBoundParameters[$_]}
        $OUTPUT = @{$true='OUTPUT INSERTED.*';$false=''}[$PSBoundParameters.ContainsKey('PassThru')]
        if ($Limit) {
            $RowCount = "SET ROWCOUNT $Limit;"
        } else {
            $RowCount = ''
        }
    }

    Process {
        $InputObject | % {
            if ($_.psobject.TypeNames -like '*System.Collections*') {
                if (!$ConvertToHashTableParam.Count) {
                    $Data = $_
                } else {
                    $Data = New-Object -TypeName PSCustomObject -Property $_ | ConvertToHashTable @ConvertToHashTableParam
                }
            } else {
                $Data = $_ | ConvertToHashTable @ConvertToHashTableParam
            }

            $iData = ImportData -HashTable $Data @ImportDataParam
            $DataKeys = $iData.Keys
            $DataValues = $iData.Values

            if ($DataKeys) {
                $columns = $DataKeys -join '],['
                $values = $DataValues -join ","
                Invoke-SqlCommand @SqlQueryParam -Query "$RowCount INSERT INTO $Table ([$columns]) $OUTPUT VALUES ($values)"
            } else {
                Write-Warning -Message "null data object: $($_ | ConvertTo-Json -Compress)"
            }
        }
    }

    End {}
}

Function Edit-SqlRecord {
<#
.EXAMPLE
Get-Service | ? {!$_.DependentServices} | select -f 3 -p Name,ServiceName,DependentServices | % {Update-SqlRecord -Server sql -Database test1 -Table ps -Data $_ -Filter @{ServiceName = $_.ServiceName} -PassThru -SkipNullOrWhiteSpace}
 UPDATE ps SET [Name] = 'AarSvc_45a9d9',[ServiceName] = 'AarSvc_45a9d9' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = 'AarSvc_45a9d9'
 UPDATE ps SET [Name] = 'AJRouter',[ServiceName] = 'AJRouter' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = 'AJRouter'
 UPDATE ps SET [Name] = 'ALG',[ServiceName] = 'ALG' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = 'ALG'
.EXAMPLE
Get-Service | ? {!$_.DependentServices} | select -f 3 -p Name,ServiceName,DependentServices | % {Update-SqlRecord -Server sql -Database test1 -Table ps -Data $_ -FilterString "[ServiceName] = $($_.ServiceName)" -PassThru -OnlyShowQuery -SkipNullOrWhiteSpace}
 UPDATE ps SET [Name] = 'AarSvc_45a9d9',[ServiceName] = 'AarSvc_45a9d9' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = AarSvc_45a9d9
 UPDATE ps SET [Name] = 'AJRouter',[ServiceName] = 'AJRouter' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = AJRouter
 UPDATE ps SET [Name] = 'ALG',[ServiceName] = 'ALG' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = ALG
.EXAMPLE
Get-Service | ? {!$_.DependentServices} | select -f 3 -p Name,ServiceName,DependentServices | % {Update-SqlRecord -Server sql -Database test1 -Table ps -Data $_ -FilterString "[ServiceName] = $($_.ServiceName)" -PassThru -SkipNullOrWhiteSpace -InsertIfNotFound -OnlyShowQuery}
 UPDATE ps SET [Name] = 'AarSvc_45a9d9',[ServiceName] = 'AarSvc_45a9d9' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = AarSvc_45a9d9 IF @@ROWCOUNT = 0 INSERT INTO ps ([Name],[ServiceName]) OUTPUT 'INSERT' AS [ACTION], INSERTED.* VALUES ('AarSvc_45a9d9','AarSvc_45a9d9')
 UPDATE ps SET [Name] = 'AJRouter',[ServiceName] = 'AJRouter' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = AJRouter IF @@ROWCOUNT = 0 INSERT INTO ps ([Name],[ServiceName]) OUTPUT 'INSERT' AS [ACTION], INSERTED.* VALUES ('AJRouter','AJRouter')
 UPDATE ps SET [Name] = 'ALG',[ServiceName] = 'ALG' OUTPUT 'UPDATE' AS [ACTION], INSERTED.* WHERE [ServiceName] = ALG IF @@ROWCOUNT = 0 INSERT INTO ps ([Name],[ServiceName]) OUTPUT 'INSERT' AS [ACTION], INSERTED.* VALUES ('ALG','ALG')
#>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    [Alias('Update-SqlRecord','Set-SqlRecord')]
    param (
         [Parameter(Mandatory=$true)][Alias('ServerInstance','SqlServer')][String]$Server
        ,[Parameter(Mandatory=$true)][Alias('SqlDatabase')][String]$Database
        ,[Parameter(Mandatory=$true)][Alias('SqlTable')][String]$Table
        ,[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
            [ValidateScript({@($_.psobject.Properties).Count})]
            [Alias('Data')]
            [System.Array]$InputObject
        ,[Parameter(Mandatory=$true,ParameterSetName='Filter')]
            [ValidateScript({@($_.psobject.Properties).Count})]
            [HashTable]$Filter
        ,[Parameter(Mandatory=$false,ParameterSetName='Filter')][ValidateSet('AND','OR')][string]$FilterCondition = 'AND'
        ,[Parameter(Mandatory=$true,ParameterSetName='FilterString')][string]$FilterString
        ,[Parameter(Mandatory=$false)][switch]$InsertIfNotFound
        ,[alias('RowCount')][int]$Limit
        ,[Parameter(Mandatory=$false)][switch]$PassThru
        ,[PSCredential]$Credential
        ,[int]$CommandTimeout
        ,[string[]]$Property
        ,[switch]$SkipNullOrEmpty
        ,[switch]$SkipNullOrWhiteSpace
        ,[int]$TruncateString = 4000
        ,[switch]$OnlyShowQuery
    )

    Begin {
        $Table = EscapeName -String $Table
        $Database = EscapeName -String $Database
        $PSBoundParameters.Keys | ? {$PassThruSqlcmdParam.Contains($_)} | % -Begin {$SqlQueryParam = @{}} -Process {$SqlQueryParam[$_] = $PSBoundParameters[$_]}
        $PSBoundParameters.Keys -like 'SkipNull*' | % -Begin {$ConvertToHashTableParam = @{}} -Process {$ConvertToHashTableParam[$_] = [bool]($PSBoundParameters[$_].IsPresent)}
        if ($PSBoundParameters.ContainsKey('Property')) {$ConvertToHashTableParam['Property'] = $Property}
        $PSBoundParameters.Keys | ? {$('CreateTable','TruncateString').Contains($_)} | % -Begin {$ImportDataParam = @{}} -Process {$ImportDataParam[$_] = $PSBoundParameters[$_]}
        $OUTPUT = @{$true=@{UPDATE = "OUTPUT 'UPDATE' AS [ACTION], INSERTED.*"; INSERT = "OUTPUT 'INSERT' AS [ACTION], INSERTED.*"};$false=@{}}[$PSBoundParameters.ContainsKey('PassThru')]
        if ($Limit) {
            $RowCount = "SET ROWCOUNT $Limit;"
        } else {
            $RowCount = ''
        }

        [string[]]$Queries = @()
    }

    Process {
        $InputObject | % {
            if ($_.psobject.TypeNames -like 'System.Collections.*') {
                if (!$ConvertToHashTableParam.Count) {
                    $Data = $_
                } else {
                    $Data = New-Object -TypeName PSCustomObject -Property $_ | ConvertToHashTable @ConvertToHashTableParam
                }
            } else {
                $Data = $_ | ConvertToHashTable @ConvertToHashTableParam
            }

            $iData = ImportData -HashTable $Data
            $DataKeys = $iData.Keys
            $DataValues = $iData.Values

            $columns = $DataKeys -join '],['
            $values = $DataValues -join ","

            [string[]]$sets = @()
            for ($i = 0; $i -lt $DataKeys.Count; $i++) {
                $sets += "[$($DataKeys[$i])] = $($DataValues[$i])"
            }

            $set = $sets -join ','

            if ($Filter) {
                $iFilter = ImportData -HashTable $Filter
                $FilterKeys = $iFilter.Keys
                $FilterValues = $iFilter.Values

                [string[]]$wheres = @()
                for ($i = 0; $i -lt $FilterKeys.Count; $i++) {
                    $key = $FilterKeys[$i]
                    $value = $FilterValues[$i].Replace('*','%')
                    $operator = if ($value -like '*%*') {'like'} else {'='}
                    $wheres += "[$key] $operator $value"
                }

                $where = $wheres -join " $FilterCondition "
            } else {
                $where = $FilterString
            }

            if ($InsertIfNotFound) {
                $Query = "$RowCount UPDATE $Table SET $set $($OUTPUT['UPDATE']) WHERE $where IF @@ROWCOUNT = 0 INSERT INTO $Table ([$columns]) $($OUTPUT['INSERT']) VALUES ($values)"
            } else {
                $Query = "$RowCount UPDATE $Table SET $set $($OUTPUT['UPDATE']) WHERE $where"
            }
            if ($DataKeys) {
                $Queries += $Query
            } else {
                Write-Warning -Message "null data object: $($_ | ConvertTo-Json -Compress)"
            }
        }
    }

    End {
        Invoke-SqlCommand @SqlQueryParam -Query $Queries
    }
}

Function Remove-SqlRecord {
<#
.EXAMPLE
Remove-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Filter @{ServiceName = 'w32time'} -PassThru -OnlyShowQuery
 DELETE ps OUTPUT DELETED.* WHERE [ServiceName] = 'w32time'
.EXAMPLE
Remove-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Filter @{ServiceName = 'w32time'} -PassThru

Name     RequiredServices CanPauseAndContinue CanShutdown CanStop DependentServices MachineName ServiceName ServicesDependedOn
----     ---------------- ------------------- ----------- ------- ----------------- ----------- ----------- ------------------
W32Time                   False               False       False                     .           W32Time
.EXAMPLE
Remove-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -FilterString "[ServiceName] LIKE 'w32time'" -PassThru

Name     RequiredServices CanPauseAndContinue CanShutdown CanStop DependentServices MachineName ServiceName ServicesDependedOn
----     ---------------- ------------------- ----------- ------- ----------------- ----------- ----------- ------------------
W32Time                   False               False       False                     .           W32Time
#>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    param (
        [Parameter(Mandatory=$true)][Alias('ServerInstance','SqlServer')][String]$Server
        ,[Parameter(Mandatory=$true)][Alias('SqlDatabase')][String]$Database
        ,[Parameter(Mandatory=$true)][Alias('SqlTable')][String]$Table
        ,[Parameter(Mandatory=$true,ParameterSetName='Filter')][Hashtable]$Filter
        ,[Parameter(Mandatory=$false,ParameterSetName='Filter')][ValidateSet('AND','OR')][string]$FilterCondition = 'AND'
        ,[Parameter(Mandatory=$true,ParameterSetName='FilterString')][string]$FilterString
        ,[alias('RowCount')][int]$Limit
        ,[Parameter(Mandatory=$false)][switch]$PassThru
        ,[PSCredential]$Credential
        ,[int]$CommandTimeout
        ,[switch]$OnlyShowQuery
    )

    $Table = EscapeName -String $Table
    $Database = EscapeName -String $Database

    $PSBoundParameters.Keys | ? {$PassThruSqlcmdParam.Contains($_)} | % -Begin {$SqlQueryParam = @{}} -Process {$SqlQueryParam[$_] = $PSBoundParameters[$_]}

    if ($Limit) {
        $RowCount = "SET ROWCOUNT $Limit;"
    } else {
        $RowCount = ''
    }

    $OUTPUT = @{$true='OUTPUT DELETED.*';$false=''}[$PSBoundParameters.ContainsKey('PassThru')]

    if ($Filter) {
        $iFilter = ImportData -HashTable $Filter
        $FilterKeys = $iFilter.Keys
        $FilterValues = $iFilter.Values

        [string[]]$wheres = @()
        for ($i = 0; $i -lt $FilterKeys.Count; $i++) {
            $key = $FilterKeys[$i]
            $value = $FilterValues[$i].Replace('*','%')
            $operator = if ($value -like '*%*') {'like'} else {'='}
            $wheres += "[$key] $operator $value"
        }

        $where = $wheres -join " $FilterCondition "
    } else {
        $where = $FilterString
    }

    Invoke-SqlCommand @SqlQueryParam -Query "$RowCount DELETE $Table $OUTPUT WHERE $where"

}

Function Get-SqlRecord {
<#
.EXAMPLE
Get-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Filter @{Name = 'win*'}

Name                ServiceType                        Status
----                -----------                        ------
WinHttpAutoProxySvc Win32OwnProcess, Win32ShareProcess Running
WinDefend           Win32OwnProcess                    Running
Winmgmt             Win32OwnProcess                    Running
WinRM               Win32OwnProcess, Win32ShareProcess Running
.EXAMPLE
Get-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Filter @{Name = 'win*'} -SortBy ServiceType -SortDirection ASC -Property Name,ServiceType,Status -RowNumberSortBy ServiceType -RowNumberPartition ServiceType

RowNumber Name                ServiceType                        Status
--------- ----                -----------                        ------
        1 WinDefend           Win32OwnProcess                    Running
        2 Winmgmt             Win32OwnProcess                    Running
        1 WinRM               Win32OwnProcess, Win32ShareProcess Running
        2 WinHttpAutoProxySvc Win32OwnProcess, Win32ShareProcess Running
.EXAMPLE
Get-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Filter @{Name = 'win*'} -Property Status,'COUNT(*) AS Counter' -GroupBy Status

Status  Counter
------  -------
Running       4
.EXAMPLE
Get-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Property Status,'COUNT(*) AS Counter' -GroupBy Status

Status  Counter
------  -------
Running     190
Stopped     167
.EXAMPLE
Get-SqlRecord -Server sql -SqlDatabase test1 -SqlTable ps -Property Status,'COUNT(*) AS Counter' -GroupBy Status -OnlyShowQuery
 SELECT   Status,COUNT(*) AS Counter FROM ps   GROUP BY Status
#>
    [CmdletBinding(DefaultParameterSetName = 'Filter')]
    param (
        [Parameter(Mandatory=$true)][Alias('ServerInstance','SqlServer')][String]$Server
        ,[Parameter(Mandatory=$true)][Alias('SqlDatabase')][String]$Database
        ,[Parameter(Mandatory=$true)][Alias('SqlTable')][String]$Table
        ,[string[]]$Property = '*'
        ,[alias('Count')][int]$Top
        ,[alias('RowCount')][int]$Limit
        ,[string]$SortBy
        ,[string][ValidateSet('ASC','DESC')]$SortDirection = 'ASC'
        ,[Parameter(ParameterSetName='Filter')][Hashtable]$Filter
        ,[Parameter(ParameterSetName='Filter')][ValidateSet('AND','OR')][string]$FilterCondition = 'AND'
        ,[Parameter(ParameterSetName='FilterString')][string]$FilterString
        ,[PSCredential]$Credential
        ,[string[]]$RowNumberSortBy
        ,[string][ValidateSet('ASC','DESC')]$RowNumberSortDirection = 'ASC'
        ,[string[]]$RowNumberPartition
        ,[string[]]$GroupBy
        ,[string]$Having
        ,[switch]$OnlyShowQuery
        ,[int]$CommandTimeout
    )

    $Table = EscapeName -String $Table
    $Database = EscapeName -String $Database

    $PSBoundParameters.Keys | ? {$PassThruSqlcmdParam.Contains($_)} | % -Begin {$SqlQueryParam = @{}} -Process {$SqlQueryParam[$_] = $PSBoundParameters[$_]}

    if ($RowNumberSortBy) {
        $RowNumberSortBy = 'ORDER BY ' + ($RowNumberSortBy -join ',') + " $RowNumberSortDirection"
        if ($RowNumberPartition) {
            $RowNumberPartitions = 'PARTITION BY ' + ($RowNumberPartition -join ',')
        }
        $RowNumber = " ROW_NUMBER() OVER($RowNumberPartitions $RowNumberSortBy $RowNumberSortDesc) AS [RowNumber], "
    }

    if ($Top) {
        $Count = "TOP $Top"
    } else {
        $Count = ''
    }

    if ($Limit) {
        $RowCount = "SET ROWCOUNT $Limit;"
    } else {
        $RowCount = ''
    }

    $Properties = $Property -join ','

    if ($SortBy) {
        $SortString = " ORDER BY $SortBy $SortDirection"
    } else {
        $SortString = ''
    }

    if ($GroupBy) {
        $GroupBy = 'GROUP BY ' + ($GroupBy -join ',')
    }

    if ($GroupBy -and $Having) {
        $Having = "HAVING $Having"
    } else {
        $Having = ''
    }

    if ($Filter) {
        $iFilter = ImportData -HashTable $Filter
        $FilterKeys = $iFilter.Keys
        $FilterValues = $iFilter.Values

        [string[]]$wheres = @()
        for ($i = 0; $i -lt $FilterKeys.Count; $i++) {
            $key = $FilterKeys[$i]
            $value = $FilterValues[$i].Replace('*','%')
            $operator = if ($value -like '*%*') {'like'} else {'='}
            $wheres += "[$key] $operator $value"
        }

        $where = 'WHERE ' + ($wheres -join " $FilterCondition ")
    } elseif ($FilterString) {
        $where = 'WHERE ' + $FilterString
    } else {
        $where = ''
    }

    Invoke-SqlCommand @SqlQueryParam -Query "$RowCount SELECT $Count $RowNumber $Properties FROM $Table $where $SortString $GroupBy $Having"

}

Filter ConvertToHashTable {
    [OutputType('System.Collections.IDictionary')]
    param(
         [object[]]$Property = @()
        ,[object[]]$ExcludeProperty = @()
        ,[switch]$SkipNullOrEmpty
        ,[switch]$SkipNullOrWhiteSpace
    )
    begin {
        [hashtable]$paramSelect = @{}
        if ($Property) {$paramSelect['Property'] = $Property}
        if ($ExcludeProperty) {$paramSelect['ExcludeProperty'] = $ExcludeProperty}
        if ($SkipNullOrEmpty -or $SkipNullOrWhiteSpace) {
            $fn = {
                $Hash[$_.Name] = $_.Value
            }
        } else {
            $fn = {
                if (!(!$_.Value -or [string]::IsNullOrEmpty($_.Value) -or [string]::IsNullOrWhiteSpace($_.Value))) {
                    $Hash[$_.Name] = $_.Value
                }
            }
        }
    }
    process {
        [dict]$Hash = [dict]::new([StringComparer]::OrdinalIgnoreCase)
        $_ | Select-Object @paramSelect -ErrorAction SilentlyContinue | % {$_.psobject.Properties.ForEach($fn)}
        $Hash
    }
    end {}
}

Function ImportData {
    [CmdletBinding()]
    param(
         [Parameter(Mandatory,ValueFromPipeline)][Alias('Data','Dictionary','HashTables')][System.Collections.IDictionary[]]$Dictionaries
        ,[double]$StringReserveMultiple = 1.5
        ,[int64]$TruncateString = 4000
        ,[switch]$CreateTable
    )

    Begin {
        [dict]$Types = [dict]::new([StringComparer]::OrdinalIgnoreCase)

        # [Dictionary[type,string]]$TypeMap = @{}
        [hashtable]$TypeMap = @{
            'System.Boolean' = 'bit'
            'System.TimeSpan' = 'time(7)'
            'System.Int16' = 'smallint'
            'System.Int32' = 'int'
            'System.Int64' = 'bigint'
            'System.Single' = 'float'
            'System.Double' = 'float'
            'System.Decimal' = 'float'
        }

        Filter PrepareFor_Json {
            param(
                [switch]$Compress
            )
            begin {
                [stringlist]$Strings = @()
            }
            process {
                $String = if ($_ -is [System.Collections.IDictionary]) {
                    $_.GetEnumerator() | % -Begin {$Hash = [ordered]@{}} -Process {$Hash[$_.Key] = $_.Value} -End {$Hash}
                } elseif ($_ -is [System.String]) {
                    $_
                } elseif ($_ -is [System.Enum]) {
                    $_.ToString()
                } elseif ($_.GetType().IsPrimitive) {
                    $_
                } elseif ($_ -is [System.DateTime]) {
                    $_.ToString('yyyy-MM-ddTHH:mm:ss.fff')
                }  elseif ($_ -is [System.TimeSpan]) {
                    $_.ToString('hh\:mm\:ss\.fffffff')
                } elseif ($_.psobject.Properties) {
                    $_.psobject.Properties | % -Begin {$Hash = [ordered]@{}} -Process {$Hash[$_.Key] = $_.Value} -End {$Hash}
                } else {
                    "$_"
                }
                $jString = ConvertTo-Json @PSBoundParameters -InputObject $String
                $Strings.Add($jString)
            }
            end {
                if ($Strings.Count -gt 1) {
                    "[$($Strings -join ',')]"
                } else {
                    $Strings
                }
            }
        }
    }

    Process {
        $Dictionaries | % {
            $Dictionary = $_
            [string[]]$Keys = $Dictionary.Keys
            [object[]]$Values = $Keys | % {
                $Key = $_
                $Value = $Dictionary[$_]

                [bool]$quote = $false

                try {
                    if (!$Value) {
                        $Type = $null
                    } else {
                        $Type = $Value.GetType()
                    }
                } catch {
                    $Type = $null
                }

                if (!$Type -or $Value.GetType() -eq [System.DBNull]) {
                    $_Value = 'NULL'
                } elseif ($Type -in @([Int16],[int32],[int64])) {
                    $_Value = $Value
                } elseif ($Type -in @([float],[double],[decimal])) {
                    [string]$_Value = $Value.ToString().Replace(',','.')
                } elseif ($Value -is [string]) {
                    $quote = $true
                    [string]$_Value = $Value
                } elseif ($Value -is [System.Enum]) {
                    $quote = $true
                    [string]$_Value = $Value
                } elseif ($Value -is [bool]) {
                    $quote = $true
                    [string]$_Value = $Value
                } elseif ($Value -is [DateTime]) {
                    $quote = $true
                    [string]$_Value = $Value.ToString('yyyy-MM-ddTHH:mm:ss.fff')
                } elseif ($Value.psobject.TypeNames -like '*System.Collections*' -or $Value.psobject.TypeNames -like '*System.Array*') {
                    $quote = $true
                    [string]$_Value = $Value | PrepareFor_Json -Compress
                } elseif (!($Value.psobject.TypeNames -like 'System.ValueType') -and !($Value.psobject.TypeNames -like 'System.String')) {
                    $quote = $true
                    [string]$_Value = $Value | PrepareFor_Json -Compress
                } else {
                    $quote = $true
                    [string]$_Value = $Value
                }

                if ($quote) {
                    $_Value = $_Value.Replace($q,$qq)
                }

                if ($_Value.Length -gt $TruncateString) {
                    $_Value = -join ($_Value)[0..($TruncateString-1)]
                }

                if ($CreateTable) {
                    if (!$Types.ContainsKey($Key)) {
                        $Types[$Key] = @{
                            Type = $null
                            Length = 0
                            AllowNull = $false
                            MaxValue = 0
                        }
                    }

                    if (!$Type -or $null -eq $Value -or $Value.GetType() -eq [System.DBNull]) {
                        $Types[$Key]['AllowNull'] = $true
                    } else {
                        if ($Type -in @([int16],[int32],[int64],[float],[double],[decimal])) {
                            if (!$Types[$Key]['Type'] -or !$Types[$Key]['MaxValue']) {
                                $Types[$Key]['MaxValue'] = [System.Int32]::MaxValue
                                $Types[$Key]['Type'] = $TypeMap[$Type.FullName]
                            }
                            if ($Type::MaxValue -gt $Types[$Key]['MaxValue']) {
                                $Types[$Key]['MaxValue'] = $Type::MaxValue
                                $Types[$Key]['Type'] = $TypeMap[$Type.FullName]
                            }
                        } elseif ($Value -is [DateTime]) {
                            if (!$Types[$Key]['Type']) {
                                $Types[$Key]['Type'] = 'date'
                            }
                            if ($Value.TimeOfDay.TotalSeconds -ne 0 -and $Types[$Key]['Type'] -eq 'date') {
                                $Types[$Key]['Type'] = 'datetime'
                            }
                        } elseif ($Value.psobject.TypeNames -like '*System.Collections*' -or $Value.psobject.TypeNames -like '*System.Array*'){
                            $Types[$Key]['Length'] = 4000
                            $Types[$Key]['Type'] = 'nvarchar(MAX)'
                        } else {
                            $TrimLength = $_Value.Trim($q).Length

                            [int]$Length = $TrimLength * $StringReserveMultiple

                            if ($Length -le 4000) {
                                if ($TrimLength -gt $Types[$Key]['Length']) {
                                    $Types[$Key]['Length'] = $Length
                                    $Types[$Key]['Type'] = "nvarchar($Length)"
                                }
                            } else {
                                $Types[$Key]['Length'] = 4000
                                $Types[$Key]['Type'] = 'nvarchar(MAX)'
                            }
                        }


                    }

                    $Types.GetEnumerator() | % {
                        if (!$Types[$_.Key]['Type']) {
                            $Types[$_.Key]['Type'] = 4000
                            $Types[$_.Key]['Type'] = 'nvarchar(MAX)'
                        }
                    }
                }

                if ($quote) {
                    $_Value = $q + $_Value + $q
                }

                $_Value
            }
        }
    }

    End {
        [PSCustomObject]@{
            Keys = [string[]]$Keys
            Values = [object[]]$Values
            Types = $Types
        }
    }
}

Export-ModuleMember -Alias @(
    ,'New-SqlRecord'
    ,'Insert-SqlRecord'
    ,'Update-SqlRecord'
    ,'Set-SqlRecord'
    ,'Create-SqlTable'
    ,'New-SqlTable'
)

# Get-Date | insert-SqlRecord -OnlyShowQuery -Server s -Database d -Table t1 -Verbose
