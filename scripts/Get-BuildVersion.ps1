<#
.SYNOPSIS
  Works out the version of a TEST build from git tags and the branch name.

    main            -> next MINOR after the last release tag  (v1.2.0 -> 1.3.0-ci.<run>)
    hotfix/1.2.1    -> the version in the branch name          (1.2.1-ci.<run>)
    no tag yet      -> 1.0.0-ci.<run>

  Releases drop the "-ci.<run>" label (see release.yml).
  Needs the full git history and tags (actions/checkout with fetch-depth: 0).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RunNumber,
    [string] $Branch = $env:GITHUB_REF_NAME
)

$ErrorActionPreference = 'Stop'

$released = @(git tag --list 'v*' --merged HEAD) |
    Where-Object { $_ -match '^v(\d+)\.(\d+)\.(\d+)$' } |
    ForEach-Object { [version]($_.Substring(1)) } |
    Sort-Object -Descending

if ($Branch -match '^hotfix/(\d+\.\d+\.\d+)$') {
    $base = $Matches[1]
}
elseif (-not $released) {
    $base = '1.0.0'
}
else {
    $last = $released[0]
    $base = '{0}.{1}.0' -f $last.Major, ($last.Minor + 1)
}

$version = "$base-ci.$RunNumber"
Write-Host "Branch: $Branch  Last release: $(if ($released) { "v$($released[0])" } else { 'none' })  Build version: $version"
if ($env:GITHUB_OUTPUT) {
    "version=$version" >> $env:GITHUB_OUTPUT
    "base=$base"       >> $env:GITHUB_OUTPUT
}
$version
