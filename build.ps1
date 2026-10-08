[CmdletBinding()]
param(
  [ValidateSet('Validate', 'Test', 'DeployAddon', 'Package', 'PackageAddon')]
  [string]$Task = 'Validate',
  [ValidateSet('ForeverBeta')]
  [string]$Target = 'ForeverBeta',
  [string]$ConfigPath,
  [switch]$LocalDebug, # Backward-compatible no-op: the voice catalogue now ships to everyone.
  [switch]$QueueLab # Development-only simulated quest queue, never packaged.
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$AddonSource = Join-Path $RepoRoot 'src'
$SoundSource = Join-Path $RepoRoot 'soundpack'
$LegacyDebugFiles = @('CatQuestComparison.lua', 'LocalDebug.lua')
$ArtifactsRoot = Join-Path $RepoRoot 'artifacts'
$SoundTocs = @('WowVoiceSounds.toc', 'WowVoiceSounds_Mainline.toc')
$QueueLabModules = @('State.lua', 'Runtime.lua', 'Window.lua', 'Commands.lua')
$QueueLabExplicit = $PSBoundParameters.ContainsKey('QueueLab')
if ($QueueLab -and $Task -ne 'DeployAddon') {
  throw '-QueueLab is allowed only for local DeployAddon, never release packaging.'
}
if ($LocalDebug -and $Task -ne 'DeployAddon') {
  throw '-LocalDebug is a legacy deployment flag. The voice catalogue is included in all builds.'
}

function Test-PathEquals {
  param([string]$Left, [string]$Right)
  return [string]::Equals($Left.TrimEnd('\', '/'), $Right.TrimEnd('\', '/'),
    [StringComparison]::OrdinalIgnoreCase)
}

function Assert-DirectChildPath {
  param([string]$Path, [string]$Parent, [string]$ExpectedLeaf)
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-PathEquals ([IO.Path]::GetDirectoryName($full)) ([IO.Path]::GetFullPath($Parent))) -or
      -not (Test-PathEquals ([IO.Path]::GetFileName($full)) $ExpectedLeaf)) {
    throw "Unsafe path '$full'; expected direct child '$ExpectedLeaf' of '$Parent'."
  }
}

function Assert-NoReparsePath {
  param([string]$Path)
  $current = [IO.Path]::GetFullPath($Path)
  while ($current) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing linked/junction path: $current"
      }
    }
    $current = [IO.Path]::GetDirectoryName($current)
  }
}

function Assert-NoReparseTree {
  param([string]$Path)
  Assert-NoReparsePath $Path
  if (Test-Path -LiteralPath $Path -PathType Container) {
    foreach ($item in Get-ChildItem -LiteralPath $Path -Force) {
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing linked/junction entry: $($item.FullName)"
      }
      if ($item.PSIsContainer) { Assert-NoReparseTree $item.FullName }
    }
  }
}

