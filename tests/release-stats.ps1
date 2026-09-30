Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$leaf = 'wowvoice-stats-' + [guid]::NewGuid().ToString('N')
$fixture = Join-Path $parent $leaf
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/release-stats.ps1') -Destination (Join-Path $fixture 'tools/release-stats.ps1')
    function Invoke-RestMethod {
        param($Uri, $Headers, $TimeoutSec)
        if ($Uri -match '/releases\?') {
            return @([pscustomobject]@{ id=1; tag_name='v1'; draft=$false; published_at='2026-09-28T00:00:00Z' })
        }
        if ($Uri -match '/releases/1/assets\?') {
            return @(
                [pscustomobject]@{name='WowVoiceTalkingHead-1.zip'; state='uploaded'; download_count=10},
                [pscustomobject]@{name='WowVoiceTalkingHead-1-addon-only.zip'; state='uploaded'; download_count=20},
                [pscustomobject]@{name='WowVoiceTalkingHead-1-lite.zip'; state='uploaded'; download_count=30},
                [pscustomobject]@{name='sources.zip'; state='uploaded'; download_count=999}
            )
        }
        throw "Unexpected request: $Uri"
    }
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen
    $data = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $row = @($data.releases)[0]
    if ($row.Full -ne 10 -or $row.AddonOnly -ne 20 -or $row.Total -ne 30 -or @($data.assets).Count -ne 2 -or
        $row.PSObject.Properties.Name -contains 'Lite') {
        throw 'Release statistics must count only full and addon-only archives.'
    }
    $html = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/index.html') -Raw -Encoding UTF8
    $csv = @(Import-Csv -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.csv') -Encoding UTF8 -UseCulture)
    if ([regex]::Matches($html, '<div class="card">').Count -ne 3 -or
        [regex]::Matches($html, '<th[ >]').Count -ne 7 -or
        $csv[0].PSObject.Properties.Name -contains 'Lite') {
        throw 'HTML and CSV must not contain the Lite column or card.'
    }
    Write-Host 'PASS: full/addon statistics remain separate; lite and unrelated archives excluded; HTML/CSV have no Lite column; no network calls.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -ne $leaf) { throw 'Unsafe stats test path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
