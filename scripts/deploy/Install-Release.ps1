<#
.SYNOPSIS
  Installs one NotesApp package on an IIS server:
  check values -> migrate database -> versioned release folder -> generate Web.config
  -> switch IIS -> health check -> roll back on failure -> clean up old releases.

.DESCRIPTION
  Folder layout on the server (SiteRoot):

    C:\Sites\NotesApp\SIT\
      releases\1.1.0-ci.12\   previous release (kept for rollback)
      releases\1.2.0\         this release, with its own generated Web.config
      current.txt             version that is live

  The live site is never edited in place. Rollback = point IIS back to the previous folder.

  Token values (#{SqlServer}#, #{SqlDatabase}#, ...) are looked up in this order:
    1. -ValuesJson key "<Name>"               (GitHub environment variables, as JSON)
    2. -ValuesJson key "<Name>_<Environment>" (repository variables, e.g. SqlServer_SIT)
    3. environment variable "<Name>"
  Built in: EnvironmentName = -Environment, ReleaseVersion = -ReleaseVersion.

  Needs: IIS + WebAdministration (unless -DryRun), and an account that may change the
  IIS site and run the migrations (the self-hosted runner, started elevated).

.EXAMPLE
  .\deploy\Install-Release.ps1 -Environment DEV -SiteRoot C:\Sites\NotesApp\DEV `
      -IisSiteName NotesApp-DEV -HealthUrl http://localhost:8081/health.ashx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Environment,
    [Parameter(Mandatory)] [string] $SiteRoot,
    [string] $IisSiteName,
    [string] $HealthUrl,
    # Version shown by the app and used as the release folder name. Defaults to the package's
    # build version; a release (e.g. 1.2.0) deploys the same files under its release number.
    [string] $ReleaseVersion,
    [int]    $KeepReleases = 5,
    [int]    $HealthTimeoutSeconds = 90,
    [string] $ValuesJson = $env:CONFIG_VALUES,
    [string] $PackageRoot = (Split-Path -Parent $PSScriptRoot),
    # Fill tokens and build the release folder, but don't touch the database or IIS.
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
function Write-Step($text) { Write-Host "==> $text" }

# --- 1. Read the package ---------------------------------------------------------------
$manifest = Get-Content (Join-Path $PackageRoot 'manifest.json') -Raw | ConvertFrom-Json
if (-not $ReleaseVersion) { $ReleaseVersion = $manifest.version }
$source = Join-Path $PackageRoot 'site'
Write-Step "Installing $($manifest.name) $ReleaseVersion (build $($manifest.version), commit $($manifest.commit)) to $Environment"

# --- 2. Collect token values and check them BEFORE touching anything --------------------
$json = @{}
if ($ValuesJson) {
    ($ValuesJson | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $json[$_.Name] = [string]$_.Value }
}
$values = @{ EnvironmentName = $Environment; ReleaseVersion = $ReleaseVersion }
foreach ($token in @($manifest.tokens)) {
    if ($values.ContainsKey($token)) { continue }
    $value = $json[$token]
    if (-not $value) { $value = $json["${token}_$Environment"] }
    if (-not $value) { $value = [Environment]::GetEnvironmentVariable($token) }
    if ($value) { $values[$token] = $value }
}
$missing = @($manifest.tokens | Where-Object { -not $values.ContainsKey($_) })
if ($missing.Count -gt 0) {
    throw "Missing values for $Environment : $($missing -join ', '). Add them as variables on the '$Environment' environment. Nothing was changed."
}
if (-not $DryRun -and (-not $IisSiteName -or -not $HealthUrl)) {
    throw '-IisSiteName and -HealthUrl are required (or use -DryRun).'
}

# --- 3. Database migrations (before the new code goes live) -----------------------------
$migrations = Join-Path $PackageRoot 'database\migrations'
if ($DryRun) {
    Write-Step "Dry run: would apply migrations to $($values.SqlDatabase) on $($values.SqlServer): $(@($manifest.migrations) -join ', ')"
}
else {
    Write-Step "Migrating database $($values.SqlDatabase) on $($values.SqlServer)"
    & (Join-Path $PSScriptRoot 'Invoke-DbMigrations.ps1') -Server $values.SqlServer -Database $values.SqlDatabase -MigrationsPath $migrations
}

# --- 4. Build the release folder next to the live one -----------------------------------
$releases   = Join-Path $SiteRoot 'releases'
$releaseDir = Join-Path $releases $ReleaseVersion
$liveDir    = $null
if (-not $DryRun) {
    Import-Module WebAdministration
    $liveDir = (Get-Item "IIS:\Sites\$IisSiteName").physicalPath
    if ($liveDir -and ([IO.Path]::GetFullPath($liveDir).TrimEnd('\') -eq [IO.Path]::GetFullPath($releaseDir).TrimEnd('\'))) {
        throw "$ReleaseVersion is already live on $IisSiteName."
    }
}
if (Test-Path $releaseDir) { Remove-Item $releaseDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

Write-Step "Copying site to $releaseDir"
robocopy $source $releaseDir /E /R:2 /W:2 /NP /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)." }
$global:LASTEXITCODE = 0

Write-Step 'Generating Web.config'
& (Join-Path $PSScriptRoot 'Set-ConfigTokens.ps1') -Path (Join-Path $releaseDir 'Web.config') -Values $values

if ($DryRun) {
    Write-Step "Dry run: release folder ready at $releaseDir. Database and IIS not changed."
    return
}

# --- 5. Switch IIS, health-check, roll back on failure ----------------------------------
Write-Step "Switching IIS site '$IisSiteName': $liveDir -> $releaseDir"
Set-ItemProperty "IIS:\Sites\$IisSiteName" -Name physicalPath -Value $releaseDir

Write-Step "Health check $HealthUrl (expecting 200 and version $ReleaseVersion)"
$healthy  = $false
$lastSeen = ''
$deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
while (-not $healthy -and (Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest $HealthUrl -UseBasicParsing -TimeoutSec 15
        $lastSeen = "$($r.StatusCode) $($r.Content)"
        $healthy = ($r.StatusCode -eq 200 -and $r.Headers['X-Release-Version'] -eq $ReleaseVersion)
    }
    catch { $lastSeen = $_.Exception.Message }
    if (-not $healthy) { Start-Sleep -Seconds 5 }
}

if (-not $healthy) {
    if ($liveDir) {
        Write-Step "Health check failed ($lastSeen). Rolling back to $liveDir"
        Set-ItemProperty "IIS:\Sites\$IisSiteName" -Name physicalPath -Value $liveDir
    }
    throw "Release $ReleaseVersion failed its health check on $Environment ($lastSeen). " +
          $(if ($liveDir) { "IIS was switched back to $liveDir." } else { 'There was no previous release to roll back to.' })
}

Set-Content (Join-Path $SiteRoot 'current.txt') $ReleaseVersion -Encoding ASCII
Write-Step "$ReleaseVersion is live on $Environment"

# --- 6. Keep the last N releases (never the live one or the one before it) --------------
$keep = @($releaseDir, $liveDir) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
Get-ChildItem $releases -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $KeepReleases |
    Where-Object { $keep -notcontains $_.FullName.TrimEnd('\') } |
    ForEach-Object { Write-Step "Removing old release $($_.Name)"; Remove-Item $_.FullName -Recurse -Force }