function Remove-CheckedDirectory {
  param([string]$Path, [string]$Parent, [string]$ExpectedLeaf)
  Assert-DirectChildPath $Path $Parent $ExpectedLeaf
  Assert-NoReparseTree $Path
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Get-AddonVersion {
  $line = Get-Content -LiteralPath (Join-Path $AddonSource 'TalkingHeadRu.toc') -Encoding UTF8 |
    Where-Object { $_ -match '^##\s+Version:\s*(.+?)\s*$' } | Select-Object -First 1
  if (-not $line) { throw 'Missing addon version.' }
  $version = [regex]::Match($line, '^##\s+Version:\s*(.+?)\s*$').Groups[1].Value
  if ($version -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') { throw 'Unsafe addon version.' }
  return $version
}

function Test-AddonLayout {
  param([switch]$AddonOnly)
  $classicFiles = @{}
  $classicQuests = @{}
  foreach ($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $AddonSource 'Durations.lua')), '\["([0-9]+[apc])"\]')) {
    $name = $match.Groups[1].Value + '.ogg'
    $classicFiles[$name] = $true
    $classicQuests[($match.Groups[1].Value -replace '[apc]$', '')] = $true
    $audio = Join-Path $SoundSource $name
    if (-not $AddonOnly -and (-not (Test-Path -LiteralPath $audio -PathType Leaf) -or (Get-Item -LiteralPath $audio).Length -eq 0)) {
      throw "Missing Classic audio: $name. Run tools/import-classic-audio.js with the extracted WowVoiceSounds directory."
    }
  }
  if ($classicFiles.Count -eq 0) { throw 'Empty Classic audio index.' }
  $runtimeSilence = Join-Path $AddonSource 'Media\silence.ogg'
  if (-not (Test-Path -LiteralPath $runtimeSilence -PathType Leaf) -or (Get-Item -LiteralPath $runtimeSilence).Length -eq 0) {
    throw 'Missing service audio: TalkingHeadRu/Media/silence.ogg'
  }
  $sources = if ($AddonOnly) { @($AddonSource) } else { @($AddonSource, $SoundSource) }
  foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing source: $source" }
    Assert-NoReparseTree $source
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -Force) {
      if ($file.Name -in (@('.git', '.idea', 'tests', 'dev', 'artifacts', 'backups', 'node_modules', 'QueueLab') + $LegacyDebugFiles) -or
          $file.Extension -in @('.bak', '.tmp', '.log')) {
        throw "Non-runtime file in package source: $($file.FullName)"
      }
      if ($file.Extension -eq '.ogg') {
        $isClassic = (Test-PathEquals $file.DirectoryName $SoundSource) -and $classicFiles.ContainsKey($file.Name)
        $isServiceAudio = Test-PathEquals $file.FullName $runtimeSilence
        if (-not $isClassic -and -not $isServiceAudio) { throw "Unexpected audio in package source: $($file.FullName)" }
      }
    }
  }
  foreach ($tocName in @('TalkingHeadRu.toc', 'TalkingHeadRu_Mainline.toc', 'TalkingHeadRu_Standard.toc')) {
    $toc = Join-Path $AddonSource $tocName
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Missing TOC: $toc" }
    $lines = @(Get-Content -LiteralPath $toc -Encoding UTF8)
    if (-not ($lines -match '^## Interface: 16001\s*$')) { throw "Wrong Forever Interface: $toc" }
    $entries = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($entries.Count -eq 0) { throw "Empty TOC: $toc" }
    foreach ($entry in $entries) {
      if ([IO.Path]::IsPathRooted($entry) -or $entry -match '(^|[\\/])\.\.([\\/]|$)' -or $entry.Contains(':')) {
        throw "Unsafe TOC entry: $entry"
      }
      if (-not (Test-Path -LiteralPath (Join-Path $AddonSource $entry) -PathType Leaf)) {
        throw "Missing TOC entry: $entry"
      }
    }
  }
  if ($AddonOnly) {
    Write-Host "Validated TalkingHead Ru $(Get-AddonVersion) runtime for addon-only update."
    return
  }
  $soundFiles = @(Get-ChildItem -LiteralPath $SoundSource -Force)
  if ($soundFiles.Count -ne ($classicFiles.Count + 2)) { throw 'soundpack must contain indexed Classic audio and two Forever TOCs only.' }
  foreach ($name in $SoundTocs) {
    $toc = Join-Path $SoundSource $name
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Missing sound TOC: $name" }
    $lines = @(Get-Content -LiteralPath $toc -Encoding UTF8)
    if (-not ($lines -match '^## Interface: 16001\s*$')) { throw "Wrong sound Interface: $name" }
    if (@($lines | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count) {
      throw "Sound TOC must contain metadata only: $name"
    }
  }
  Write-Host "Validated TalkingHead Ru $(Get-AddonVersion) and $($classicFiles.Count) Classic recordings."
}

