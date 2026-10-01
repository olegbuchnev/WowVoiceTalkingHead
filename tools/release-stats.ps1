[CmdletBinding()]
param([switch]$NoOpen)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = 'olegbuchnev/WowVoiceTalkingHead'
$api = "https://api.github.com/repos/$repo"
$headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'WowVoice-local-stats' }
$root = Split-Path -Parent $PSScriptRoot
# This folder is gitignored and is separate from the pCloud release sync folder.
$output = Join-Path $root 'artifacts\stats'
$dateCulture = [Globalization.CultureInfo]::GetCultureInfo('en-GB')

function Get-GitHubToken {
    foreach ($name in @('GITHUB_TOKEN', 'GH_TOKEN')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
    }
    # Use an existing Git login without prompting or opening an authentication window.
    # Capture credentials in memory; never write them to the report or console.
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    $process = $null
    try {
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $git.Source
        $start.Arguments = '-c credential.interactive=false credential fill'
        $start.WorkingDirectory = $root
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
        $start.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
        $process = [Diagnostics.Process]::Start($start)
        $process.StandardInput.Write("protocol=https`nhost=github.com`n`n")
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(5000)) { $process.Kill(); return $null }
        if ($process.ExitCode -ne 0) { return $null }
        foreach ($line in ($stdout.Result -split "`r?`n")) {
            if ($line.StartsWith('password=')) { return $line.Substring(9) }
        }
    } catch {
        return $null
    } finally {
        if ($process) { $process.Dispose() }
    }
    return $null
}

function Get-ApiFailure($Failure) {
    $response = if ($Failure.Exception.PSObject.Properties['Response']) { $Failure.Exception.Response } else { $null }
    $status = if ($response) { [int]$response.StatusCode } else { 0 }
    $message = if ($status -eq 403 -or $status -eq 429) {
        if ($response.Headers['X-RateLimit-Remaining'] -eq '0') {
            $reset = 0L
            $time = if ([long]::TryParse($response.Headers['X-RateLimit-Reset'], [ref]$reset)) {
                [DateTimeOffset]::FromUnixTimeSeconds($reset).ToLocalTime().ToString('HH:mm:ss zzz')
            } else { $null }
            'GitHub API request limit reached.' + $(if ($time) { " Retry after $time." }) +
                ' Use an existing GitHub login in Git, or set GH_TOKEN/GITHUB_TOKEN.'
        } elseif ($response.Headers['Retry-After']) {
            "GitHub temporarily limited API requests. Retry after $($response.Headers['Retry-After']) seconds."
        } else {
            'GitHub refused the API request (HTTP ' + $status + '). Check account access or try again later.'
        }
    } elseif ($status -eq 401) {
        'GitHub rejected the saved login or token (HTTP 401). Refresh the login in Git or GH_TOKEN/GITHUB_TOKEN.'
    } else { $Failure.Exception.Message }
    return [pscustomobject]@{ Status = $status; Message = $message }
}

function Get-Pages([string]$Route) {
    for ($page = 1; ; $page++) {
        $uri = "${api}${Route}?per_page=100&page=$page"
        try {
            $items = @(Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30)
        } catch {
            $failure = Get-ApiFailure $_
            # A stale optional login must not prevent access to public statistics.
            if ($failure.Status -eq 401 -and $headers.ContainsKey('Authorization')) {
                $headers.Remove('Authorization')
                try { $items = @(Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30) }
                catch { throw (Get-ApiFailure $_).Message }
            } else { throw $failure.Message }
        }
        foreach ($item in $items) { $item }
        if ($items.Count -lt 100) { break }
    }
}

function Escape-Html($Value) { [Net.WebUtility]::HtmlEncode([string]$Value) }
function Count-Text($Value) {
    if ($null -eq $Value) { return '—' }
    return ([long]$Value).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('ru-RU'))
}

