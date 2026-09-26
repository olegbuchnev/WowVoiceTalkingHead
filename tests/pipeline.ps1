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
  foreach ($name in @('src', 'build.ps1', 'USER_README.md')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $fixture -Recurse
  }
  # Exercise repeated packaging with a small, real-audio fixture. The full
  # production library and its disjoint quest sets are checked by the JS suite.
  foreach ($name in @('soundpack', 'catvoices')) {
    $dest = Join-Path $fixture $name
    New-Item -ItemType Directory -Path $dest | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $project $name) -File) {
      if ($file.Extension -ne '.ogg') { Copy-Item -LiteralPath $file.FullName -Destination $dest }
    }
  }
  Copy-Item -LiteralPath (Join-Path $project 'soundpack\179a.ogg') -Destination (Join-Path $fixture 'soundpack')
  'WowVoiceDur = { ["179a"] = 12.5 }' | Set-Content -LiteralPath (Join-Path $fixture 'src\Durations.lua')
  $catSample = Get-ChildItem -LiteralPath (Join-Path $project 'catvoices') -Filter '*.ogg' -File | Select-Object -First 1
  Copy-Item -LiteralPath $catSample.FullName -Destination (Join-Path $fixture 'catvoices')
  $sampleId = $catSample.BaseName -replace '_.*$', ''
  ('WowVoiceForeverAudio = { ["' + $sampleId + 'a"] = { file = "' + $catSample.Name + '", duration = 12.5 } }') |
    Set-Content -LiteralPath (Join-Path $fixture 'src\ForeverAudio.lua')
  $build = Join-Path $fixture 'build.ps1'
  $addons = Join-Path $fixture 'game\_classic_beta_\Interface\AddOns'
  $voice = Join-Path $addons 'WowVoice'
  $sounds = Join-Path $addons 'WowVoiceSounds'
  $catSounds = Join-Path $addons 'CatVoices'
  foreach ($dir in @($voice, $sounds, $catSounds, (Join-Path $voice '.idea'), (Join-Path $addons 'Unrelated'))) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $oldCore = Join-Path $voice 'Core.lua'
  'old core' | Set-Content -LiteralPath $oldCore
  'stale' | Set-Content -LiteralPath (Join-Path $voice 'obsolete.lua')
  'workspace' | Set-Content -LiteralPath (Join-Path $voice '.idea\workspace.xml')
  Copy-Item -LiteralPath (Join-Path $fixture 'soundpack\179a.ogg') -Destination $sounds
  'extra user audio' | Set-Content -LiteralPath (Join-Path $sounds 'custom.ogg')
  'old supplemental audio' | Set-Content -LiteralPath (Join-Path $catSounds $catSample.Name)
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
  Assert-True ((Get-Content -LiteralPath (Join-Path $sounds 'custom.ogg') -Raw).Trim() -eq 'extra user audio') 'Extra user audio changed.'
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'catvoices') -File) {
    Assert-True ((Get-FileHash -LiteralPath $file.FullName).Hash -eq
      (Get-FileHash -LiteralPath (Join-Path $catSounds $file.Name)).Hash) "Supplement deployment mismatch: $($file.Name)"
  }
  Assert-True (Test-Path -LiteralPath (Join-Path $sounds 'WowVoiceSounds_Vanilla.toc')) 'Other sound TOC was removed.'
  Assert-True (Test-Path -LiteralPath (Join-Path $addons 'Unrelated\keep.txt')) 'Sibling addon was touched.'
  $backups = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'backups') -Directory)
  Assert-True ($backups.Count -eq 1) 'Expected one pre-deploy backup.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WowVoice\Core.lua') -Raw).Trim() -eq 'old core') 'Backup did not preserve old code.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceSounds\WowVoiceSounds.toc') -Raw).Trim() -eq 'old TOC') 'Backup did not preserve old TOC.'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceSounds\179a.ogg'))) 'Backup copied sound library.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName ('CatVoices\' + $catSample.Name)) -Raw).Trim() -eq 'old supplemental audio') 'Backup did not preserve supplemental audio.'
  Write-Host 'PASS: three-folder deploy, pre-write backups, Classic/extra audio/other addons/IDE state preserved.'

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
  $accidentalOgg = Join-Path $fixture 'soundpack\999999p.ogg'
  'not allowed' | Set-Content -LiteralPath $accidentalOgg
  Assert-Fails { & $build -Task Package } 'Unindexed OGG was allowed in release sources.'
  Remove-Item -LiteralPath $accidentalOgg
  foreach ($audio in @((Join-Path $fixture 'soundpack\179a.ogg'), (Join-Path $fixture ('catvoices\' + $catSample.Name)))) {
    $saved = Join-Path $fixture 'temporarily-held-audio.ogg'
    Move-Item -LiteralPath $audio -Destination $saved
    try { Assert-Fails { & $build -Task Package } 'Missing indexed audio was allowed in a complete release.' }
    finally { Move-Item -LiteralPath $saved -Destination $audio }
  }
  Write-Host 'PASS: wrong client/target, escaping TOC paths, unindexed and missing audio are rejected.'
  $supplementIndex = Join-Path $fixture 'src\ForeverAudio.lua'
  $originalSupplement = [IO.File]::ReadAllText($supplementIndex)
  [IO.File]::WriteAllText($supplementIndex, $originalSupplement.Replace($sampleId + 'a', '179a'))
  try { Assert-Fails { & $build -Task Package } 'A Classic quest was duplicated in CatVoices.' }
  finally { [IO.File]::WriteAllText($supplementIndex, $originalSupplement) }
  Write-Host 'PASS: overlapping quest IDs cannot enter the release.'

  & $build -Task Package
  $artifacts = Join-Path $fixture 'artifacts'
  $release = Join-Path $artifacts 'WoWVoice'
  $firstZip = @(Get-ChildItem -LiteralPath $release -Filter '*.zip' -File)[0].FullName
  $firstHash = (Get-FileHash -LiteralPath $firstZip).Hash
  # If an existing release cannot be replaced, it must not be truncated/deleted.
  $lock = [IO.File]::Open($firstZip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
  try { Assert-Fails { & $build -Task Package } 'Replacing a locked release should fail.' }
  finally { $lock.Dispose() }
  Assert-True ((Get-FileHash -LiteralPath $firstZip).Hash -eq $firstHash) 'Failed package damaged the previous release.'
  Assert-True (@(Get-ChildItem -LiteralPath $artifacts -Directory).Count -eq 1) 'Failed package left staging files.'
  # Give the output folder a known creation time to detect delete/recreate.
  [IO.Directory]::SetCreationTimeUtc($release, [datetime]::UtcNow.AddDays(-2))
  $folderCreated = [IO.Directory]::GetCreationTimeUtc($release)
  'old artifact' | Set-Content -LiteralPath (Join-Path $artifacts 'old.zip')
  'old release' | Set-Content -LiteralPath (Join-Path $release 'old.zip')
  & $build -Task Package
  Assert-True ([IO.Directory]::GetCreationTimeUtc($release) -eq $folderCreated) 'Package recreated the shared folder.'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $artifacts 'old.zip'))) 'Package did not clear old artifacts.'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $release 'old.zip'))) 'Package did not clear old releases.'
  # A new version gets a new filename inside the same shared folder.
  [IO.File]::WriteAllText($tocPath, ($original -replace '(?m)^(## Version: [^\r\n]+)', '$1-test'))
  & $build -Task Package
  Assert-True (-not (Test-Path -LiteralPath $firstZip)) 'Previous version survived a successful package.'
  Assert-True ([IO.Directory]::GetCreationTimeUtc($release) -eq $folderCreated) 'Version change recreated the shared folder.'
  $archives = @(Get-ChildItem -LiteralPath $release -Filter '*.zip' -File)
  Assert-True ($archives.Count -eq 1) 'Expected exactly one ZIP.'
  $expected = @{}
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -File -Recurse) {
    $relative = $file.FullName.Substring($sourcePrefix.Length).Replace('\', '/')
    $expected['WowVoice/' + $relative] = $file.FullName
  }
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'soundpack') -File) {
    $expected['WowVoiceSounds/' + $file.Name] = $file.FullName
  }
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'catvoices') -File) {
    $expected['CatVoices/' + $file.Name] = $file.FullName
  }
  $expected['README.txt'] = $null
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($archives[0].FullName)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $entries = @($archive.Entries | Where-Object { $_.Name })
    Assert-True ($entries.Count -eq $expected.Count) 'Unexpected ZIP entry count.'
    foreach ($entry in $entries) {
      $name = $entry.FullName.Replace('\', '/')
      Assert-True ($expected.ContainsKey($name)) "Unexpected archive file: $name"
      if ($name -eq 'README.txt') {
        $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
        try { $guide = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $sourceGuide = [IO.File]::ReadAllText((Join-Path $fixture 'USER_README.md'))
        Assert-True ($guide.Contains('WowVoice')) 'Plain-text guide is missing its title.'
        foreach ($url in [regex]::Matches($sourceGuide, '\]\((https?://[^)]+)\)')) {
          Assert-True ($guide.Contains($url.Groups[1].Value)) 'Plain-text guide lost a link.'
        }
        Assert-True ($guide -notmatch '(?m)^#{1,6}\s|\*\*|`|\]\(https?://') 'Markdown remained in README.txt.'
        continue
      }
      $stream = $entry.Open()
      try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
      finally { $stream.Dispose() }
      Assert-True ($hash -eq (Get-FileHash -LiteralPath $expected[$name] -Algorithm SHA256).Hash) "ZIP content mismatch: $name"
    }
  }
  finally { $sha.Dispose(); $archive.Dispose() }
  Assert-True (@(Get-ChildItem -LiteralPath $artifacts -Force).Count -eq 1) 'Expected only the shared folder in artifacts.'
  Assert-True (@(Get-ChildItem -LiteralPath $release -Force).Count -eq 1) 'Expected only the latest ZIP in the shared folder.'
  Write-Host 'PASS: ZIP contains exactly WowVoice, both audio folders and plain-text README; runtime hashes match.'
  Write-Host 'PASS: stable shared folder, version replacement, legacy ZIP cleanup and failed-build preservation.'
}
finally {
  # Only this uniquely named temporary fixture can be recursively removed.
  $resolvedFixture = [IO.Path]::GetFullPath($fixture)
  if ([IO.Path]::GetDirectoryName($resolvedFixture) -ne $tempRoot -or
      [IO.Path]::GetFileName($resolvedFixture) -ne $leaf) { throw 'Unsafe test cleanup path.' }
  Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
