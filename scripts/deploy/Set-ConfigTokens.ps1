<#
.SYNOPSIS
  Replaces every #{Name}# token in a config file, or fails without writing
  anything if any token has no value.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]    $Path,
    [Parameter(Mandatory)] [hashtable] $Values
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Path)) { throw "Config file not found: $Path" }

$text = [System.IO.File]::ReadAllText($Path)
$pattern = '#\{([A-Za-z0-9_.]+)\}#'
$names = @([regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

$missing = @($names | Where-Object { -not $Values.ContainsKey($_) -or [string]::IsNullOrEmpty([string]$Values[$_]) })
if ($missing.Count -gt 0) { throw "No value for token(s): $($missing -join ', '). $Path was not changed." }

# Values are XML-escaped so characters like & or < can't break the file.
$result = [regex]::Replace($text, $pattern, {
    param($m) [System.Security.SecurityElement]::Escape([string]$Values[$m.Groups[1].Value])
})

$check = New-Object System.Xml.XmlDocument
$check.LoadXml($result)   # refuse to write invalid XML
[System.IO.File]::WriteAllText($Path, $result, (New-Object System.Text.UTF8Encoding($false)))

foreach ($name in $names) {
    $shown = if ($name -match 'Password|Secret|Key|Token|Pwd') { '***' } else { $Values[$name] }
    Write-Host ("  {0,-16} = {1}" -f $name, $shown)
}
