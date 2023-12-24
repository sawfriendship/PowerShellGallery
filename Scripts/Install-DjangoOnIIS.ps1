
<#PSScriptInfo
.VERSION 1.1.0
.GUID c0cde633-3d10-43dc-81b3-3cd6faf5dc80
.AUTHOR saw-friendship
.COMPANYNAME
.COPYRIGHT
.TAGS Install Django web-framework on IIS web-server 
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
Install Django web-framework on IIS web-server 
#> 

#Requires -RunAsAdministrator

param (
	[Parameter(Mandatory)][string]$SiteName,
	[string]$PythonEXE = 'python',
	[string]$Requirements = '',
	[switch]$AddToHostsFile,
	[switch]$Http2Https
)

$SiteName = $SiteName -replace '\s*'

$v = py -V
Write-Host $v -ForegroundColor Green

if ($Add2Hosts) {
	Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "127.0.0.1 `t $SiteName"
}

$AllFeatures = (Dism.exe /Online /English /Get-Features /Format:Table) -like '*[a-z]*|*[a-z]*' -replace '\s' | ConvertFrom-Csv -Delimiter '|' -Header Name,State | Select-Object -Skip 1 | Sort-Object -Property Name

$InstalledFeatures = $AllFeatures | ? {$_.State -eq 'Enabled'}

$Features = @(
	,'IIS-WebServerRole'
	,'IIS-WebServer'
	,'IIS-WebServerManagementTools'
	,'IIS-CGI'
	,'IIS-DefaultDocument'
	,'IIS-HttpErrors'
	,'IIS-HttpRedirect'
	,'IIS-HttpLogging'
	,'IIS-BasicAuthentication'
)

$Features | ? {$_ -notin $InstalledFeatures.Name} | % {
	Write-Host "Install Feature '$_'" -ForegroundColor Yellow
	Dism.exe /Online /English /Enable-Feature:$_
}

# ----------------------------------

mkdir "C:\inetpub\$SiteName\static" -Force

$vEnvName = 'venv'
$SitePath = "C:\inetpub\$SiteName\"
$PythonPath = "C:\inetpub\$SiteName\$vEnvName"

cd $SitePath

Set-Alias -Name 'pyexe' -Value $PythonEXE

pyexe -m venv $vEnvName

# ----------------------------------
.\venv\Scripts\Activate.ps1
# ----------------------------------
python -m pip install --upgrade pip wheel
if ($Requirements) {
	python -m pip install -r $Requirements
} else {
	python -m pip install wfastcgi django djangorestframework django-filter django-guardian django-debug-toolbar
}
# ---------------------------------------
.\venv\Scripts\wfastcgi-enable.exe
# ----------------------------------
# IIS Config
Import-Module WebAdministration
New-Website -Name $SiteName -IPAddress * -Port 80 -HostHeader $SiteName -PhysicalPath $SitePath
#
C:\Windows\System32\inetsrv\appcmd.exe unlock config -section:system.webServer/handlers
New-WebHandler -PSPath "IIS:\Sites\$SiteName" -Name PythonHandler -Path * -Verb * -Modules FastCgiModule -ScriptProcessor "$PythonPath\Scripts\python.exe|$PythonPath\lib\site-packages\wfastcgi.py" -ResourceType Unspecified -RequiredAccess Script
Remove-WebHandler -PSPath "IIS:\Sites\$SiteName\static" -Name PythonHandler
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "PYTHONPATH"; value = $SitePath}
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "DJANGO_SETTINGS_MODULE"; value = "app.settings"}
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "WSGI_HANDLER"; value = "django.core.wsgi.get_wsgi_application()"}
# ----------------------------------
# Favicon
$RuleName = 'favicon'
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules" -Name "." -Value @{name = $RuleName; patternSyntax = 'ExactMatch'; stopProcessing = 'false'}
Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'match' -Value @{url = 'favicon.ico'}
Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'action' -Value @{type = 'Rewrite'; 'url' = '/static/favicon.ico'}
# ----------------------------------
# IIS_IUSRS must have rights to the directory
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "WSGI_LOG"; value = "$SitePath\wfastcgi.log"}
Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/appSettings" -Name "." -Value @{key = "WSGI_RESTART_FILE_REGEX"; value = ".*((\.py)|(\.config))$"}
# ----------------------------------
if ($Http2Https) {
	New-WebBinding -Name $SiteName -IPAddress * -Port 443 -Protocol https -HostHeader $SiteName -SslFlags 1

	$RuleName = 'Http2Https'
	Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules" -Name "." -Value @{name = $RuleName; stopProcessing = 'false'}
	Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'match' -Value @{url = '(.*)'}
	Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'conditions' -Value @{trackAllCaptures = 'False'; logicalGrouping = 'MatchAll'}
	Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']/conditions" -Name '.' -Value @{input = '{HTTPS}'; pattern = '^OFF$'}
	Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" -Filter "/system.webServer/rewrite/rules/rule[@name='$RuleName']" -Name 'action' -Value @{type="Redirect"; url="https://{HTTP_HOST}/{R:1}"; redirectType="SeeOther"}
}
###########################################################################################################

# ---------------------------------------
django-admin startproject app .

$Settings = Get-Content -Path ".\app\settings.py" -Encoding UTF8 | Select-String -NotMatch -Pattern '^STATIC_URL = |^ALLOWED_HOSTS = '
$Settings += ''
$Settings += "ALLOWED_HOSTS = ['*']"
$Settings += ''
$Settings += 'STATIC_URL = "/static/"'
$Settings += 'import os'
$Settings += 'STATIC_ROOT = os.path.join(BASE_DIR, "static")'
$Settings += ''
Set-Content -Path ".\app\settings.py" -Encoding UTF8 -Value $Settings

python manage.py startapp main
python manage.py collectstatic
python manage.py migrate
python manage.py createsuperuser

# ----------------------------------

