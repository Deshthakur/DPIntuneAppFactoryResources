<#
.SYNOPSIS
    Runs an existing Azure DevOps style script on a GitHub runner and translates
    ##vso logging commands into their GitHub Actions equivalents, so the
    original scripts do not need to be edited.

    ##vso[task.setvariable variable=X;isOutput=true]v  ->  GITHUB_OUTPUT (+ GITHUB_ENV)
    ##vso[task.setvariable variable=X]v                ->  GITHUB_ENV
    ##vso[task.logissue type=error|warning;]msg        ->  ::error:: / ::warning::
    ##vso[task.complete result=Failed;]                ->  step fails
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [hashtable]$Arguments = @{}
)

function ConvertFrom-VsoProps([string]$Raw) {
    $h = @{}
    foreach ($p in ($Raw -split ';')) {
        $kv = $p -split '=', 2
        if ($kv.Count -eq 2) { $h[$kv[0].Trim()] = $kv[1].Trim() }
    }
    return $h
}

$script:failed = $false

& $Path @Arguments *>&1 | ForEach-Object {
    $line = "$_"

    if ($line -match '^##vso\[task\.setvariable (?<props>[^\]]*)\](?<value>.*)$') {
        $props = ConvertFrom-VsoProps $Matches.props
        $name  = $props['variable']
        $value = $Matches.value
        if ($props['issecret'] -eq 'true') { Write-Host "::add-mask::$value" }
        "$name=$value" | Out-File -FilePath $env:GITHUB_ENV -Append -Encoding utf8
        if ($props['isOutput'] -eq 'true') {
            "$name=$value" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
        }
        if ($props['issecret'] -ne 'true') { Write-Host "[vso] set $name=$value" }
    }
    elseif ($line -match '^##vso\[task\.logissue (?<props>[^\]]*)\](?<msg>.*)$') {
        $props = ConvertFrom-VsoProps $Matches.props
        $type  = if ($props['type'] -eq 'error') { 'error' } else { 'warning' }
        Write-Host "::$type::$($Matches.msg)"
    }
    elseif ($line -match '^##vso\[task\.complete (?<props>[^\]]*)\]') {
        $props = ConvertFrom-VsoProps $Matches.props
        if ($props['result'] -eq 'Failed') { $script:failed = $true }
        Write-Host $line
    }
    else {
        Write-Host $line
    }
}

if ($script:failed) { exit 1 }
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
