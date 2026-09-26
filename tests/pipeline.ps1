Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$leaf = 'wowvoice-pipeline-' + [guid]::NewGuid().ToString('N')
$fixture = Join-Path $tempRoot $leaf
New-Item -ItemType Directory -Path $fixture | Out-Null

function Assert-True {
  param([bool]$Value, [string]$Message)
  if (-not $Value) { throw $Message }
}

function Assert-Fails {
  param([scriptblock]$Action, [string]$Message)
  $failed = $false
  try { & $Action } catch { $failed = $true }
  Assert-True $failed $Message
}

try {
  foreach ($name in @('src', 'soundpack', 'build.ps1', 'USER_README.md')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $fixture -Recurse
  }
  $build = Join-Path $fixture 'build.ps1'
  $addons = Join-Path $fixture 'game\_classic_beta_\Interface\AddOns'
  $voice = Join-Path $addons 'WowVoice'
  $sounds = Join-Path $addons 'WowVoiceSounds'
  foreach ($dir in @($voice, $sounds, (Join-Path $voice '.idea'), (Join-Path $addons 'Unrelated'))) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $oldCore = Join-Path $voice 'Core.lua'
  'old core' | Set-Content -LiteralPath $oldCore
  'stale' | Set-Content -LiteralPath (Join-Path $voice 'obsolete.lua')
  'workspace' | Set-Content -LiteralPath (Join-Path $voice '.idea\workspace.xml')
  'ogg sentinel' | Set-Content -LiteralPath (Join-Path $sounds '179a.ogg')
  'old TOC' | Set-Content -LiteralPath (Join-Path $sounds 'WowVoiceSounds.toc')
  'vanilla sentinel' | Set-Content -LiteralPath (Join-Path $sounds 'WowVoiceSounds_Vanilla.toc')
  'unrelated' | Set-Content -LiteralPath (Join-Path $addons 'Unrelated\keep.txt')
  $soundHash = (Get-FileHash -LiteralPath (Join-Path $sounds '179a.ogg')).Hash
  $config = Join-Path $fixture 'targets.psd1'
  "@{ ForeverBeta = '$($addons.Replace("'", "''"))' }" | Set-Content -LiteralPath $config

  & $build -Task Deploy -Target ForeverBeta -ConfigPath $config
  $sourcePrefix = (Join-Path $fixture 'src') + '\'
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -File -Recurse) {
    $relative = $file.FullName.Substring($sourcePrefix.Length)
    Assert-True ((Get-FileHash -LiteralPath $file.FullName).Hash -eq
      (Get-FileHash -LiteralPath (Join-Path $voice $relative)).Hash) "Deployment mismatch: $relative"
  }
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'obsolete.lua'))) 'Stale runtime file survived.'
  Assert-True (Test-Path -LiteralPath (Join-Path $voice '.idea\workspace.xml')) 'IDE state was removed.'
  Assert-True ((Get-FileHash -LiteralPath (Join-Path $sounds '179a.ogg')).Hash -eq $soundHash) 'OGG changed.'
  Assert-True (Test-Path -LiteralPath (Join-Path $sounds 'WowVoiceSounds_Vanilla.toc')) 'Other sound TOC was removed.'
  Assert-True (Test-Path -LiteralPath (Join-Path $addons 'Unrelated\keep.txt')) 'Sibling addon was touched.'
  $backups = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'backups') -Directory)
  Assert-True ($backups.Count -eq 1) 'Expected one pre-deploy backup.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WowVoice\Core.lua') -Raw).Trim() -eq 'old core') 'Backup did not preserve old code.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceSounds\WowVoiceSounds.toc') -Raw).Trim() -eq 'old TOC') 'Backup did not preserve old TOC.'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceSounds\179a.ogg'))) 'Backup copied sound library.'
  Write-Host 'PASS: deploy sync, pre-write backups, OGG/other addons/IDE state preserved.'

  $retail = Join-Path $fixture 'game\_retail_\Interface\AddOns'
  New-Item -ItemType Directory -Path $retail -Force | Out-Null
  "@{ ForeverBeta = '$($retail.Replace("'", "''"))' }" | Set-Content -LiteralPath $config
  Assert-Fails { & $build -Task Deploy -ConfigPath $config } 'Retail path accepted.'
  Assert-Fails { & $build -Task Deploy -Target Retail -ConfigPath $config } 'Retail target accepted.'
  Assert-True (@(Get-ChildItem -LiteralPath $retail -Force).Count -eq 0) 'Rejected deployment wrote files.'
  $tocPath = Join-Path $fixture 'src\WowVoice.toc'
  $original = [IO.File]::ReadAllText($tocPath)
  [IO.File]::AppendAllText($tocPath, "`n..\outside.lua`n")
  Assert-Fails { & $build -Task Validate } 'Escaping TOC path accepted.'
  [IO.File]::WriteAllText($tocPath, $original)
  $accidentalOgg = Join-Path $fixture 'soundpack\179a.ogg'
  'not allowed' | Set-Content -LiteralPath $accidentalOgg
  Assert-Fails { & $build -Task Package } 'OGG was allowed in release sources.'
  Remove-Item -LiteralPath $accidentalOgg
  Write-Host 'PASS: wrong client/target, escaping TOC paths and accidental OGG are rejected.'

  & $build -Task Package
  $artifacts = Join-Path $fixture 'artifacts'
  'old artifact' | Set-Content -LiteralPath (Join-Path $artifacts 'old.zip')
  & $build -Task Package
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $artifacts 'old.zip'))) 'Package did not clear old artifacts.'
  $archives = @(Get-ChildItem -LiteralPath $artifacts -Filter '*.zip' -File)
  Assert-True ($archives.Count -eq 1) 'Expected exactly one ZIP.'
  $expected = @{}
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -File -Recurse) {
    $relative = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
    $expected['WowVoice/' + $relative] = $file.FullName
  }
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'soundpack') -File) {
    $expected['WowVoiceSounds/' + $file.Name] = $file.FullName
  }
  $expected['README.md'] = Join-Path $fixture 'USER_README.md'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($archives[0].FullName)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $entries = @($archive.Entries | Where-Object { $_.Name })
    Assert-True ($entries.Count -eq $expected.Count) 'Unexpected ZIP entry count.'
    foreach ($entry in $entries) {
      $name = $entry.FullName.Replace('\', '/')
      Assert-True ($expected.ContainsKey($name)) "Unexpected archive file: $name"
      $stream = $entry.Open()
      try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
      finally { $stream.Dispose() }
      Assert-True ($hash -eq (Get-FileHash -LiteralPath $expected[$name] -Algorithm SHA256).Hash) "ZIP content mismatch: $name"
    }
  }
  finally { $sha.Dispose(); $archive.Dispose() }
  Assert-True (@(Get-ChildItem -LiteralPath $artifacts -Force).Count -eq 1) 'Expected only the release ZIP in artifacts.'
  Write-Host 'PASS: ZIP contains exactly WowVoice, two sound TOCs and user README; hashes match.'
}
finally {
  # Only this uniquely named temporary fixture can be recursively removed.
  $resolvedFixture = [IO.Path]::GetFullPath($fixture)
  if ([IO.Path]::GetDirectoryName($resolvedFixture) -ne $tempRoot -or
      [IO.Path]::GetFileName($resolvedFixture) -ne $leaf) { throw 'Unsafe test cleanup path.' }
  Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
