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

function Get-Pages([string]$Route) {
    for ($page = 1; ; $page++) {
        $items = @(Invoke-RestMethod -Uri "${api}${Route}?per_page=100&page=$page" `
            -Headers $headers -TimeoutSec 30)
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
    $releases = @(Get-Pages '/releases' | Where-Object { -not $_.draft } |
        Sort-Object published_at -Descending)
    $rows = @()
    $details = @()
    foreach ($release in $releases) {
        # Fetch assets separately so large releases are also paginated completely.
        $assets = @(Get-Pages "/releases/$($release.id)/assets" |
            Where-Object { $_.state -eq 'uploaded' -and $_.name -match '\.zip$' })
        $counts = @{ full = $null; addon = $null }
        foreach ($asset in $assets) {
            $kind = if ($asset.name -match '^WowVoice(?:TalkingHead)?-.+-addon-only\.zip$') { 'addon' }
                elseif ($asset.name -match '^WowVoice(?:TalkingHead)?-.+-lite\.zip$') { continue }
                elseif ($asset.name -match '^WowVoice(?:TalkingHead)?-.+\.zip$') { 'full' }
                else { continue }
            $counts[$kind] = [long]$counts[$kind] + [long]$asset.download_count
            $details += [pscustomobject]@{
                release = $release.tag_name; asset = $asset.name
                kind = $kind; downloads = [long]$asset.download_count
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
<div class="notes"><p>Счётчики включают повторные и проверочные скачивания. Это не число уникальных пользователей и не отдельный счётчик нажатий на сайте. Скачивания с pCloud сюда не входят.</p>
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
