Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$leaf = 'wowvoice-stats-' + [guid]::NewGuid().ToString('N')
$fixture = Join-Path $parent $leaf
New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') -Force | Out-Null
$savedGitHubToken = $env:GITHUB_TOKEN
$savedGhToken = $env:GH_TOKEN
try {
    # No real credential helper, authentication or network is used by fixtures.
    $env:GITHUB_TOKEN = 'stats-fixture-token'
    $env:GH_TOKEN = $null
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/release-stats.ps1') -Destination (Join-Path $fixture 'tools/release-stats.ps1')
    New-Item -ItemType Directory -Path (Join-Path $fixture 'config') -Force | Out-Null
    $ledgerPath = Join-Path $fixture 'config/release-download-checks.json'
    [IO.File]::WriteAllText($ledgerPath, @'
{"schemaVersion":1,"checks":[
  {"assetId":11,"release":"v1","asset":"WowVoiceTalkingHead-1.zip","count":1},
  {"assetId":12,"release":"v1","asset":"WowVoiceTalkingHead-1-addon-only.zip","count":21},
  {"assetId":19,"release":"v2","asset":"WowVoiceTalkingHead-1.zip","count":3},
  {"assetId":31,"release":"v1.2.5-forever","asset":"WowVoiceTalkingHead-1.2.5-forever-addon-only.zip","count":2}
]}
'@)
    function Get-TestAssets($Id) {
        if ($Id -eq 1) {
            return @(
                [pscustomobject]@{id=11; name='WowVoiceTalkingHead-1.zip'; state='uploaded'; download_count=10},
                [pscustomobject]@{id=12; name='WowVoiceTalkingHead-1-addon-only.zip'; state='uploaded'; download_count=20},
                [pscustomobject]@{id=13; name='WowVoiceTalkingHead-1-lite.zip'; state='uploaded'; download_count=30},
                [pscustomobject]@{id=14; name='sources.zip'; state='uploaded'; download_count=999}
            )
        }
        if ($Id -eq 2) {
            # Same name as the removed asset 19, but this upload has its own counter.
            return @([pscustomobject]@{id=21; name='WowVoiceTalkingHead-1.zip'; state='uploaded'; download_count=5})
        }
        if ($Id -eq 3) {
            return @([pscustomobject]@{id=31; name='TalkingHeadRu-1.2.5-forever.zip'; state='uploaded'; download_count=7})
        }
    }
    $statsFixture = @{ Mode = 'embedded'; Requests = 0 }
    function Invoke-RestMethod {
        param($Uri, $Headers, $TimeoutSec)
        $statsFixture.Requests++
        if ($Headers.ContainsKey('Authorization') -and $Headers.Authorization -ne 'Bearer stats-fixture-token') {
            throw 'Unexpected authentication header.'
        }
        if ($statsFixture.Mode -eq 'stale-login' -and $Headers.ContainsKey('Authorization')) {
            $exception = [Exception]::new('Unauthorized')
            $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{
                StatusCode=401; Headers=@{}
            })
            throw $exception
        }
        if ($statsFixture.Mode -eq 'release-pages') {
            if ($Uri -notmatch '/releases\?') { throw "Unexpected request: $Uri" }
            $pageSize = if ($Uri -match 'page=1$') { 100 } else { 1 }
            return @(1..$pageSize | ForEach-Object {
                [pscustomobject]@{id=$_; tag_name="v$_"; draft=$false; published_at='2026-09-28T00:00:00Z'; assets=@()}
            })
        }
        if ($statsFixture.Mode -eq 'asset-pages') {
            $items = @(1..100 | ForEach-Object {
                [pscustomobject]@{id=$_; name="WowVoiceTalkingHead-$_.zip"; state='uploaded'; download_count=1}
            })
            if ($Uri -match '/releases\?') {
                return @([pscustomobject]@{id=3; tag_name='v3'; draft=$false; published_at='2026-09-28T00:00:00Z'; assets=$items})
            }
            if ($Uri -match '/releases/3/assets\?.*page=1$') { return $items }
            if ($Uri -match '/releases/3/assets\?.*page=2$') {
                return @([pscustomobject]@{id=101; name='WowVoiceTalkingHead-101.zip'; state='uploaded'; download_count=1})
            }
            throw "Unexpected request: $Uri"
        }
        if ($Uri -match '/releases\?') {
            $testReleases = @(
                [pscustomobject]@{ id=1; tag_name='v1'; draft=$false; published_at='2026-09-28T00:00:00Z'; assets=@(Get-TestAssets 1) },
                [pscustomobject]@{ id=2; tag_name='v2'; draft=$false; published_at='2026-09-29T00:00:00Z'; assets=@(Get-TestAssets 2) },
                [pscustomobject]@{ id=3; tag_name='v1.2.5-forever'; draft=$false; published_at='2026-10-04T00:00:00Z'; assets=@(Get-TestAssets 3) }
            )
            if ($statsFixture.Mode -eq 'addon-only') { return @($testReleases | Where-Object id -eq 3) }
            if ($statsFixture.Mode -eq 'missing-assets') {
                foreach ($release in $testReleases) { $release.PSObject.Properties.Remove('assets') }
            }
            return $testReleases
        }
        if ($statsFixture.Mode -eq 'missing-assets' -and $Uri -match '/releases/([123])/assets\?') {
            return @(Get-TestAssets ([int]$Matches[1]))
        }
        throw "Unexpected request: $Uri"
    }
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen
    if ($statsFixture.Requests -ne 1) { throw 'Embedded release assets must require only one request.' }
    $data = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $row = $data.releases | Where-Object Release -eq 'v1'
    if ($row.Full -ne 9 -or $row.AddonOnly -ne 0 -or $row.Total -ne 9 -or @($data.assets).Count -ne 4 -or
        $row.PSObject.Properties.Name -contains 'Lite') {
        throw 'Statistics must deduct known checks without becoming negative.'
    }
    $replacement = $data.releases | Where-Object Release -eq 'v2'
    if ($replacement.Full -ne 5 -or $null -ne $replacement.AddonOnly) {
        throw 'Replacing an asset must not inherit checks; an absent archive stays absent.'
    }
    $current = $data.releases | Where-Object Release -eq 'v1.2.5-forever'
    if ($null -ne $current.Full -or $current.AddonOnly -ne 5 -or $current.Total -ne 5 -or
        ($data.releases | Measure-Object Total -Sum).Sum -ne 19) {
        throw 'A new addon-only release must count alongside historical full archives, including check deductions.'
    }
    $addonDetail = $data.assets | Where-Object asset -eq 'WowVoiceTalkingHead-1-addon-only.zip'
    if ($addonDetail.downloads -ne 0) { throw 'Per-asset JSON must use the adjusted counter.' }
    $html = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/index.html') -Raw -Encoding UTF8
    $csv = @(Import-Csv -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.csv') -Encoding UTF8 -UseCulture)
    if ([regex]::Matches($html, '<div class="card">').Count -ne 3 -or
        [regex]::Matches($html, '<th[ >]').Count -ne 9 -or
        $csv[0].PSObject.Properties.Name -contains 'Lite') {
        throw 'HTML and CSV must not contain the Lite column or card.'
    }
    $currentCsv = $csv | Where-Object Release -eq 'v1.2.5-forever'
    if ($currentCsv.Full -ne '' -or $currentCsv.AddonOnly -ne 5 -or $currentCsv.Total -ne 5 -or
        $html -notmatch '<th scope="row">v1.2.5-forever</th><td>[^<]+</td><td>—</td><td>5</td><td>5</td>' -or
        $html -notmatch 'Старые полные архивы<strong>14</strong>' -or
        $html -notmatch 'Аддон<strong>5</strong>' -or $html -notmatch 'Всего ZIP<strong>19</strong>' -or
        $html -notmatch 'CurseForge') {
        throw 'Report must distinguish an absent full archive from zero downloads and explain historical counts.'
    }
    $csvRow = $csv | Where-Object Release -eq 'v1'
    if ($csvRow.Total -ne 9 -or ($csvRow.PSObject.Properties.Name -join ',') -ne 'Release,Published,Full,AddonOnly,Total' -or
        ($row.PSObject.Properties.Name -join ',') -ne 'Release,PublishedUTC,Full,AddonOnly,Total' -or
        $html -match '<th>GitHub</th>|<th>Проверки</th>') { throw 'Reports must retain the original columns without technical counters.' }
    $statsFixture.Mode = 'addon-only'; $statsFixture.Requests = 0
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen | Out-Null
    $onlyAddon = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($statsFixture.Requests -ne 1 -or @($onlyAddon.releases).Count -ne 1 -or
        $null -ne $onlyAddon.releases[0].Full -or $onlyAddon.releases[0].Total -ne 5) {
        throw 'Statistics must also work when there are no full archives in any release.'
    }
    $statsFixture.Mode = 'embedded'
    Remove-Item -LiteralPath $ledgerPath
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen
    $unadjusted = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $row = $unadjusted.releases | Where-Object Release -eq 'v1'
    if ($row.Full -ne 10 -or $row.AddonOnly -ne 20 -or $row.Total -ne 30) {
        throw 'Without known checks the original counters must be preserved.'
    }
    $statsFixture.Mode = 'stale-login'; $statsFixture.Requests = 0
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen
    if ($statsFixture.Requests -ne 2) { throw 'A stale login must retry the public API exactly once.' }
    $statsFixture.Mode = 'missing-assets'; $statsFixture.Requests = 0
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen | Out-Null
    if ($statsFixture.Requests -ne 4) { throw 'Missing embedded assets must fetch each release separately.' }
    $statsFixture.Mode = 'asset-pages'; $statsFixture.Requests = 0
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen
    $large = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($statsFixture.Requests -ne 3 -or $large.releases[0].Full -ne 101 -or @($large.assets).Count -ne 101) {
        throw 'Large releases must paginate assets completely.'
    }
    $statsFixture.Mode = 'release-pages'; $statsFixture.Requests = 0
    & (Join-Path $fixture 'tools/release-stats.ps1') -NoOpen | Out-Null
    $large = Get-Content -LiteralPath (Join-Path $fixture 'artifacts/stats/downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($statsFixture.Requests -ne 2 -or @($large.releases).Count -ne 101) { throw 'Releases must paginate completely.' }
    foreach ($name in @('index.html','downloads.csv','downloads.json')) {
        if ((Get-Content -LiteralPath (Join-Path $fixture "artifacts/stats/$name") -Raw -Encoding UTF8) -match 'stats-fixture-token') {
            throw 'Credentials must never be written to reports.'
        }
    }
    # Run failure in a child process because the command correctly exits with 1.
    $reportBefore = @{}
    foreach ($name in @('index.html','downloads.csv','downloads.json')) {
        $reportBefore[$name] = (Get-FileHash -LiteralPath (Join-Path $fixture "artifacts/stats/$name")).Hash
    }
    $runner = Join-Path $fixture 'rate-limit.ps1'
    [IO.File]::WriteAllText($runner, @'
param([string]$StatsScript)
function Invoke-RestMethod {
    param($Uri,$Headers,$TimeoutSec)
    $exception = [Exception]::new('Forbidden')
    $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{
        StatusCode=403; Headers=@{'X-RateLimit-Remaining'='0'; 'X-RateLimit-Reset'='1790815296'}
    })
    throw $exception
}
& $StatsScript -NoOpen
exit $LASTEXITCODE
'@)
    $failureLog = Join-Path $fixture 'failure.log'
    $failureError = Join-Path $fixture 'failure-error.log'
    $child = Start-Process powershell.exe -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $runner + '"'),
        ('"' + (Join-Path $fixture 'tools/release-stats.ps1') + '"')
    ) -RedirectStandardOutput $failureLog -RedirectStandardError $failureError
    $failureText = Get-Content -LiteralPath $failureError -Raw
    if ($child.ExitCode -ne 1 -or $failureText -notmatch 'GitHub API request limit reached' -or
        $failureText -notmatch 'Retry after' -or $failureText -match 'stats-fixture-token') {
        throw ('Rate limits must explain retry time, keep credentials private and preserve the previous report. Exit=' +
            $child.ExitCode + '. ' + $failureText.Replace('stats-fixture-token', '[redacted]'))
    }
    foreach ($name in $reportBefore.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $fixture "artifacts/stats/$name")).Hash -ne $reportBefore[$name]) {
            throw 'Failed requests must preserve every previous report file.'
        }
    }
    Write-Host 'PASS: addon-only releases and historical full archives, original CSV/JSON columns, adjusted counts, single request, complete pagination, authentication, stale-login fallback and useful rate-limit errors preserving the report; no network calls.'
} finally {
    $env:GITHUB_TOKEN = $savedGitHubToken
    $env:GH_TOKEN = $savedGhToken
    $resolved = [IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -ne $leaf) { throw 'Unsafe stats test path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