function Resolve-AddOnsDirectory {
  if ($ConfigPath) {
    # Explicit configuration remains available for isolated tests and automation.
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
      throw "Missing deployment configuration: $ConfigPath"
    }
    $targets = Import-PowerShellDataFile -LiteralPath $ConfigPath
    $configured = $targets[$Target]
  } else {
    $localEnvironment = Join-Path $RepoRoot 'config\build.env.local.ps1'
    if (Test-Path -LiteralPath $localEnvironment -PathType Leaf) {
      . $localEnvironment
    }
    $configured = $env:WOWVOICE_FOREVER_BETA_ADDONS
    if ([string]::IsNullOrWhiteSpace($configured)) {
      throw 'Set WOWVOICE_FOREVER_BETA_ADDONS. Copy config\build.env.example.ps1 to config\build.env.local.ps1 and edit the path.'
    }
  }
  if (-not $configured -or -not (Test-Path -LiteralPath $configured -PathType Container)) {
    throw "Missing or invalid AddOns directory for $Target."
  }
  Assert-NoReparsePath $configured
  $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $configured).Path).TrimEnd('\', '/')
  $interface = [IO.Path]::GetDirectoryName($resolved)
  $client = [IO.Path]::GetDirectoryName($interface)
  if (-not (Test-PathEquals ([IO.Path]::GetFileName($resolved)) 'AddOns') -or
      -not (Test-PathEquals ([IO.Path]::GetFileName($interface)) 'Interface') -or
      -not (Test-PathEquals ([IO.Path]::GetFileName($client)) '_classic_beta_')) {
    throw "ForeverBeta destination must end in _classic_beta_\Interface\AddOns: $resolved"
  }
  return $resolved
}

