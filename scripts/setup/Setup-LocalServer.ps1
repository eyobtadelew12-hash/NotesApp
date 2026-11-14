<#
.SYNOPSIS
  ONE-TIME setup that turns this PC into the practice DEV, SIT, PAT and PROD servers.
  Run from an ELEVATED PowerShell (Run as administrator).

.DESCRIPTION
  Prerequisites (install yourself first):
    - IIS with ASP.NET 4.8. Turn on in "Windows Features", or run elevated:
        Enable-WindowsOptionalFeature -Online -All -FeatureName IIS-WebServerRole,IIS-WebServer,IIS-ASPNET45,IIS-NetFxExtensibility45,IIS-ISAPIExtensions,IIS-ISAPIFilter,IIS-ManagementConsole,IIS-ManagementScriptingTools
    - SQL Server Express (free), default instance name SQLEXPRESS, "Basic" install.

  Per environment this creates:
    - IIS app pool  NotesApp-<ENV>  (.NET 4, integrated pipeline, ApplicationPoolIdentity)
    - IIS site      NotesApp-<ENV>  on http://localhost:<port>  (DEV 8081, SIT 8082, PAT 8083, PROD 8084)
    - folder        C:\Sites\NotesApp\<ENV>\releases\0.0.0  (placeholder until the first deploy)
    - database      NotesApp_<ENV> on .\SQLEXPRESS
    - SQL login for IIS APPPOOL\NotesApp-<ENV>: read/write data only (Integrated Security, no password)
  It is safe to run again: existing items are kept.

  At the end it prints the GitHub variables to add to each environment.
#>
[CmdletBinding()]
param(
    [string[]] $Environments = @('DEV', 'SIT', 'PAT', 'PROD'),
    [int]      $FirstPort = 8081,
    [string]   $SqlServer = '.\SQLEXPRESS',
    [string]   $SitesRoot = 'C:\Sites\NotesApp',
    # The Windows account that will run the GitHub self-hosted runner.
    [string]   $RunnerAccount = "$env:USERDOMAIN\$env:USERNAME"
)

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run this script from an elevated PowerShell (Run as administrator).' }
if (-not (Get-Service W3SVC -ErrorAction SilentlyContinue)) { throw 'IIS is not installed. See the prerequisites at the top of this script.' }

function Invoke-Sql([string] $database, [string] $sql) {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source'] = $SqlServer; $b['Initial Catalog'] = $database; $b['Integrated Security'] = $true; $b['Connect Timeout'] = 15
    $c = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
    try { $c.Open(); $cmd = $c.CreateCommand(); $cmd.CommandText = $sql; [void]$cmd.ExecuteNonQuery() }
    finally { $c.Dispose() }
}

try { Invoke-Sql 'master' 'SELECT 1' }
catch { throw "Can't connect to SQL Server '$SqlServer' with your Windows account: $($_.Exception.Message). Is SQL Server Express installed and running?" }

Import-Module WebAdministration

New-Item -ItemType Directory -Force -Path $SitesRoot | Out-Null
# The runner account deploys the release folders; IIS app pools only need to read them.
icacls $SitesRoot /grant "${RunnerAccount}:(OI)(CI)M" /T /Q | Out-Null

$port = $FirstPort
$summary = @()
foreach ($envName in $Environments) {
    $name   = "NotesApp-$envName"
    $root   = Join-Path $SitesRoot $envName
    $initial = Join-Path $root 'releases\0.0.0'
    $db     = "NotesApp_$envName"

    Write-Host "==> $envName"
    if (-not (Test-Path $initial)) {
        New-Item -ItemType Directory -Force -Path $initial | Out-Null
        Set-Content (Join-Path $initial 'index.html') "<h1>NotesApp $envName</h1><p>Nothing deployed yet.</p>" -Encoding UTF8
    }

    if (-not (Test-Path "IIS:\AppPools\$name")) {
        New-WebAppPool -Name $name | Out-Null
        Set-ItemProperty "IIS:\AppPools\$name" -Name managedRuntimeVersion -Value 'v4.0'
        Set-ItemProperty "IIS:\AppPools\$name" -Name managedPipelineMode -Value 'Integrated'
        Write-Host "  app pool $name created"
    }
    if (-not (Test-Path "IIS:\Sites\$name")) {
        New-Website -Name $name -Port $port -PhysicalPath $initial -ApplicationPool $name | Out-Null
        Write-Host "  site $name created on http://localhost:$port"
    }
    icacls $root /grant "IIS APPPOOL\${name}:(OI)(CI)RX" /T /Q | Out-Null

    Invoke-Sql 'master' "IF DB_ID(N'$db') IS NULL CREATE DATABASE [$db];"
    Invoke-Sql 'master' "IF SUSER_ID(N'IIS APPPOOL\$name') IS NULL CREATE LOGIN [IIS APPPOOL\$name] FROM WINDOWS;"
    Invoke-Sql $db @"
IF USER_ID(N'IIS APPPOOL\$name') IS NULL CREATE USER [IIS APPPOOL\$name] FOR LOGIN [IIS APPPOOL\$name];
ALTER ROLE db_datareader ADD MEMBER [IIS APPPOOL\$name];
ALTER ROLE db_datawriter ADD MEMBER [IIS APPPOOL\$name];
"@
    Write-Host "  database $db ready; IIS APPPOOL\$name can read and write data"

    $summary += [pscustomobject]@{ Environment = $envName; SqlServer = $SqlServer; SqlDatabase = $db; IIS_SITE_NAME = $name; SITE_ROOT = $root; HEALTH_URL = "http://localhost:$port/health.ashx" }
    $port++
}

Write-Host ''
Write-Host 'Done. Add these variables to each GitHub environment (Settings > Environments > <ENV> > Variables),'
Write-Host 'or run the gh commands below from the repo folder:'
foreach ($s in $summary) {
    Write-Host ''
    Write-Host "# $($s.Environment)"
    foreach ($p in 'SqlServer', 'SqlDatabase', 'IIS_SITE_NAME', 'SITE_ROOT', 'HEALTH_URL') {
        Write-Host ("gh variable set {0} --env {1} --body `"{2}`"" -f $p, $s.Environment, $s.$p)
    }
}
Write-Host ''
Write-Host 'And once, for the repository:  gh variable set DEPLOY_RUNNER --body "self-hosted"'
