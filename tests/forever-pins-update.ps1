Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\check-forever-pins.ps1')

function Assert-True([bool]$Value, [string]$Message) {
  if (-not $Value) { throw $Message }
}
function Invoke-RestMethod {
  param($Uri, $TimeoutSec, $Headers, $ErrorAction)
  Assert-True ($Uri -match 'path=Database%2FForeverQuests.lua&per_page=1') 'Must check the database file.'
  Assert-True ($TimeoutSec -eq 10) 'Network check needs a bounded timeout.'
  if ($script:networkError) { throw 'Network unavailable (fixture)' }
  return $script:response
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('wowvoice-pins-check-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$manifest = Join-Path $fixture 'source.json'
$report = Join-Path $fixture 'report.json'
try {
  $imported = 'a' * 40
  @{commit=$imported} | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
  $hash = (Get-FileHash -LiteralPath $manifest).Hash
  $script:networkError = $false
  $script:response = @([pscustomobject]@{sha=$imported;commit=@{committer=@{date='2026-10-11T00:00:00Z'}}})
  $result = Invoke-ForeverPinsCheck -ManifestPath $manifest -ReportPath $report
  Assert-True ($result.status -eq 'current') 'Matching commits must be current.'
  $script:response[0].sha = 'b' * 40
  $result = Invoke-ForeverPinsCheck -ManifestPath $manifest -ReportPath $report
  Assert-True ($result.status -eq 'changed' -and $result.latestCommit -eq ('b' * 40)) 'Changed data must be reported.'
  Assert-True ($result.url.EndsWith('b' * 40)) 'Update link must point to the checked commit.'
  $script:networkError = $true
  $result = Invoke-ForeverPinsCheck -ManifestPath $manifest -ReportPath $report
  $saved = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
  Assert-True ($result.status -eq 'unavailable' -and $saved.status -eq 'unavailable') 'Network failure must replace stale success.'
  Assert-True ($null -eq $saved.latestCommit) 'Do not present a stale latest commit as a fresh check.'
  $script:networkError = $false
  foreach ($response in @(@(), @([pscustomobject]@{sha='invalid'}))) {
    $script:response = $response
    $result = Invoke-ForeverPinsCheck -ManifestPath $manifest -ReportPath $report
    Assert-True ($result.status -eq 'unavailable') 'Missing/malformed remote commit must fail the check.'
  }
  Assert-True ((Get-FileHash -LiteralPath $manifest).Hash -eq $hash) 'Check must never update the source snapshot.'
  Write-Host 'PASS: Pins update detection, bounded request, missing/invalid responses, offline reporting and unchanged imported data.'
} finally {
  foreach ($file in @($manifest, $report)) {
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
  }
  Remove-Item -LiteralPath $fixture
}
