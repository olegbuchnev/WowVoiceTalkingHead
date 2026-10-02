[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $repo 'dev\catquest-update-lab'
$destination = Join-Path $repo 'artifacts\catquest-update-test\WowVoiceCatQuestUpdateLab'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($name in @('WowVoiceCatQuestUpdateLab.toc', 'Lab.lua', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $destination $name) -Force
}
Write-Host "Test addon prepared: $destination"
Write-Host 'Installation and scenarios: dev/catquest-update-lab/README.md'
Write-Host 'Installed addons and third-party packs have not been modified.'
