<#
.SYNOPSIS
  Creates (or updates) your developer database in LocalDB, so F5 in Visual Studio works.
  Uses the same migrations as every deployed environment.
#>
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
sqllocaldb start MSSQLLocalDB | Out-Null
& (Join-Path $root 'scripts\deploy\Invoke-DbMigrations.ps1') `
    -Server '(localdb)\MSSQLLocalDB' -Database 'NotesApp' `
    -MigrationsPath (Join-Path $root 'database\migrations') -CreateDatabase