function Invoke-Deploy {
  $addons = Resolve-AddOnsDirectory
  # Local defaults are opt-in and apply only to environment-based deployment.
  # An explicit switch (including -QueueLab:$false) always wins.
  $enableQueueLab = $QueueLab -or (-not $QueueLabExplicit -and -not $ConfigPath -and
    $env:WOWVOICE_QUEUE_LAB -eq '1')
  $labSource = Join-Path $RepoRoot 'dev\queue-lab'
  if ($enableQueueLab) {
    Assert-NoReparseTree $labSource
    foreach ($module in $QueueLabModules) {
      if (-not (Test-Path -LiteralPath (Join-Path $labSource $module) -PathType Leaf)) {
        throw "Missing QueueLab module: $module"
      }
    }
  }
  $destination = Join-Path $addons 'TalkingHeadRu'
  $legacyDestination = Join-Path $addons 'WowVoiceTalkingHead'
  Assert-DirectChildPath $destination $addons 'TalkingHeadRu'
  Assert-DirectChildPath $legacyDestination $addons 'WowVoiceTalkingHead'
  Assert-NoReparseTree $destination
  Assert-NoReparseTree $legacyDestination

  # Back up before the first write. Deployment never modifies sound libraries.
  $backups = Join-Path $RepoRoot 'backups'
  Assert-DirectChildPath $backups $RepoRoot 'backups'
  Assert-NoReparsePath $backups
  $backup = Join-Path $backups ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    Copy-Item -LiteralPath $destination -Destination (Join-Path $backup 'TalkingHeadRu') -Recurse
  }
  if (Test-Path -LiteralPath $legacyDestination) {
    Copy-Item -LiteralPath $legacyDestination -Destination (Join-Path $backup 'WowVoiceTalkingHead') -Recurse
  }
  $addons | Set-Content -LiteralPath (Join-Path $backup 'destination.txt') -Encoding UTF8
  Write-Host "Backup: $backup"

  # Retire the previous addon after backup; SavedVariables in WTF stay untouched.
  Remove-CheckedDirectory $legacyDestination $addons 'WowVoiceTalkingHead'

  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  $sourcePrefix = $AddonSource.TrimEnd('\', '/') + '\'
  $destinationPrefix = $destination.TrimEnd('\', '/') + '\'
  $expected = @{}
  foreach ($file in Get-ChildItem -LiteralPath $AddonSource -File -Recurse -Force) {
    $relative = $file.FullName.Substring($sourcePrefix.Length)
    $expected[$relative] = $true
    $deployed = Join-Path $destination $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($deployed)) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $deployed -Force
  }
  foreach ($file in Get-ChildItem -LiteralPath $destination -File -Recurse -Force) {
    $relative = $file.FullName.Substring($destinationPrefix.Length)
    # Leave any existing IDE workspace state alone; it is not a runtime source.
    if ($relative -match '^\.idea([\\/]|$)') { continue }
    if (-not $expected.ContainsKey($relative)) { Remove-Item -LiteralPath $file.FullName -Force }
  }
  foreach ($dir in (Get-ChildItem -LiteralPath $destination -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)) {
    if (@(Get-ChildItem -LiteralPath $dir.FullName -Force).Count -eq 0) {
      [IO.Directory]::Delete($dir.FullName)
    }
  }
  if ($enableQueueLab) {
    $labDestination = Join-Path $destination 'QueueLab'
    New-Item -ItemType Directory -Path $labDestination -Force | Out-Null
    foreach ($module in $QueueLabModules) {
      $sourceModule = Join-Path $labSource $module
      $targetModule = Join-Path $labDestination $module
      Copy-Item -LiteralPath $sourceModule -Destination $targetModule
      if ((Get-FileHash -LiteralPath $sourceModule).Hash -ne (Get-FileHash -LiteralPath $targetModule).Hash) {
        throw "QueueLab deployment mismatch: $module"
      }
    }
    $entries = ($QueueLabModules | ForEach-Object { 'QueueLab\' + $_ }) -join "`r`n"
    foreach ($toc in Get-ChildItem -LiteralPath $destination -Filter 'TalkingHeadRu*.toc' -File) {
      $contents = [IO.File]::ReadAllText($toc.FullName).TrimEnd() + "`r`n" + $entries + "`r`n"
      [IO.File]::WriteAllText($toc.FullName, $contents, [Text.UTF8Encoding]::new($false))
    }
    Write-Host 'QueueLab enabled locally: /tt after /reload. Source TOCs and release packages unchanged.'
  }
  Write-Host "Deployed TalkingHead Ru to ${Target}: $addons"
  Write-Host 'Sound libraries unchanged. Fully restart the game after switching to the TalkingHeadRu folder.'
}

function Invoke-Package {
  param([switch]$AddonOnly)
  Assert-DirectChildPath $ArtifactsRoot $RepoRoot 'artifacts'
  Assert-NoReparseTree $ArtifactsRoot
  New-Item -ItemType Directory -Path $ArtifactsRoot -Force | Out-Null
  # Keep this directory in place so cloud sync can retain its shared link.
  $release = Join-Path $ArtifactsRoot 'WoWVoice'
  Assert-DirectChildPath $release $ArtifactsRoot 'WoWVoice'
  New-Item -ItemType Directory -Path $release -Force | Out-Null
  $stageName = 'package-stage-' + [guid]::NewGuid().ToString('N')
  $stage = Join-Path $ArtifactsRoot $stageName
  New-Item -ItemType Directory -Path $stage | Out-Null
  try {
    Copy-Item -LiteralPath $AddonSource -Destination (Join-Path $stage 'TalkingHeadRu') -Recurse
    $packagePaths = @((Join-Path $stage 'TalkingHeadRu'))
    if (-not $AddonOnly) {
      Copy-Item -LiteralPath $SoundSource -Destination (Join-Path $stage 'WowVoiceSounds') -Recurse
      $packagePaths += (Join-Path $stage 'WowVoiceSounds')
    }
    $suffix = if ($AddonOnly) { '' } else { '-full' }
    $zipName = 'TalkingHeadRu-' + (Get-AddonVersion) + $suffix + '.zip'
    $pendingZip = Join-Path $stage $zipName
    $zip = Join-Path $release $zipName
    Compress-Archive -LiteralPath $packagePaths -DestinationPath $pendingZip
    # Publish only a completed ZIP; preserve the previous release on build failure.
    if (Test-Path -LiteralPath $zip -PathType Leaf) {
      [IO.File]::Replace($pendingZip, $zip, [NullString]::Value)
    } else {
      Move-Item -LiteralPath $pendingZip -Destination $zip
    }
    foreach ($directory in @($ArtifactsRoot, $release)) {
      foreach ($old in Get-ChildItem -LiteralPath $directory -Filter '*.zip' -File) {
        $oldKind = if ($old.Name -like 'TalkingHeadRu-*-full.zip') { 'full' } elseif ($old.Name -like 'TalkingHeadRu-*.zip' -or $old.Name -like '*-addon-only.zip') { 'addon' } elseif ($old.Name -like '*-lite.zip') { 'lite' } else { 'full' }
        $kind = if ($AddonOnly) { 'addon' } else { 'full' }
        $sameKind = $oldKind -eq $kind
        if ($sameKind -and -not (Test-PathEquals $old.FullName $zip)) {
          Remove-Item -LiteralPath $old.FullName
        }
      }
    }
    Write-Host "Package created: $zip"
  }
  finally { Remove-CheckedDirectory $stage $ArtifactsRoot $stageName }
}

function Resolve-NpxPath {
  $pathCommand = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
  if ($pathCommand) { return $pathCommand.Source }

  $candidates = @()
  if ($env:NODE_EXE) {
    $candidates += Join-Path `
      ([System.IO.Path]::GetDirectoryName($env:NODE_EXE)) `
      'npx.cmd'
  }

  if ($env:LOCALAPPDATA) {
    $jetBrainsRoot = Join-Path $env:LOCALAPPDATA 'JetBrains'
    if (Test-Path -LiteralPath $jetBrainsRoot) {
      $patterns = @(
        'IntelliJIdea*\acp-agents\.runtimes\node\*\npx.cmd',
        'IntelliJIdea*\aia\agents\.runtimes\node\*\npx.cmd'
      )
      foreach ($pattern in $patterns) {
        $candidates += Get-ChildItem `
          -Path (Join-Path $jetBrainsRoot $pattern) `
          -File `
          -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -ExpandProperty FullName
      }
    }
    $candidates += Join-Path $env:LOCALAPPDATA 'Programs\nodejs\npx.cmd'
  }

  if ($env:ProgramFiles) {
    $candidates += Join-Path $env:ProgramFiles 'nodejs\npx.cmd'
  }
  if (${env:ProgramFiles(x86)}) {
    $candidates += Join-Path ${env:ProgramFiles(x86)} 'nodejs\npx.cmd'
  }

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }
  return $null
}



function Invoke-Tests {
  $npx = Resolve-NpxPath
  if (-not $npx) { throw 'Test requires Node.js/npm (PATH, NODE_EXE or IntelliJ runtime).' }
  $nodeDir = Split-Path -Parent $npx
  $previousPath = $env:Path
  $env:Path = $nodeDir + [IO.Path]::PathSeparator + $previousPath
  Push-Location $RepoRoot
  try {
    & (Join-Path $nodeDir 'npm.cmd') ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    & (Join-Path $nodeDir 'node.exe') (Join-Path $RepoRoot 'tests\run.js')
    if ($LASTEXITCODE -ne 0) { throw 'Lua validation/tests failed.' }
    & (Join-Path $RepoRoot 'tests\pipeline.ps1')
    & (Join-Path $RepoRoot 'tests\release-stats.ps1')
  }
  finally { Pop-Location; $env:Path = $previousPath }
}

Test-AddonLayout -AddonOnly:($Task -in @('PackageAddon', 'DeployAddon'))
switch ($Task) {
  'Validate' { }
  'Test' { Invoke-Tests }
  'DeployAddon' { Invoke-Deploy }
  'Package' { Invoke-Package }
  'PackageAddon' { Invoke-Package -AddonOnly }
}
