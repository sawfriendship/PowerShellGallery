[string[]]$PassThruSqlcmdParam = @('Server','Database','Credential','CommandTimeout','OnlyShowQuery')
$q = "'"
$qq = "''"

# [System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('StringList', 'System.Collections.Generic.List[System.String]')
# [System.Management.Automation.PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('ObjectList', 'System.Collections.Generic.List[System.Object]')

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
         [Parameter(Mandatory=$true)][Alias('ServerInstance','SqlServer')][string]$Server
        ,[Parameter(Mandatory=$true)][Alias('SqlDatabase')][string]$Database
        ,[Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)][string[]]$Query
        ,[System.Management.Automation.PSCredential]$Credential
        ,[Alias('QueryTimeout')][int]$CommandTimeout = 30
        ,[switch]$OnlyShowQuery
        ,[switch]$Raw
    )
    Begin {
        $Counter = 1

        $SqlConnectionStringBuilderProperties = @{
            InitialCatalog = $Database
            DataSource = $Server
            IntegratedSecurity = $true
            PersistSecurityInfo = $true
        }

        if ($Credential) {
            $SqlConnectionStringBuilderProperties['IntegratedSecurity'] = $false
            $SqlConnectionStringBuilderProperties['UserID'] = $Credential.UserName.TrimStart('\')
            $SqlConnectionStringBuilderProperties['Password'] = $Credential.GetNetworkCredential().Password
        }

        $SqlConnectionStringBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder -Property $SqlConnectionStringBuilderProperties
        $ConnectionString = $SqlConnectionStringBuilder.ConnectionString

        $SqlDataAdapter = New-Object -TypeName System.Data.SqlClient.SqlDataAdapter -Property @{ `
            SelectCommand = New-Object -TypeName System.Data.SqlClient.SqlCommand -Property @{ `
                CommandTimeout = $CommandTimeout; `
                Connection = New-Object -TypeName System.Data.SqlClient.SqlConnection -Property @{ `
                    ConnectionString = $ConnectionString; `
                }
            }
        }

        if (!$OnlyShowQuery) {
            $SqlDataAdapter.SelectCommand.Connection.Open()
        }
    }
    Process {
        $Query | % {
            if (!$OnlyShowQuery) {
                Write-Verbose -Message "ConnectionState: $($SqlDataAdapter.SelectCommand.Connection.State)"
            }

            Write-Verbose -Message "CommandNumber: $Counter"

            if ($OnlyShowQuery) {
                $_
            } else {
                $SqlDataAdapter.SelectCommand.CommandText = $_
                $DataSet = New-Object -TypeName System.Data.DataSet
                $RowCount = $SqlDataAdapter.Fill($DataSet)
                Write-Verbose -Message "ReturnedRows: $RowCount"
                Write-Verbose -Message "Query: $_"
                Write-Debug -Message "ConnectionString: '$ConnectionString'"
                if ($Raw) {
                    $DataSet
                } else {
                    $DataSet.Tables | % {$_.Rows}
                }
            }
            $Counter++
        }
    }
    End {
        if ($SqlDataAdapter.SelectCommand.Connection.State -ne [System.Data.ConnectionState]::Closed) {
            $SqlDataAdapter.SelectCommand.Connection.Close()
        }
    }
}

Function Add-SqlTable {
<#
.EXAMPLE
Get-Service | Create-SqlTable -Server sql -Database [test1] -Table [ps] -OnlyShowQuery
CREATE TABLE ps (
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
         [Parameter(Mandatory=$true)][Alias('ServerInstance','SqlServer')][String]$Server
        ,[Parameter(Mandatory=$true)][Alias('SqlDatabase')][String]$Database
        ,[Parameter(Mandatory=$true)][Alias('SqlTable')][String]$Table
        ,[string]$IdentityName
        ,[double]$StringReserveMultiple
        ,[int]$TruncateString = 4000
        ,[System.Array]$IdentitySettings = @(1,1)
        ,[Parameter(Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({@($_.psobject.Properties).Count})]
            [Alias('Data')]
            [System.Array]$InputObject
        ,[switch]$OnlyShowQuery
    )

    Begin {
        $PSBoundParameters.Keys | ? {$PassThruSqlcmdParam.Contains($_)} | % -Begin {$SqlQueryParam = @{}} -Process {$SqlQueryParam[$_] = $PSBoundParameters[$_]}
        $InputObjects = New-Object -TypeName System.Collections.ArrayList
        $Properties = New-Object -TypeName System.Collections.ArrayList
        [string]$ReturnChar = [string][char]10
        [string]$JoinChar = ',' + [string][char]10
        [string]$TabChar = [string][char]9
        $PSBoundParameters.Keys | ? {$('StringReserveMultiple','TruncateString').Contains($_)} | % -Begin {$ImportDataParam = @{}} -Process {$ImportDataParam[$_] = $PSBoundParameters[$_]}
    }
    Process {
        $InputObject | % {
            [void]$InputObjects.Add($_)

            $_.psobject.Properties | % {
                if (!$Properties.Contains($_.Name)) {
                    [void]$Properties.Add($_.Name)
                }
            }
        }
    }
    End {
        $TableTypes = $InputObjects | Select-Object -Property $Properties | ConvertTo_HashTable | Import_Data -CreateTable @ImportDataParam
        $Types = $TableTypes.Types
        $Query = $Properties | % -Begin {
            [string[]]$Lines = @()
            if ($IdentityName) {$Lines += ($TabChar + "[$IdentityName] [int] IDENTITY($($IdentitySettings -join ',')) NOT NULL")}
            "CREATE TABLE $Table (" + $ReturnChar
        } -Process {
            if ($Types.ContainsKey($_)) {
                $Lines += ($TabChar + "[$_] " + $Types[$_]['Type'] + @{$true = ' NULL'; $false = ' NOT NULL'}[$Types[$_]['AllowNull']])
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
        ,[System.Management.Automation.PSCredential]$Credential
        ,[int]$CommandTimeout
        ,[string[]]$Property
        ,[switch]$SkipNullOrEmpty
        ,[switch]$SkipNullOrWhiteSpace
        ,[int]$TruncateString = 4000
        ,[switch]$OnlyShowQuery
    )

    Begin {
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
                    $Data = New-Object -TypeName PSCustomObject -Property $_ | ConvertTo_HashTable @ConvertToHashTableParam
                }
            } else {
                $Data = $_ | ConvertTo_HashTable @ConvertToHashTableParam
            }

            $iData = Import_Data -HashTable $Data @ImportDataParam
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
        ,[System.Management.Automation.PSCredential]$Credential
        ,[int]$CommandTimeout
        ,[string[]]$Property
        ,[switch]$SkipNullOrEmpty
        ,[switch]$SkipNullOrWhiteSpace
        ,[int]$TruncateString = 4000
        ,[switch]$OnlyShowQuery
    )

    Begin {
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
                    $Data = New-Object -TypeName PSCustomObject -Property $_ | ConvertTo_HashTable @ConvertToHashTableParam
                }
            } else {
                $Data = $_ | ConvertTo_HashTable @ConvertToHashTableParam
            }

            $iData = Import_Data -HashTable $Data
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
                $iFilter = Import_Data -HashTable $Filter
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
        ,[System.Management.Automation.PSCredential]$Credential
        ,[int]$CommandTimeout
        ,[switch]$OnlyShowQuery
    )

    $PSBoundParameters.Keys | ? {$PassThruSqlcmdParam.Contains($_)} | % -Begin {$SqlQueryParam = @{}} -Process {$SqlQueryParam[$_] = $PSBoundParameters[$_]}

    if ($Limit) {
        $RowCount = "SET ROWCOUNT $Limit;"
    } else {
        $RowCount = ''
    }

    $OUTPUT = @{$true='OUTPUT DELETED.*';$false=''}[$PSBoundParameters.ContainsKey('PassThru')]

    if ($Filter) {
        $iFilter = Import_Data -HashTable $Filter
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
        ,[System.Management.Automation.PSCredential]$Credential
        ,[string[]]$RowNumberSortBy
        ,[string][ValidateSet('ASC','DESC')]$RowNumberSortDirection = 'ASC'
        ,[string[]]$RowNumberPartition
        ,[string[]]$GroupBy
        ,[string]$Having
        ,[switch]$OnlyShowQuery
        ,[int]$CommandTimeout
    )

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
        $iFilter = Import_Data -HashTable $Filter
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

Filter ConvertTo_HashTable {
    param(
         [System.Array]$Property = @()
        ,[System.Array]$ExcludeProperty = @()
        ,[switch]$SkipNullOrEmpty
        ,[switch]$SkipNullOrWhiteSpace
    )
    Begin {
        $paramSelect = @{'ErrorAction' = 'SilentlyContinue'}
        if ($Property) {$paramSelect['Property'] = $Property}
        if ($ExcludeProperty) {$paramSelect['ExcludeProperty'] = $ExcludeProperty}
        $Skip = ($SkipNullOrEmpty -or $SkipNullOrWhiteSpace)
    }
    Process {
        $Hash = @{}
        if (!$Skip) {
            $_ | Select-Object @paramSelect | % {$_.psobject.Properties} | % {
                $Hash[$_.Name] = $_.Value
            }
        } else {
            $_ | Select-Object @paramSelect | % {$_.psobject.Properties} | % {
                if (!(($SkipNullOrEmpty -and [string]::IsNullOrEmpty($_.Value)) -or ($SkipNullOrWhiteSpace -and [string]::IsNullOrWhiteSpace($_.Value)))) {
                    $Hash[$_.Name] = $_.Value
                }
            }
        }
        $Hash
    }
    End {}
}

Function Import_Data {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({@($_.psobject.Properties).Count})]
            [Alias('Data')]
            [HashTable[]]$HashTable
        ,[double]$StringReserveMultiple = 1.5
        ,[int]$TruncateString = 4000
        ,[switch]$CreateTable
    )

    Begin {
        $Types = @{}

        $TypeMap = @{
            'System.Int32' = 'int'
            'System.Int64' = 'bigint'
            'System.Single' = 'float'
            'System.Double' = 'float'
            'System.Decimal' = 'float'
        }

        Filter ConvertTo-Json_ {
            param(
                [switch]$Compress
            )
            Begin {$Strings = New-Object -TypeName System.Collections.ArrayList}
            Process {
                $String = if ($_.psobject.TypeNames -like 'System.Collections.*') {
                    $_.GetEnumerator() | % -Begin {$Hash = @{}} -Process {$Hash[$_.Name.ToString()] = $_.Value} -End {ConvertTo-Json @PSBoundParameters -InputObject $Hash}
                } elseif ($_.psobject.TypeNames -like 'System.DateTime') {
                    ConvertTo-Json @PSBoundParameters -InputObject $_.ToString('yyyy-MM-ddTHH:mm:ss.fff')
                } elseif (!($_.psobject.TypeNames -like 'System.ValueType') -and !($_.psobject.TypeNames -like 'System.String')) {
                    $_.psobject.Properties | % -Begin {$Hash = @{}} -Process {$Hash[$_.Name.ToString()] = $_.Value} -End {ConvertTo-Json @PSBoundParameters -InputObject $Hash}
                } else {
                    ConvertTo-Json @PSBoundParameters -InputObject $_.ToString()
                }
                [void]$Strings.Add($String)
            }
            End {
                if ($Strings.Count -ge 1) {
                    '[' + ($Strings -join ',') + ']'
                } else {
                    $Strings
                }
            }
        }

    }

    Process {
        $HashTable | % {
            $_HashTable = $_
            $Keys = $_HashTable.Keys
            $Values = $Keys | % {
                $Key = $_
                $Value = $_HashTable[$Key]
                [bool]$quote = $false

                try {
                    $Type = $Value.GetType()
                } catch {
                    $Type = $null
                }

                if (!$Type -or $null -eq $Value -or $Value.GetType() -eq [System.DBNull]) {
                    $_Value = 'NULL'
                } elseif ($Value.GetType() -in @([int],[int64])) {
                    $_Value = $Value
                } elseif ($Value.GetType() -in @([Float],[Double],[Decimal])) {
                    [string]$_Value = $Value.ToString().Replace(',','.')
                } elseif ($Value -is [bool]) {
                    $quote = $true
                    [string]$_Value = $Value
                } elseif ($Value -is [DateTime]) {
                    $quote = $true
                    [string]$_Value = $Value.ToString('yyyy-MM-ddTHH:mm:ss.fff')
                } elseif ($Value.psobject.TypeNames -like '*System.Collections*' -or $Value.psobject.TypeNames -like '*System.Array*') {
                    $quote = $true
                    [string]$_Value = $Value | ConvertTo-Json_ -Compress
                } elseif (!($Value.psobject.TypeNames -like 'System.ValueType') -and !($Value.psobject.TypeNames -like 'System.String')) {
                    $quote = $true
                    [string]$_Value = $Value | ConvertTo-Json_ -Compress
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
                        if ($Type -in @([int],[int64],[Float],[Double],[Decimal])) {
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
                        if (!$Types[$_.Name]['Type']) {
                            $Types[$_.Name]['Type'] = 4000
                            $Types[$_.Name]['Type'] = 'nvarchar(MAX)'
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
            Values = [string[]]$Values
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
