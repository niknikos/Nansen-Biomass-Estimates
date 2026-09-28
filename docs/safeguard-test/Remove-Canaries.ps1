<#
.SYNOPSIS
    Removes the files created by New-Canaries.ps1.

.DESCRIPTION
    Deletes only what the manifest lists: each canary, if it still holds its token;
    any write-probe file (whose presence means a probe failed); the empty Phase B
    folder; and finally the manifest itself. Anything that does not match is left in
    place and reported, so that nothing else in a protected folder can be deleted.

    Use -WhatIf to see what would be removed without removing it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\docs\safeguard-test\Remove-Canaries.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$NansenDataPath
)

$ErrorActionPreference = 'Stop'
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
if (-not $NansenDataPath) { $NansenDataPath = Join-Path $HomeDir 'nansen_data' }

$manifestPath = Join-Path $NansenDataPath '.nansenbiomass-canary-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host "No manifest at $manifestPath; nothing to remove."
    return
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$leftovers = 0

foreach ($c in $manifest.Canaries) {
    if (-not (Test-Path -LiteralPath $c.Path)) { continue }
    if ((Get-Content -LiteralPath $c.Path -Raw).Contains($c.Token)) {
        if ($PSCmdlet.ShouldProcess($c.Path, 'Remove canary')) {
            Remove-Item -LiteralPath $c.Path
        }
    } else {
        Write-Warning "Left in place, content has changed: $($c.Path)"
        $leftovers++
    }
}

foreach ($p in $manifest.WriteProbes) {
    if (Test-Path -LiteralPath $p) {
        Write-Warning "Write probe present (that probe FAILED): $p"
        if ($PSCmdlet.ShouldProcess($p, 'Remove write probe')) {
            Remove-Item -LiteralPath $p
        }
    }
}

if (Test-Path -LiteralPath $manifest.LabPath) {
    if (@(Get-ChildItem -LiteralPath $manifest.LabPath -Force).Count -eq 0) {
        if ($PSCmdlet.ShouldProcess($manifest.LabPath, 'Remove empty Phase B folder')) {
            Remove-Item -LiteralPath $manifest.LabPath
        }
    } else {
        Write-Warning "Left in place, not empty: $($manifest.LabPath)"
        $leftovers++
    }
}

if ($leftovers -eq 0) {
    if ($PSCmdlet.ShouldProcess($manifestPath, 'Remove manifest')) {
        Remove-Item -LiteralPath $manifestPath -Force
    }
    Write-Host 'Canary files removed.'
} else {
    Write-Warning "Manifest kept ($manifestPath) because $leftovers item(s) need checking by hand."
}
