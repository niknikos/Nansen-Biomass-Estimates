<#
.SYNOPSIS
    Removes the files created by New-Canaries.ps1.

.DESCRIPTION
    Deletes only what the manifest lists: each canary, if it still holds its token;
    any write-probe file (whose presence means a probe failed); the Phase B folder, if
    it holds nothing but the settings file the test created; and finally the manifest
    itself. It can be run again after a partial run. Anything that does not match is left in
    place and reported, so that nothing else in a protected folder can be deleted.

    Use -Preview to see what would be removed without removing it. (-Preview replaces
    the usual -WhatIf, which relies on a method call that Constrained Language Mode
    blocks; the script uses only cmdlets, hashtables and core types.)

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\docs\safeguard-test\Remove-Canaries.ps1 -Preview
#>
[CmdletBinding()]
param(
    [string]$NansenDataPath,
    # Show what would be removed, without removing anything.
    [switch]$Preview
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
        Remove-Item -LiteralPath $c.Path -WhatIf:$Preview
    } else {
        Write-Warning "Left in place, content has changed: $($c.Path)"
        $leftovers++
    }
}

foreach ($p in $manifest.WriteProbes) {
    if (Test-Path -LiteralPath $p) {
        Write-Warning "Write probe present (that probe FAILED): $p"
        Remove-Item -LiteralPath $p -WhatIf:$Preview
    }
}

$lab = $manifest.LabPath
if (Test-Path -LiteralPath $lab) {
    # Remove the folder only if it holds nothing but what the test created.
    $labClaude = Join-Path $lab '.claude'
    $labSettings = Join-Path $labClaude 'settings.json'
    $others = @(
        Get-ChildItem -LiteralPath $lab -Recurse -Force |
            Where-Object { $_.FullName -ne $labClaude -and $_.FullName -ne $labSettings }
    )
    $settingsOk = $true
    if (Test-Path -LiteralPath $labSettings) {
        $settingsOk = ((Get-Content -LiteralPath $labSettings -Raw).Trim() -eq $manifest.LabSettingsText)
    }
    if ($others.Count -gt 0 -or -not $settingsOk) {
        Write-Warning "Left in place, holds files the test did not create: $lab"
        $leftovers++
    } else {
        try {
            # -Force because .claude counts as hidden; the check above has confirmed
            # that the folder holds only what the test created.
            Remove-Item -LiteralPath $lab -Recurse -Force -WhatIf:$Preview
        } catch {
            Write-Warning ("Could not remove $lab ($($_.Exception.Message)). If it is still " +
                'open as the working folder of a Claude session, or in File Explorer, close ' +
                'or archive the session (or quit the desktop app), then run this script again.')
            $leftovers++
        }
    }
}

if ($leftovers -eq 0) {
    Remove-Item -LiteralPath $manifestPath -Force -WhatIf:$Preview
    if ($Preview) {
        Write-Host 'Preview only: nothing was removed.'
    } else {
        Write-Host 'Canary files removed.'
    }
} else {
    Write-Warning "Manifest kept ($manifestPath) because $leftovers item(s) need checking by hand."
}
