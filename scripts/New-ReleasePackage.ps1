<#
.SYNOPSIS
  Builds the NotesApp.Web package: one zip, built ONCE, deployed unchanged to
  DEV, SIT, and (after Release) PAT and PROD.

.DESCRIPTION
  Package layout (NotesApp.Web.<Version>.zip):
    site/                 published site; Web.config = tokenized template
    database/migrations/  versioned SQL scripts, applied by the deploy
    deploy/               Install-Release.ps1, Set-ConfigTokens.ps1, Invoke-DbMigrations.ps1
    manifest.json         version, commit, branch, tokens the deploy must supply
  A .sha256 file is written next to the zip.

.EXAMPLE
  .\scripts\New-ReleasePackage.ps1 -Version 1.0.0-local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $OutputDir = (Join-Path $PSScriptRoot '..\out'),
    [string] $Commit = $env:GITHUB_SHA,
    [string] $Branch = $env:GITHUB_REF_NAME
)

$ErrorActionPreference = 'Stop'
if (-not $Commit) { $Commit = try { git rev-parse HEAD 2>$null } catch { $null } }
if ($Commit -notmatch '^[0-9a-f]{40}$') { $Commit = 'unknown' }
if (-not $Branch) { $Branch = try { git rev-parse --abbrev-ref HEAD 2>$null } catch { $null } }
if (-not $Branch) { $Branch = 'local' }

$root    = Resolve-Path (Join-Path $PSScriptRoot '..')
$project = Join-Path $root 'src\NotesApp.Web\NotesApp.Web.csproj'
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = Resolve-Path $OutputDir
$staging = Join-Path $OutputDir 'package'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }

# MSBuild from Visual Studio (dotnet build can't build Web Forms projects).
$msbuild = Get-Command msbuild -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $msbuild) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
}
if (-not $msbuild) { throw 'MSBuild not found. Install Visual Studio or Build Tools.' }

# 1. Publish with Web.Release.config applied (-> tokenized Web.config).
& $msbuild $project /restore /p:Configuration=Release /p:DeployOnBuild=true `
    /p:DeployDefaultTarget=WebPublish /p:WebPublishMethod=FileSystem `
    "/p:PublishUrl=$staging\site" /p:DeleteExistingFiles=true /m /v:minimal /nologo
if ($LASTEXITCODE -ne 0) { throw "MSBuild publish failed ($LASTEXITCODE)." }

# 2. Clean and check the template: no transform files, no developer comments
#    (a comment could even look like a token), no real server names left.
$site = Join-Path $staging 'site'
Get-ChildItem $site -Recurse -File -Filter 'Web.*.config' | Remove-Item
$template = Join-Path $site 'Web.config'
$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.Load($template)
@($xml.SelectNodes('//comment()')) | ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
$xml.Save($template)
foreach ($cs in $xml.configuration.connectionStrings.add) {
    if ($cs.connectionString -notmatch '#\{') {
        throw "Connection string '$($cs.name)' has no tokens: real server names would ship in the package. Tokenize it in Web.Release.config."
    }
}
$tokens = @([regex]::Matches((Get-Content $template -Raw), '#\{([A-Za-z0-9_.]+)\}#') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

# 3. Database migrations and deploy scripts travel with the package.
$migrations = Join-Path $staging 'database\migrations'
New-Item -ItemType Directory -Force -Path $migrations | Out-Null
Copy-Item (Join-Path $root 'database\migrations\*.sql') $migrations
Copy-Item (Join-Path $PSScriptRoot 'deploy') -Destination (Join-Path $staging 'deploy') -Recurse

# 4. Manifest.
[ordered]@{
    name       = 'NotesApp.Web'
    version    = $Version
    commit     = $Commit
    branch     = $Branch
    builtAt    = (Get-Date).ToUniversalTime().ToString('o')
    tokens     = $tokens
    migrations = @(Get-ChildItem $migrations -Filter *.sql | Sort-Object Name | ForEach-Object Name)
} | ConvertTo-Json | Set-Content (Join-Path $staging 'manifest.json') -Encoding UTF8

# 5. Zip and checksum.
$zip = Join-Path $OutputDir "NotesApp.Web.$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content "$zip.sha256" "$hash  $(Split-Path $zip -Leaf)" -Encoding ASCII

Write-Host "Package: $zip"
Write-Host "Tokens:  $($tokens -join ', ')"
Write-Host "SHA256:  $hash"
if ($env:GITHUB_OUTPUT) {
    "zip=$zip"   >> $env:GITHUB_OUTPUT
    "name=$(Split-Path $zip -Leaf)" >> $env:GITHUB_OUTPUT
}
