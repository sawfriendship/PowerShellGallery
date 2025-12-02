
<#PSScriptInfo

.VERSION 1.0.1

.GUID 8ea6ddc2-4d42-44cd-b7a1-9d5d04aea45d

.AUTHOR saw-friendship

.COMPANYNAME

.COPYRIGHT

.TAGS
Install Flask web-framework on IIS web-server
.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<#

.DESCRIPTION
Install Flask web-framework on IIS web-server

#>

#Requires -RunAsAdministrator

param (
    [Parameter(Mandatory)][System.String]$SiteName,
    [switch]$Add2Hosts,
    [switch]$Http2Https
)

$SiteName = $SiteName -replace '\s*'

$v = py -V
Write-Host $v -ForegroundColor Green

if ($Add2Hosts) {
    Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "127.0.0.1 `t $SiteName"
}

$AllFeatures = (Dism.exe /Online /English /Get-Features /Format:Table) -like '*[a-z]*|*[a-z]*' -replace '\s' | ConvertFrom-Csv -Delimiter '|' -Header Name, State | Select-Object -Skip 1 | Sort-Object -Property Name

$InstalledFeatures = $AllFeatures | ? { $_.State -eq 'Enabled' }

$Features = @(
    , 'IIS-WebServerRole'
    , 'IIS-WebServer'
    , 'IIS-WebServerManagementTools'
    , 'IIS-ApplicationDevelopment'
    , 'IIS-CGI'
    , 'IIS-DefaultDocument'
    , 'IIS-HttpErrors'
    , 'IIS-HttpRedirect'
    , 'IIS-HttpLogging'
    , 'IIS-BasicAuthentication'
)

$Features | ? { $_ -notin $InstalledFeatures.Name } | % {
    Write-Host "Install Feature '$_'" -ForegroundColor Yellow
    Dism.exe /Online /English /Enable-Feature:$_
}

# ----------------------------------

mkdir "C:\inetpub\$SiteName\static" -Force

$vEnvName = 'venv'
$SitePath = "C:\inetpub\$SiteName\"
$PythonPath = "C:\inetpub\$SiteName\$vEnvName"

cd $SitePath

py -m venv $vEnvName

# ----------------------------------
.\venv\Scripts\Activate.ps1
# ----------------------------------
py -m pip install --upgrade pip wheel
py -m pip install --upgrade wfastcgi flask SQLAlchemy
# ----------------------------------
.\venv\Scripts\wfastcgi-enable.exe
# ----------------------------------
# IIS Config
Import-Module WebAdministration
New-Website -Name $SiteName -IPAddress * -Port 80 -HostHeader $SiteName -PhysicalPath $SitePath
#
C:\Windows\System32\inetsrv\appcmd.exe unlock config -section:system.webServer/handlers
New-WebHandler -PSPath "IIS:\Sites\$SiteName" -Name PythonHandler -Path * -Verb * -Modules FastCgiModule -ScriptProcessor "$PythonPath\Scripts\python.exe|$PythonPath\lib\site-packages\wfastcgi.py" -ResourceType Unspecified -RequiredAccess Script -Force
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "PYTHONPATH"; value = "$PythonPath" }
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "WSGI_HANDLER"; value = "main.app" }
# ----------------------------------
# IIS_IUSRS must have rights to the directory
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "WSGI_LOG"; value = "$SitePath\wfastcgi.log" }
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "WSGI_RESTART_FILE_REGEX"; value = ".*((\.py)|(\.config))$" }
# ----------------------------------
# Favicon
$RuleName = 'favicon'
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules" -Name "." -Value @{name = $RuleName; patternSyntax = 'ExactMatch'; stopProcessing = 'false' }
Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'match' -Value @{url = 'favicon.ico' }
Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'action' -Value @{type = 'Rewrite'; 'url' = '/static/favicon.ico' }
# ----------------------------------
# Http2Https
if ($Http2Https) {
    New-WebBinding -Name $SiteName -IPAddress * -Port 443 -Protocol https -HostHeader $SiteName -SslFlags 1

    $RuleName = 'Http2Https'
    Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules" -Name "." -Value @{name = $RuleName; stopProcessing = 'false' }
    Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'match' -Value @{url = '(.*)' }
    Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'conditions' -Value @{trackAllCaptures = 'False'; logicalGrouping = 'MatchAll' }
    Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']/conditions" -Name '.' -Value @{input = '{HTTPS}'; pattern = '^OFF$' }
    Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'action' -Value @{type = "Redirect"; url = "https://{HTTP_HOST}/{R:1}"; redirectType = "SeeOther" }
}
# ----------------------------------
# ----------------------------------
$rows = @(
    , 'from flask import Flask, request, jsonify'
    , 'app = Flask(__name__)'
    , ''
    , '@app.route("/")'
    , 'def flask_main():'
    , '    return "Hello!"'
    , ''
)

$rows | Out-File "$SitePath\main.py" -Encoding UTF8
# ----------------------------------
