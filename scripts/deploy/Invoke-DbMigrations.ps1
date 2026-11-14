<#
.SYNOPSIS
  Applies database/migrations/*.sql in name order, each exactly once per database.

.DESCRIPTION
  Applied scripts are recorded in dbo.SchemaVersions. Each script runs in its own
  transaction (split on lines that contain only GO); a failure rolls that script back
  and stops. Signs in with Integrated Security, as the account running the deploy.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [Parameter(Mandatory)] [string] $MigrationsPath,
    # Create the database if it does not exist (local developer databases).
    [switch] $CreateDatabase
)

$ErrorActionPreference = 'Stop'

function Get-Connection([string] $db) {
    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $b['Data Source'] = $Server
    $b['Initial Catalog'] = $db
    $b['Integrated Security'] = $true
    $b['Connect Timeout'] = 15
    $c = New-Object System.Data.SqlClient.SqlConnection $b.ConnectionString
    $c.Open()
    $c
}

function Invoke-NonQuery($conn, [string] $sql, $tx = $null) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 120
    if ($tx) { $cmd.Transaction = $tx }
    [void]$cmd.ExecuteNonQuery()
}

if ($CreateDatabase) {
    $master = Get-Connection 'master'
    try {
        $cmd = $master.CreateCommand()
        $cmd.CommandText = "IF DB_ID(@db) IS NULL BEGIN DECLARE @s nvarchar(400) = N'CREATE DATABASE ' + QUOTENAME(@db); EXEC (@s) END"
        [void]$cmd.Parameters.AddWithValue('@db', $Database)
        [void]$cmd.ExecuteNonQuery()
    }
    finally { $master.Dispose() }
}

$conn = Get-Connection $Database
try {
    Invoke-NonQuery $conn @"
IF OBJECT_ID(N'dbo.SchemaVersions', N'U') IS NULL
    CREATE TABLE dbo.SchemaVersions (
        ScriptName NVARCHAR(255) NOT NULL CONSTRAINT PK_SchemaVersions PRIMARY KEY,
        AppliedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_SchemaVersions_AppliedAt DEFAULT SYSUTCDATETIME()
    );
"@

    $applied = New-Object System.Collections.Generic.HashSet[string]
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 'SELECT ScriptName FROM dbo.SchemaVersions'
    $reader = $cmd.ExecuteReader()
    while ($reader.Read()) { [void]$applied.Add($reader.GetString(0)) }
    $reader.Close()

    $scripts = Get-ChildItem $MigrationsPath -Filter *.sql | Sort-Object Name
    foreach ($script in $scripts) {
        if ($applied.Contains($script.Name)) { Write-Host "  = $($script.Name) (already applied)"; continue }

        $batches = [regex]::Split((Get-Content $script.FullName -Raw), '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() }
        $tx = $conn.BeginTransaction()
        try {
            foreach ($batch in $batches) { Invoke-NonQuery $conn $batch $tx }
            $rec = $conn.CreateCommand()
            $rec.Transaction = $tx
            $rec.CommandText = 'INSERT INTO dbo.SchemaVersions (ScriptName) VALUES (@n)'
            [void]$rec.Parameters.AddWithValue('@n', $script.Name)
            [void]$rec.ExecuteNonQuery()
            $tx.Commit()
            Write-Host "  + $($script.Name) applied"
        }
        catch {
            $tx.Rollback()
            throw "Migration $($script.Name) failed and was rolled back: $($_.Exception.Message)"
        }
    }
    Write-Host "Database $Database on $Server is up to date ($($scripts.Count) migration(s) known)."
}
finally { $conn.Dispose() }