try {
    $token = Get-GitHubToken
    if ($token) { $headers.Authorization = 'Bearer ' + $token }
    $token = $null
    # Asset IDs change on replacement even when the filename and tag stay the same.
    $checksByAsset = @{}
    $checksFile = Join-Path $root 'config\release-download-checks.json'
    if (Test-Path -LiteralPath $checksFile -PathType Leaf) {
        $ledger = Get-Content -LiteralPath $checksFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($ledger.schemaVersion -ne 1) { throw 'Unsupported download-check ledger schema.' }
        foreach ($check in $ledger.checks) {
            $id = [long]$check.assetId
            $count = [long]$check.count
            if ($id -le 0 -or $id -ne [double]$check.assetId -or $count -lt 0 -or $count -ne [double]$check.count `
                -or $checksByAsset.ContainsKey([string]$id)) { throw 'Invalid or duplicate download-check ledger entry.' }
            $checksByAsset[[string]$id] = $count
        }
    }
    $releases = @(Get-Pages '/releases' | Where-Object { -not $_.draft } |
        Sort-Object published_at -Descending)
    $rows = @()
    $details = @()
    foreach ($release in $releases) {
        # Release responses already include assets. Only potentially capped lists
        # need separate pagination; ordinary runs require one request for all releases.
        $embedded = $release.PSObject.Properties['assets']
        $assets = if ($embedded -and @($release.assets).Count -lt 100) { @($release.assets) }
            else { @(Get-Pages "/releases/$($release.id)/assets") }
        $assets = @($assets | Where-Object { $_.state -eq 'uploaded' -and $_.name -match '\.zip$' })
        $counts = @{ full = $null; addon = $null }
        foreach ($asset in $assets) {
            $kind = if ($asset.name -match '^WowVoice(?:TalkingHead)?-.+-addon-only\.zip$') { 'addon' }
                elseif ($asset.name -match '^WowVoice(?:TalkingHead)?-.+-lite\.zip$') { continue }
                elseif ($asset.name -match '^WowVoice(?:TalkingHead)?-.+\.zip$') { 'full' }
                else { continue }
            $raw = [long]$asset.download_count
            $recordedChecks = [long]$checksByAsset[[string]$asset.id]
            # GitHub may report a delayed counter; deductions can never make it negative.
            $checks = [Math]::Min($raw, $recordedChecks)
            $adjusted = $raw - $checks
            $counts[$kind] = [long]$counts[$kind] + $adjusted
            $details += [pscustomobject]@{
                release = $release.tag_name; asset = $asset.name
                kind = $kind; downloads = $adjusted
            }
        }
        $rows += [pscustomobject]@{
            Release = $release.tag_name
            PublishedUTC = ([DateTimeOffset]::Parse($release.published_at)).UtcDateTime.ToString('yyyy-MM-dd')
            Full = $counts.full; AddonOnly = $counts.addon
            Total = [long]$counts.full + [long]$counts.addon
        }
    }
    $collectedAt = [DateTimeOffset]::UtcNow
    $collected = $collectedAt.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    $collectedDisplay = $collectedAt.ToString('d MMMM yyyy, HH:mm', $dateCulture) + ' UTC'
    $displayRows = @($rows | Select-Object Release, @{Name = 'Published'; Expression = {
        [DateTime]::ParseExact($_.PublishedUTC, 'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture).ToString('d MMMM yyyy', $dateCulture)
    }}, Full, AddonOnly, Total)
    $totalFull = [long](($rows | Measure-Object Full -Sum).Sum)
    $totalAddon = [long](($rows | Measure-Object AddonOnly -Sum).Sum)
    $total = $totalFull + $totalAddon
    $tableRows = foreach ($row in $displayRows) {
        '<tr><th scope="row">' + (Escape-Html $row.Release) + '</th><td>' + $row.Published +
            '</td><td>' + (Count-Text $row.Full) + '</td><td>' + (Count-Text $row.AddonOnly) +
            '</td><td>' + (Count-Text $row.Total) + '</td></tr>'
    }
    if (-not $rows.Count) { $tableRows = '<tr><td colspan="5">Опубликованных релизов пока нет.</td></tr>' }
    $html = @"
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>WowVoice — статистика скачиваний</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#202523;color:#e1e7e4;font:16px/1.6 system-ui,sans-serif}
main{max-width:1020px;margin:48px auto;padding:0 24px}h1{font-size:28px;margin:0 0 8px}p{margin:8px 0 20px}.muted{color:#a9b7af}
.cards{display:flex;gap:16px;flex-wrap:wrap;margin:28px 0}.card{flex:1;min-width:180px;border:1px solid #415249;border-radius:8px;padding:16px 20px;background:#29372f}
.card strong{display:block;color:#a7e0c6;font-size:32px}.table{overflow-x:auto}table{border-collapse:collapse;width:100%;white-space:nowrap}
th,td{padding:12px 14px;border-bottom:1px solid #415249;text-align:right}th:first-child,thead th:nth-child(2),tbody td:nth-child(2){text-align:left}thead{color:#a7e0c6}tbody th{font-weight:500}tfoot{font-weight:700}
a{color:#a7e0c6}code{background:#29372f;padding:2px 6px;border-radius:4px}.notes{font-size:14px;color:#a9b7af;margin-top:28px}
</style></head><body><main>
<h1>Скачивания WowVoice TalkingHead</h1>
<p class="muted">Локальный отчёт · GitHub Releases · обновлён $collectedDisplay</p>
<div class="cards"><div class="card">Всего ZIP<strong>$(Count-Text $total)</strong></div><div class="card">Полный комплект<strong>$(Count-Text $totalFull)</strong></div><div class="card">Только аддон<strong>$(Count-Text $totalAddon)</strong></div></div>
<div class="table"><table><thead><tr><th>Релиз</th><th title="Дата публикации по UTC">Дата релиза</th><th>Полный</th><th>Только аддон</th><th>Всего</th></tr></thead>
<tbody>$($tableRows -join "`n")</tbody><tfoot><tr><th colspan="2">Итого</th><td>$(Count-Text $totalFull)</td><td>$(Count-Text $totalAddon)</td><td>$(Count-Text $total)</td></tr></tfoot></table></div>
<p><a href="downloads.csv" download>Скачать таблицу CSV для Excel</a></p>
<p>Для обновления снова запусти <code>stats.cmd</code>. Эта страница — сохранённый снимок, перезагрузка браузера не запрашивает новые данные.</p>
<div class="notes"><p>Известные наши проверочные скачивания исключены. Остальные повторные и проверочные скачивания остаются в счётчиках. Это не число уникальных пользователей и не отдельный счётчик нажатий на сайте. Скачивания с pCloud сюда не входят.</p>
<p>Учитываются полные и addon-only архивы WowVoice, прикреплённые к существующим опубликованным релизам, включая предварительные. Другие файлы, исторические lite-архивы и автоматически созданные GitHub архивы исходников исключены. Удалённые или заменённые файлы не сохраняют прежний счётчик в этом отчёте. «—» означает, что архива такого типа в релизе нет.</p>
<p>Отчёт хранится только на этом компьютере и не публикуется. Исходные счётчики публичного репозитория доступны через GitHub API.</p></div>
</main></body></html>
"@
    # Do not touch the previous report until every request has succeeded.
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $displayRows | Export-Csv -LiteralPath (Join-Path $output 'downloads.csv') -NoTypeInformation -Encoding UTF8 -UseCulture
    [IO.File]::WriteAllText((Join-Path $output 'downloads.json'),
        ([ordered]@{ repository = $repo; collectedAtUTC = $collected; releases = $rows; assets = $details } | ConvertTo-Json -Depth 5),
        [Text.UTF8Encoding]::new($false))
    $report = Join-Path $output 'index.html'
    [IO.File]::WriteAllText($report, $html, [Text.UTF8Encoding]::new($false))
    $displayRows | Format-Table -AutoSize
    Write-Host "Total ZIP downloads: $total. Updated: $collectedDisplay"
    Write-Host "Local report: $report"
    if (-not $NoOpen) { Invoke-Item -LiteralPath $report }
} catch {
    Write-Error "Could not update release statistics. $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
