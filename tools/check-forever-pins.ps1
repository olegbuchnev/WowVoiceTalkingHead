[CmdletBinding()]
param()

function Invoke-ForeverPinsCheck {
  param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\docs\internal\forever-pins-speakers-source.json'),
    [string]$ReportPath = (Join-Path $PSScriptRoot '..\artifacts\review\forever-pins-update.json')
  )
  $report = [ordered]@{
    checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'unavailable'
    importedCommit = $null
    latestCommit = $null
    latestDate = $null
    url = $null
    error = $null
  }
  try {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid imported database commit.' }
    $report.importedCommit = $manifest.commit
    # Query the data file, not general addon/UI commits. No auth or dependency required.
    $uri = 'https://api.github.com/repos/TylerAkins/forever-quest-markers/commits?path=Database%2FForeverQuests.lua&per_page=1'
    $commits = @(Invoke-RestMethod -Uri $uri -TimeoutSec 10 -Headers @{
      'User-Agent' = 'TalkingHeadRu-source-check'
      'Accept' = 'application/vnd.github+json'
    } -ErrorAction Stop)
    if ($commits.Count -ne 1 -or $commits[0].sha -notmatch '^[a-f0-9]{40}$') {
      throw 'GitHub returned no valid database commit.'
    }
    $latest = $commits[0]
    $report.latestCommit = $latest.sha
    $report.latestDate = $latest.commit.committer.date
    $report.url = 'https://github.com/TylerAkins/forever-quest-markers/commit/' + $latest.sha
    $report.status = if ($manifest.commit -eq $latest.sha) { 'current' } else { 'changed' }
  } catch {
    $report.error = $_.Exception.Message
  }
  if ($report.status -eq 'current') {
    Write-Host "Forever Quest Pins database: current ($($report.importedCommit.Substring(0, 12)))." -ForegroundColor Green
  } elseif ($report.status -eq 'changed') {
    Write-Warning "Forever Quest Pins database CHANGED: imported $($report.importedCommit.Substring(0, 12)), upstream $($report.latestCommit.Substring(0, 12)) ($($report.latestDate))."
    Write-Host $report.url
    Write-Host 'Review Database/ForeverQuests.lua and Metadata.lua at that commit, then import with:'
    Write-Host "node tools/import-forever-pins-speakers.js <Database-directory> $($report.latestCommit)"
  } else {
    Write-Warning "Forever Quest Pins database: NOT CHECKED. $($report.error) Retry: .\build.cmd -Task CheckSources"
  }
  $parent = Split-Path -Parent ([IO.Path]::GetFullPath($ReportPath))
  [IO.Directory]::CreateDirectory($parent) | Out-Null
  [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 5) + "`n", [Text.UTF8Encoding]::new($false))
  return [pscustomobject]$report
}

if ($MyInvocation.InvocationName -ne '.') {
  $result = Invoke-ForeverPinsCheck
  if ($result.status -eq 'unavailable') { exit 1 }
}
