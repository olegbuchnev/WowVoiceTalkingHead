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
  foreach ($name in @('src', 'dev', 'build.ps1', 'USER_README.md')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $fixture -Recurse
  }
  # Exercise repeated packaging with a small, real-audio fixture. The full
  # production library and its disjoint quest sets are checked by the JS suite.
  foreach ($name in @('soundpack')) {
    $dest = Join-Path $fixture $name
    New-Item -ItemType Directory -Path $dest | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $project $name) -File) {
      if ($file.Extension -ne '.ogg') { Copy-Item -LiteralPath $file.FullName -Destination $dest }
    }
  }
  Copy-Item -LiteralPath (Join-Path $project 'soundpack\179a.ogg') -Destination (Join-Path $fixture 'soundpack')
  'WowVoiceDur = { ["179a"] = 12.5 }' | Set-Content -LiteralPath (Join-Path $fixture 'src\Durations.lua')
  $build = Join-Path $fixture 'build.ps1'
  $addons = Join-Path $fixture 'game\_classic_beta_\Interface\AddOns'
  $voice = Join-Path $addons 'WowVoiceTalkingHead'
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
  'old supplemental audio' | Set-Content -LiteralPath (Join-Path $catSounds 'keep.ogg')
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
  Assert-True (Test-Path -LiteralPath (Join-Path $sounds 'WowVoiceSounds_Vanilla.toc')) 'Other sound TOC was removed.'
  Assert-True (Test-Path -LiteralPath (Join-Path $addons 'Unrelated\keep.txt')) 'Sibling addon was touched.'
  $backups = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'backups') -Directory)
  Assert-True ($backups.Count -eq 1) 'Expected one pre-deploy backup.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceTalkingHead\Core.lua') -Raw).Trim() -eq 'old core') 'Backup did not preserve old code.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceSounds\WowVoiceSounds.toc') -Raw).Trim() -eq 'old TOC') 'Backup did not preserve old TOC.'
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'WowVoiceSounds\179a.ogg'))) 'Backup copied sound library.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $catSounds 'keep.ogg') -Raw).Trim() -eq 'old supplemental audio') 'Legacy CatVoices must not be modified.'
  Write-Host 'PASS: two-folder deploy, pre-write backups, Classic/extra audio/other addons/IDE state preserved.'

  foreach ($taskName in @('Deploy', 'DeployAddon')) {
    & $build -Task $taskName -LocalDebug -ConfigPath $config
    foreach ($module in @('Comparison.lua', 'VoiceComparison.lua')) {
      Assert-True ((Get-FileHash -LiteralPath (Join-Path $voice $module)).Hash -eq
        (Get-FileHash -LiteralPath (Join-Path $fixture ('src\' + $module))).Hash) 'Public comparison module was not deployed.'
    }
    foreach ($toc in Get-ChildItem -LiteralPath $voice -Filter '*.toc') {
      $entries = @(Get-Content -LiteralPath $toc.FullName | Where-Object { $_ -in @('Comparison.lua', 'VoiceComparison.lua') })
      Assert-True (($entries -join ',') -eq 'Comparison.lua,VoiceComparison.lua') 'Incorrect public catalogue load order.'
      Assert-True ((Get-FileHash -LiteralPath $toc.FullName).Hash -eq
        (Get-FileHash -LiteralPath (Join-Path $fixture ('src\' + $toc.Name))).Hash) 'Deployment changed source TOCs.'
    }
  }
  Write-Host 'PASS: voice catalogue always included; legacy flag leaves runtime and source TOCs identical.'

  $retail = Join-Path $fixture 'game\_retail_\Interface\AddOns'
  New-Item -ItemType Directory -Path $retail -Force | Out-Null
  "@{ ForeverBeta = '$($retail.Replace("'", "''"))' }" | Set-Content -LiteralPath $config
  Assert-Fails { & $build -Task Deploy -ConfigPath $config } 'Retail path accepted.'
  Assert-Fails { & $build -Task DeployAddon -ConfigPath $config } 'Addon-only deploy accepted Retail path.'
  Assert-Fails { & $build -Task Deploy -Target Retail -ConfigPath $config } 'Retail target accepted.'
  Assert-True (@(Get-ChildItem -LiteralPath $retail -Force).Count -eq 0) 'Rejected deployment wrote files.'
  $tocPath = Join-Path $fixture 'src\WowVoiceTalkingHead.toc'
  $original = [IO.File]::ReadAllText($tocPath)
  [IO.File]::AppendAllText($tocPath, "`n..\outside.lua`n")
  Assert-Fails { & $build -Task Validate } 'Escaping TOC path accepted.'
  [IO.File]::WriteAllText($tocPath, $original)
  $accidentalOgg = Join-Path $fixture 'soundpack\999999p.ogg'
  'not allowed' | Set-Content -LiteralPath $accidentalOgg
  Assert-Fails { & $build -Task Package } 'Unindexed OGG was allowed in release sources.'
  Remove-Item -LiteralPath $accidentalOgg
  foreach ($audio in @((Join-Path $fixture 'soundpack\179a.ogg'))) {
    $saved = Join-Path $fixture 'temporarily-held-audio.ogg'
    Move-Item -LiteralPath $audio -Destination $saved
    try { Assert-Fails { & $build -Task Package } 'Missing indexed audio was allowed in a complete release.' }
    finally { Move-Item -LiteralPath $saved -Destination $audio }
  }
  Write-Host 'PASS: wrong client/target, escaping TOC paths, unindexed and missing audio are rejected.'
  & $build -Task Package
  $artifacts = Join-Path $fixture 'artifacts'
  $release = Join-Path $artifacts 'WoWVoice'
  $firstZip = @(Get-ChildItem -LiteralPath $release -Filter '*.zip' -File)[0].FullName
  Assert-True ((Split-Path -Leaf $firstZip) -like 'WowVoiceTalkingHead-*.zip') 'Full package is missing the new project name.'
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
    $expected['WowVoiceTalkingHead/' + $relative] = $file.FullName
  }
  foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'soundpack') -File) {
    $expected['WowVoiceSounds/' + $file.Name] = $file.FullName
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
        $fullGuide = $guide
        $sourceGuide = [IO.File]::ReadAllText((Join-Path $fixture 'USER_README.md'))
        Assert-True ($guide.Contains('WowVoiceTalkingHead')) 'Plain-text guide is missing its title.'
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
  Write-Host 'PASS: ZIP contains exactly WowVoiceTalkingHead, the Classic audio folder and plain-text README; runtime hashes match.'
  Write-Host 'PASS: stable shared folder, version replacement, legacy ZIP cleanup and failed-build preservation.'

  $fullZip = $archives[0].FullName
  $fullHash = (Get-FileHash -LiteralPath $fullZip).Hash
  # Exercise an update build with the Classic sound source directory absent.
  foreach ($name in @('soundpack')) {
    $from = [IO.Path]::GetFullPath((Join-Path $fixture $name))
    $held = [IO.Path]::GetFullPath((Join-Path $fixture ($name + '-held')))
    Assert-True ((Split-Path -Parent $from) -eq $fixture -and (Split-Path -Parent $held) -eq $fixture) 'Unsafe fixture rename.'
    Rename-Item -LiteralPath $from -NewName ($name + '-held')
  }
  try {
    # Deploy code with no audio sources; installed audio and its TOCs must not be written.
    "@{ ForeverBeta = '$($addons.Replace("'", "''"))' }" | Set-Content -LiteralPath $config
    $audioBefore = @{}
    foreach ($file in Get-ChildItem -LiteralPath $sounds, $catSounds -File -Recurse) {
      $audioBefore[$file.FullName] = @((Get-FileHash -LiteralPath $file.FullName).Hash, $file.LastWriteTimeUtc.Ticks)
    }
    'before addon-only deploy' | Set-Content -LiteralPath $oldCore
    'stale' | Set-Content -LiteralPath (Join-Path $voice 'obsolete.lua')
    $previousBackups = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'backups') -Directory).FullName
    & $build -Task DeployAddon -Target ForeverBeta -ConfigPath $config
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -File -Recurse) {
      $relative = $file.FullName.Substring($sourcePrefix.Length)
      Assert-True ((Get-FileHash -LiteralPath $file.FullName).Hash -eq
        (Get-FileHash -LiteralPath (Join-Path $voice $relative)).Hash) "Addon-only deployment mismatch: $relative"
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'obsolete.lua'))) 'Addon-only deploy kept stale code.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'LocalDebug.lua'))) 'Normal deploy kept local debug code.'
    Assert-True (Test-Path -LiteralPath (Join-Path $voice 'Comparison.lua')) 'Normal deploy missed comparison code.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'CatQuestComparison.lua'))) 'Normal deploy kept comparison metadata.'
    Assert-True (Test-Path -LiteralPath (Join-Path $voice '.idea\workspace.xml')) 'Addon-only deploy removed IDE state.'
    $audioAfter = @(Get-ChildItem -LiteralPath $sounds, $catSounds -File -Recurse)
    Assert-True ($audioAfter.Count -eq $audioBefore.Count) 'Addon-only deploy changed audio file count.'
    foreach ($file in $audioAfter) {
      Assert-True ($audioBefore.ContainsKey($file.FullName)) 'Addon-only deploy created an audio file.'
      $before = $audioBefore[$file.FullName]
      Assert-True ((Get-FileHash -LiteralPath $file.FullName).Hash -eq $before[0] -and
        $file.LastWriteTimeUtc.Ticks -eq $before[1]) "Addon-only deploy wrote audio: $($file.Name)"
    }
    $addonBackups = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'backups') -Directory |
      Where-Object { $_.FullName -notin $previousBackups })
    Assert-True ($addonBackups.Count -eq 1) 'Expected one addon-only backup.'
    $addonBackup = $addonBackups[0].FullName
    Assert-True ((Get-Content -LiteralPath (Join-Path $addonBackup 'WowVoiceTalkingHead\Core.lua') -Raw).Trim() -eq
      'before addon-only deploy') 'Addon-only backup lost old code.'
    Assert-True (@(Get-ChildItem -LiteralPath $addonBackup -Force).Count -eq 2 -and
      (Test-Path -LiteralPath (Join-Path $addonBackup 'destination.txt'))) 'Addon-only backup contains unexpected files.'
    Write-Host 'PASS: addon-only deploy without audio sources, runtime sync, backup, IDE state and untouched audio contents/timestamps.'

    & $build -Task PackageAddon
    $updateZip = @(Get-ChildItem -LiteralPath $release -Filter '*-addon-only.zip' -File)[0].FullName
    Assert-True ((Split-Path -Leaf $updateZip) -like 'WowVoiceTalkingHead-*-addon-only.zip') 'Addon-only package is missing the new project name.'
    Assert-True ((Get-FileHash -LiteralPath $fullZip).Hash -eq $fullHash) 'Addon update changed full release.'
    $archive = [IO.Compression.ZipFile]::OpenRead($updateZip)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
      $entries = @($archive.Entries | Where-Object { $_.Name })
      $runtimeFiles = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -File -Recurse)
      Assert-True ($entries.Count -eq ($runtimeFiles.Count + 1)) 'Addon update has unexpected entries.'
      foreach ($entry in $entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ($name -eq 'README.txt') {
          $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
          try { $guide = $reader.ReadToEnd() } finally { $reader.Dispose() }
          Assert-True ($guide -eq $fullGuide) 'Full and addon-only archives must share the same guide.'
          Assert-True ($guide.Contains('addon-only') -and $guide.Contains('/reload') -and $guide.Contains('WowVoiceSounds')) 'Addon-only instructions missing.'
          continue
        }
        Assert-True ($name.StartsWith('WowVoiceTalkingHead/') -and $name -notmatch '\.ogg$') 'Audio or unrelated folder in addon update.'
        $stream = $entry.Open()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
        Assert-True ($hash -eq (Get-FileHash -LiteralPath $expected[$name]).Hash) "Update content mismatch: $name"
      }
    } finally { $sha.Dispose(); $archive.Dispose() }
    $updateHash = (Get-FileHash -LiteralPath $updateZip).Hash
    $lock = [IO.File]::Open($updateZip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try { Assert-Fails { & $build -Task PackageAddon } 'Locked addon update was replaced.' }
    finally { $lock.Dispose() }
    Assert-True ((Get-FileHash -LiteralPath $updateZip).Hash -eq $updateHash) 'Failed update damaged previous ZIP.'
    [IO.File]::AppendAllText($tocPath, "`n..\outside.lua`n")
    try { Assert-Fails { & $build -Task PackageAddon } 'Update accepted escaping TOC entry.' }
    finally { [IO.File]::WriteAllText($tocPath, $original) }
    & $build -Task PackageAddon
    Assert-True (-not (Test-Path -LiteralPath $updateZip)) 'Old addon-only version was not removed.'
    $updateZip = @(Get-ChildItem -LiteralPath $release -Filter '*-addon-only.zip' -File)[0].FullName
    $updateHash = (Get-FileHash -LiteralPath $updateZip).Hash
  }
  finally {
    foreach ($name in @('soundpack')) {
      Rename-Item -LiteralPath (Join-Path $fixture ($name + '-held')) -NewName $name
    }
  }
  & $build -Task Package
  Assert-True ((Get-FileHash -LiteralPath $updateZip).Hash -eq $updateHash) 'Full package changed addon-only update.'
  Assert-True (@(Get-ChildItem -LiteralPath $release -Filter '*.zip' -File).Count -eq 2) 'Expected one full release and one update.'
  Assert-True ([IO.Directory]::GetCreationTimeUtc($release) -eq $folderCreated) 'Addon packaging recreated shared folder.'
  Write-Host 'PASS: addon-only build without audio sources, runtime hashes, update guide, validation, failed-build preservation and independent archive replacement.'
  # Exercise environment-based deployment only inside the temporary fixture.
  $previousAddonsEnvironment = $env:WOWVOICE_FOREVER_BETA_ADDONS
  $previousQueueLabEnvironment = $env:WOWVOICE_QUEUE_LAB
  $fixtureConfig = Join-Path $fixture 'config'
  New-Item -ItemType Directory -Path $fixtureConfig -Force | Out-Null
  $fixtureEnvironment = Join-Path $fixtureConfig 'build.env.local.ps1'
  try {
    $env:WOWVOICE_QUEUE_LAB = $null
    $env:WOWVOICE_FOREVER_BETA_ADDONS = $null
    Assert-Fails { & $build -Task DeployAddon } 'Deployment accepted missing environment configuration.'
    $env:WOWVOICE_FOREVER_BETA_ADDONS = $retail
    Assert-Fails { & $build -Task DeployAddon } 'Environment deployment accepted Retail path.'
    $env:WOWVOICE_FOREVER_BETA_ADDONS = $addons
    & $build -Task DeployAddon
    Assert-True ((Get-FileHash -LiteralPath $oldCore).Hash -eq
      (Get-FileHash -LiteralPath (Join-Path $fixture 'src\Core.lua')).Hash) 'Inherited environment deployment failed.'

    $environmentLine = '$env:WOWVOICE_FOREVER_BETA_ADDONS = ' + "'" + $addons.Replace("'", "''") + "'"
    $environmentLine | Set-Content -LiteralPath $fixtureEnvironment -Encoding UTF8
    $env:WOWVOICE_FOREVER_BETA_ADDONS = $retail
    & $build -Task Deploy -LocalDebug
    Assert-True ($env:WOWVOICE_FOREVER_BETA_ADDONS -eq $addons) 'Local file did not override inherited environment.'
    Assert-True (Test-Path -LiteralPath (Join-Path $voice 'VoiceComparison.lua')) 'Environment deployment missed public voice catalogue.'

    # Local opt-in survives ordinary and repeated deployments without a flag.
    '$env:WOWVOICE_QUEUE_LAB = ''1''' | Add-Content -LiteralPath $fixtureEnvironment -Encoding UTF8
    foreach ($iteration in 1..2) {
      & $build -Task DeployAddon
      foreach ($toc in Get-ChildItem -LiteralPath $voice -Filter '*.toc') {
        $entries = @(Get-Content -LiteralPath $toc.FullName | Where-Object { $_ -like 'QueueLab\*' })
        Assert-True (($entries -join ',') -eq 'QueueLab\State.lua,QueueLab\Runtime.lua,QueueLab\Window.lua') 'Local QueueLab default missing or duplicated.'
      }
      Assert-True (Test-Path -LiteralPath (Join-Path $voice 'QueueLab\Window.lua')) 'Local QueueLab default missed harness files.'
    }
    & $build -Task PackageAddon
    $archive = [IO.Compression.ZipFile]::OpenRead($updateZip)
    try {
      Assert-True (@($archive.Entries | Where-Object { $_.FullName -match 'QueueLab|queue-lab' }).Count -eq 0) 'Local QueueLab default leaked into a release archive.'
    } finally { $archive.Dispose() }
    & $build -Task DeployAddon -QueueLab:$false
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'QueueLab'))) 'Explicit QueueLab opt-out did not override local default.'
    & $build -Task DeployAddon -ConfigPath $config
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'QueueLab'))) 'Explicit configuration used the inherited QueueLab preference.'

    # Non-deploy tasks and explicit PSD1 configuration must not execute this file.
    "throw 'Local environment must not be loaded here.'" | Set-Content -LiteralPath $fixtureEnvironment
    & $build -Task Validate
    & $build -Task PackageAddon
    "@{ ForeverBeta = '$($addons.Replace("'", "''"))' }" | Set-Content -LiteralPath $config
    & $build -Task DeployAddon -ConfigPath $config
    Assert-True (@(Get-ChildItem -LiteralPath $retail -Force).Count -eq 0) 'Environment tests wrote to rejected destination.'
  } finally {
    $env:WOWVOICE_FOREVER_BETA_ADDONS = $previousAddonsEnvironment
    $env:WOWVOICE_QUEUE_LAB = $previousQueueLabEnvironment
  }
  Write-Host 'PASS: inherited/local deployment, persistent QueueLab opt-in, explicit opt-out/config bypass, release exclusion and independent non-deploy tasks.'

  # QueueLab is a Git-managed dev module, injected only into explicitly opted-in deployments.
  foreach ($iteration in 1..2) {
    & $build -Task DeployAddon -QueueLab -ConfigPath $config
    foreach ($module in @('State.lua', 'Runtime.lua', 'Window.lua')) {
      Assert-True ((Get-FileHash -LiteralPath (Join-Path $voice ('QueueLab\' + $module))).Hash -eq
        (Get-FileHash -LiteralPath (Join-Path $fixture ('dev\queue-lab\' + $module))).Hash) 'QueueLab module mismatch.'
    }
    foreach ($toc in Get-ChildItem -LiteralPath $voice -Filter '*.toc') {
      $entries = @(Get-Content -LiteralPath $toc.FullName | Where-Object { $_ -like 'QueueLab\*' })
      Assert-True (($entries -join ',') -eq 'QueueLab\State.lua,QueueLab\Runtime.lua,QueueLab\Window.lua') 'QueueLab duplicate or wrong TOC order.'
      Assert-True (-not ([IO.File]::ReadAllText((Join-Path $fixture ('src\' + $toc.Name))).Contains('QueueLab'))) 'QueueLab changed a source TOC.'
    }
  }
  Assert-Fails { & $build -Task PackageAddon -QueueLab } 'Addon packaging accepted QueueLab.'
  Assert-Fails { & $build -Task Package -QueueLab } 'Full packaging accepted QueueLab.'
  & $build -Task PackageAddon
  $archive = [IO.Compression.ZipFile]::OpenRead($updateZip)
  try {
    Assert-True (@($archive.Entries | Where-Object { $_.FullName -match 'QueueLab|queue-lab' }).Count -eq 0) 'QueueLab leaked into release ZIP.'
    foreach ($entry in $archive.Entries | Where-Object { $_.FullName -like '*.toc' }) {
      $reader = [IO.StreamReader]::new($entry.Open())
      try { Assert-True (-not $reader.ReadToEnd().Contains('QueueLab')) 'QueueLab loader leaked into release TOC.' }
      finally { $reader.Dispose() }
    }
  } finally { $archive.Dispose() }
  & $build -Task DeployAddon -ConfigPath $config
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $voice 'QueueLab'))) 'Plain deployment left QueueLab files installed.'
  foreach ($toc in Get-ChildItem -LiteralPath $voice -Filter '*.toc') {
    Assert-True (-not ([IO.File]::ReadAllText($toc.FullName).Contains('QueueLab'))) 'Plain deploy kept QueueLab loader.'
  }
  $contaminatedSource = Join-Path $fixture 'src\QueueLab'
  New-Item -ItemType Directory -Path $contaminatedSource | Out-Null
  try { Assert-Fails { & $build -Task PackageAddon } 'Package validation accepted a dev directory in src.' }
  finally { [IO.Directory]::Delete($contaminatedSource) }
  Write-Host 'PASS: QueueLab opt-in, repeated deploy, source TOC isolation, release exclusion and clean removal.'
}
finally {
  # Only this uniquely named temporary fixture can be recursively removed.
  $resolvedFixture = [IO.Path]::GetFullPath($fixture)
  if ([IO.Path]::GetDirectoryName($resolvedFixture) -ne $tempRoot -or
      [IO.Path]::GetFileName($resolvedFixture) -ne $leaf) { throw 'Unsafe test cleanup path.' }
  Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
