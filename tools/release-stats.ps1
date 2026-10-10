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
    } elseif ($status -eq 0) {
        'Cannot connect to api.github.com. Check the network, VPN or proxy and retry later.'
    } else { 'GitHub API request failed (HTTP ' + $status + '). Retry later.' }
    return [pscustomobject]@{ Status = $status; Message = $message }
}

function Invoke-GitHubRequest([string]$Uri) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { return Invoke-RestMethod -Uri $Uri -Headers $headers -TimeoutSec 10 }
        catch {
            $failure = Get-ApiFailure $_
            if ($attempt -eq 3 -or ($failure.Status -ne 0 -and $failure.Status -lt 500)) { throw }
            Write-Warning "GitHub request failed; retrying ($($attempt + 1)/3)."
            Start-Sleep -Seconds $attempt
        }
    }
}

function Get-Pages([string]$Route) {
    for ($page = 1; ; $page++) {
        $uri = "${api}${Route}?per_page=100&page=$page"
        try {
            $items = @(Invoke-GitHubRequest $uri)
        } catch {
            $failure = Get-ApiFailure $_
            # A stale optional login must not prevent access to public statistics.
            if ($failure.Status -eq 401 -and $headers.ContainsKey('Authorization')) {
                $headers.Remove('Authorization')
                try { $items = @(Invoke-GitHubRequest $uri) }
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

function Get-CurseForgeClicks {
    $result = [pscustomobject][ordered]@{
        event = 'curseforge-open'; status = 'unconfigured'
        startUTC = '2026-10-10T00:00:00Z'; collectedAtUTC = $null
        rawClicks = $null; excludedClicks = $null; clicks = $null
        message = 'Не подключено: добавьте API-токен в config/goatcounter-token.local.txt.'
    }
    $goatToken = $null
    try {
        $deductions = 0L
        $clickLedger = Join-Path $root 'config\curseforge-click-checks.json'
        if (Test-Path -LiteralPath $clickLedger) {
            $ledger = Get-Content -LiteralPath $clickLedger -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($ledger.schemaVersion -ne 1 -or $ledger.event -cne $result.event) { throw 'Invalid click ledger.' }
            foreach ($check in $ledger.checks) {
                $n = 0L
                if (-not [long]::TryParse([string]$check.count, [ref]$n) -or $n -lt 0) { throw 'Invalid click deduction.' }
                $deductions = [long]($deductions + $n)
            }
        }
        $goatToken = [Environment]::GetEnvironmentVariable('GOATCOUNTER_API_TOKEN')
        $tokenFile = Join-Path $root 'config\goatcounter-token.local.txt'
        if ([string]::IsNullOrWhiteSpace($goatToken) -and (Test-Path -LiteralPath $tokenFile)) {
            $goatToken = Get-Content -LiteralPath $tokenFile -Raw -Encoding UTF8
        }
        if (-not [string]::IsNullOrWhiteSpace($goatToken)) {
            $result.status = 'unavailable'
            $now = [DateTimeOffset]::UtcNow
            $end = $now.AddHours(1).ToString("yyyy-MM-dd'T'HH':00:00Z'")
            $uri = 'https://tove2889.goatcounter.com/api/v0/stats/hits?path_by_name=true&include_paths=curseforge-open&limit=100' +
                '&start=' + [Uri]::EscapeDataString($result.startUTC) + '&end=' + [Uri]::EscapeDataString($end)
            $response = Invoke-RestMethod -Uri $uri -Headers @{
                Authorization = 'Bearer ' + $goatToken.Trim()
                'Content-Type' = 'application/json'; 'User-Agent' = 'TalkingHeadRu-local-stats'
            } -TimeoutSec 30
            if (-not $response.PSObject.Properties['hits'] -or $response.more) { throw 'Incomplete click response.' }
            $allHits = @($response.hits | Where-Object { $null -ne $_ })
            $hits = @($allHits | Where-Object { $_.event -eq $true -and $_.path -ceq $result.event })
            if ($hits.Count -gt 1 -or $allHits.Count -ne $hits.Count) { throw 'Unexpected click response.' }
            $raw = 0L
            if ($hits.Count -eq 1 -and (-not [long]::TryParse([string]$hits[0].count, [ref]$raw) -or $raw -lt 0)) {
                throw 'Invalid click counter.'
            }
            $result.rawClicks = $raw
            $result.collectedAtUTC = $now.ToString('o')
            $result.status = 'ok'
            $result.message = 'Без известных проверочных переходов. Данные с 10.10.2026.'
        }
    } catch {
        # Never include server response bodies or exception text: they may echo credentials.
        $result.status = 'unavailable'
        $result.message = 'Не удалось обновить переходы. Проверьте API-токен, право чтения статистики, соединение и файл вычетов.'
    } finally { $goatToken = $null }
    if ($result.status -ne 'ok') {
        # Keep the last successful sample visibly dated instead of reporting a false zero.
        $cacheFile = Join-Path $output 'curseforge-clicks.json'
        try {
            if (Test-Path -LiteralPath $cacheFile) {
                $cached = Get-Content -LiteralPath $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cached.event -ceq $result.event -and $cached.startUTC -eq $result.startUTC -and
                    $cached.status -in @('ok', 'stale') -and $null -ne $cached.clicks) {
                    $result.rawClicks = $cached.rawClicks
                    $result.excludedClicks = $cached.excludedClicks
                    $result.clicks = $cached.clicks
                    $result.collectedAtUTC = $cached.collectedAtUTC
                    $result.status = 'stale'
                    $result.message += ' Показан предыдущий результат от ' + $cached.collectedAtUTC + '.'
                }
            }
        } catch { <# Ignore an unreadable cache; unknown is better than zero. #> }
    } else {
        $result.excludedClicks = [Math]::Min($result.rawClicks, $deductions)
        $result.clicks = $result.rawClicks - $result.excludedClicks
    }
    return $result
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
    $githubStatus = 'ok'
    $githubMessage = ''
    $githubCollected = $null
    $rows = @()
    $details = @()
    try {
    $releases = @(Get-Pages '/releases' | Where-Object { -not $_.draft } |
        Sort-Object published_at -Descending)
    foreach ($release in $releases) {
        # Release responses already include assets. Only potentially capped lists
        # need separate pagination; ordinary runs require one request for all releases.
        $embedded = $release.PSObject.Properties['assets']
        $assets = if ($embedded -and @($release.assets).Count -lt 100) { @($release.assets) }
            else { @(Get-Pages "/releases/$($release.id)/assets") }
        $assets = @($assets | Where-Object { $_.state -eq 'uploaded' -and $_.name -match '\.zip$' })
        $counts = @{ full = $null; addon = $null }
        foreach ($asset in $assets) {
            $kind = if ($asset.name -match '^TalkingHeadRu-.+-full\.zip$') { 'full' }
                elseif ($asset.name -match '^TalkingHeadRu-.+\.zip$') { 'addon' }
                elseif ($asset.name -match '^WowVoice(?:TalkingHead)?-.+-addon-only\.zip$') { 'addon' }
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
    } catch {
        $githubStatus = 'unavailable'
        $githubMessage = 'GitHub: ' + $_.Exception.Message
        Write-Warning $githubMessage
        # Discard partial pages. A cached sample is already adjusted; never deduct twice.
        $rows = @()
        $details = @()
        $downloadsCache = Join-Path $output 'downloads.json'
        try {
            if (Test-Path -LiteralPath $downloadsCache) {
                $cachedDownloads = Get-Content -LiteralPath $downloadsCache -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($cachedDownloads.repository -ne $repo) { throw 'Wrong cached repository.' }
                $cachedRows = @($cachedDownloads.releases)
                foreach ($cachedRow in $cachedRows) {
                    [void][DateTime]::ParseExact($cachedRow.PublishedUTC, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                    if ($cachedRow.Total -lt 0 -or $cachedRow.Total -ne ([long]$cachedRow.Full + [long]$cachedRow.AddonOnly)) {
                        throw 'Invalid cached count.'
                    }
                }
                $githubCollected = [string]$cachedDownloads.collectedAtUTC
                if ([string]::IsNullOrWhiteSpace($githubCollected)) { throw 'Missing cache timestamp.' }
                $rows = $cachedRows
                $details = @($cachedDownloads.assets)
                $githubStatus = 'stale'
            }
        } catch { <# An unreadable cache is unavailable, never a fresh zero. #> }
        $githubMessage += if ($githubStatus -eq 'stale') {
            ' Показаны сохранённые скачивания от ' + $githubCollected + '. Сейчас обновить их не удалось.'
        } else { ' Сохранённых данных нет. Скачивания временно недоступны.' }
    }
    $collectedAt = [DateTimeOffset]::UtcNow
    $collected = $collectedAt.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    $collectedDisplay = $collectedAt.ToString('d MMMM yyyy, HH:mm', $dateCulture) + ' UTC'
    if ($githubStatus -eq 'ok') {
        $githubCollected = $collected
        $githubMessage = 'GitHub Releases · обновлено ' + $collectedDisplay
    }
    $displayRows = @($rows | Select-Object Release, @{Name = 'Published'; Expression = {
        [DateTime]::ParseExact($_.PublishedUTC, 'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture).ToString('d MMMM yyyy', $dateCulture)
    }}, Full, AddonOnly, Total)
    $totalFull = if ($rows.Count) { [long](($rows | Measure-Object Full -Sum).Sum) } else { 0L }
    $totalAddon = if ($rows.Count) { [long](($rows | Measure-Object AddonOnly -Sum).Sum) } else { 0L }
    $total = $totalFull + $totalAddon
    if ($githubStatus -eq 'unavailable') { $totalFull = $null; $totalAddon = $null; $total = $null }
    $tableRows = foreach ($row in $displayRows) {
        '<tr><th scope="row">' + (Escape-Html $row.Release) + '</th><td>' + $row.Published +
            '</td><td>' + (Count-Text $row.Full) + '</td><td>' + (Count-Text $row.AddonOnly) +
            '</td><td>' + (Count-Text $row.Total) + '</td></tr>'
    }
    if (-not $rows.Count) {
        $emptyMessage = if ($githubStatus -eq 'unavailable') { 'Данные GitHub временно недоступны.' } else { 'Опубликованных релизов пока нет.' }
        $tableRows = '<tr><td colspan="5">' + $emptyMessage + '</td></tr>'
    }
    $clicks = Get-CurseForgeClicks
    $downloadsLink = if ($githubStatus -eq 'ok' -or (Test-Path -LiteralPath (Join-Path $output 'downloads.csv'))) {
        '<p><a href="downloads.csv" download>Скачать таблицу CSV для Excel</a></p>'
    } else { '' }
    $html = @"
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>TalkingHead Ru — статистика</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#202523;color:#e1e7e4;font:16px/1.6 system-ui,sans-serif}
main{max-width:1020px;margin:48px auto;padding:0 24px}h1{font-size:28px;margin:0 0 8px}p{margin:8px 0 20px}.muted{color:#a9b7af}
.cards{display:flex;gap:16px;flex-wrap:wrap;margin:28px 0}.card{flex:1;min-width:180px;border:1px solid #415249;border-radius:8px;padding:16px 20px;background:#29372f}
.card strong{display:block;color:#a7e0c6;font-size:32px}.table{overflow-x:auto}table{border-collapse:collapse;width:100%;white-space:nowrap}
th,td{padding:12px 14px;border-bottom:1px solid #415249;text-align:right}th:first-child,thead th:nth-child(2),tbody td:nth-child(2){text-align:left}thead{color:#a7e0c6}tbody th{font-weight:500}tfoot{font-weight:700}
a{color:#a7e0c6}code{background:#29372f;padding:2px 6px;border-radius:4px}.notes{font-size:14px;color:#a9b7af;margin-top:28px}
.clicks{border:1px solid #675044;border-left:3px solid #f16436;padding:20px;margin:28px 0;background:#2c2926}.clicks h2{font-size:20px;margin:0 0 8px}.clicks strong{display:block;font-size:32px;color:#ff976e}.clicks p:last-child{margin-bottom:0}
</style></head><body><main>
<h1>Статистика TalkingHead Ru</h1>
<p class="muted">Локальный отчёт · сформирован $collectedDisplay</p>
<p class="muted">$(Escape-Html $githubMessage)</p>
<div class="cards"><div class="card">Всего ZIP<strong>$(Count-Text $total)</strong></div><div class="card">Аддон<strong>$(Count-Text $totalAddon)</strong></div><div class="card">Старые полные архивы<strong>$(Count-Text $totalFull)</strong></div></div>
<p class="muted">Начиная с 1.2.5 выпускается только архив аддона. Скачивания полных архивов прошлых релизов сохраняются в статистике и входят в общую сумму.</p>
<div class="table"><table><thead><tr><th>Релиз</th><th title="Дата публикации по UTC">Дата релиза</th><th>Старый полный архив</th><th>Аддон</th><th>Всего</th></tr></thead>
<tbody>$($tableRows -join "`n")</tbody><tfoot><tr><th colspan="2">Итого</th><td>$(Count-Text $totalFull)</td><td>$(Count-Text $totalAddon)</td><td>$(Count-Text $total)</td></tr></tfoot></table></div>
$downloadsLink
<section class="clicks"><h2>Переходы на CurseForge с сайта</h2><strong>$(Count-Text $clicks.clicks)</strong>
<p class="muted">$(Escape-Html $clicks.message)</p>
<p>Нажатия на кнопку «Открыть на CurseForge». Это не скачивания и не установки; в сумму ZIP выше не входят.</p>
<p><a href="curseforge-clicks.csv" download>Скачать переходы CSV</a> · <a href="https://tove2889.goatcounter.com/">Открыть GoatCounter</a></p></section>
<p>Для обновления снова запусти <code>stats.cmd</code>. Эта страница — сохранённый снимок, перезагрузка браузера не запрашивает новые данные.</p>
<div class="notes"><p>Известные наши проверочные скачивания исключены. Остальные повторные и проверочные скачивания остаются в счётчиках. Это не число уникальных пользователей и не отдельный счётчик нажатий на сайте. Скачивания с pCloud и скачивания библиотек с CurseForge сюда не входят.</p>
<p>Учитываются архивы аддона (включая прежние addon-only) и полные архивы прошлых выпусков, прикреплённые к существующим опубликованным релизам, включая предварительные. Другие файлы, исторические lite-архивы и автоматически созданные GitHub архивы исходников исключены. Удалённые или заменённые файлы не сохраняют прежний счётчик в этом отчёте. «—» означает, что архива такого типа в релизе нет.</p>
<p>Отчёт хранится только на этом компьютере и не публикуется. Исходные счётчики публичного репозитория доступны через GitHub API.</p></div>
</main></body></html>
"@
    # Refresh independent sources; never replace successful GitHub files on failure.
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    if ($githubStatus -eq 'ok') {
        $displayRows | Export-Csv -LiteralPath (Join-Path $output 'downloads.csv') -NoTypeInformation -Encoding UTF8 -UseCulture
    }
    $clicks | Select-Object event, status, startUTC, collectedAtUTC, clicks |
        Export-Csv -LiteralPath (Join-Path $output 'curseforge-clicks.csv') -NoTypeInformation -Encoding UTF8 -UseCulture
    [IO.File]::WriteAllText((Join-Path $output 'curseforge-clicks.json'), ($clicks | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    if ($githubStatus -eq 'ok') {
      [IO.File]::WriteAllText((Join-Path $output 'downloads.json'),
        ([ordered]@{ repository = $repo; collectedAtUTC = $collected; releases = $rows; assets = $details } | ConvertTo-Json -Depth 5),
        [Text.UTF8Encoding]::new($false))
    }
    $report = Join-Path $output 'index.html'
    [IO.File]::WriteAllText($report, $html, [Text.UTF8Encoding]::new($false))
    $displayRows | Format-Table -AutoSize
    Write-Host "Total ZIP downloads: $(Count-Text $total) [$githubStatus]. GitHub sample: $githubCollected"
    Write-Host "CurseForge clicks: $(Count-Text $clicks.clicks) [$($clicks.status)]"
    Write-Host "Local report: $report"
    if (-not $NoOpen) { Invoke-Item -LiteralPath $report }
} catch {
    Write-Error "Could not update release statistics. $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
