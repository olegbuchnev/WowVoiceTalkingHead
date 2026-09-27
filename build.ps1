[CmdletBinding()]
param(
  [ValidateSet('Validate', 'Test', 'Deploy', 'DeployAddon', 'Package', 'PackageAddon')]
  [string]$Task = 'Validate',
  [ValidateSet('ForeverBeta')]
  [string]$Target = 'ForeverBeta',
  [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$AddonSource = Join-Path $RepoRoot 'src'
$SoundSource = Join-Path $RepoRoot 'soundpack'
$CatSource = Join-Path $RepoRoot 'catvoices'
$ArtifactsRoot = Join-Path $RepoRoot 'artifacts'
$SoundTocs = @('WowVoiceSounds.toc', 'WowVoiceSounds_Mainline.toc')
if (-not $ConfigPath) {
  $ConfigPath = Join-Path $RepoRoot 'config\deploy.targets.local.psd1'
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
  $line = Get-Content -LiteralPath (Join-Path $AddonSource 'WowVoiceTalkingHead.toc') -Encoding UTF8 |
    Where-Object { $_ -match '^##\s+Version:\s*(.+?)\s*$' } | Select-Object -First 1
  if (-not $line) { throw 'Missing addon version.' }
  $version = [regex]::Match($line, '^##\s+Version:\s*(.+?)\s*$').Groups[1].Value
  if ($version -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') { throw 'Unsafe addon version.' }
  return $version
}

function Test-AddonLayout {
  param([switch]$AddonOnly)
  $guideName = 'USER_README.md'
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $guideName) -PathType Leaf)) {
    throw "Missing $guideName for the release archive."
  }
  $foreverDirectory = $CatSource
  $foreverIndex = Join-Path $AddonSource 'ForeverAudio.lua'
  $foreverFiles = @{}
  foreach ($match in [regex]::Matches([IO.File]::ReadAllText($foreverIndex), 'file = "([0-9]+(?:_t)?(?:_[mf])?\.ogg)"')) {
    $name = $match.Groups[1].Value
    $foreverFiles[$name] = $true
    $audio = Join-Path $foreverDirectory $name
    if (-not $AddonOnly -and (-not (Test-Path -LiteralPath $audio -PathType Leaf) -or (Get-Item -LiteralPath $audio).Length -eq 0)) {
      throw "Missing supplemental audio: $name"
    }
  }
  if ($foreverFiles.Count -eq 0) { throw 'Empty Forever audio index.' }
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
  foreach ($match in [regex]::Matches([IO.File]::ReadAllText($foreverIndex), '\["([0-9]+)[ac]"\]')) {
    if ($classicQuests.ContainsKey($match.Groups[1].Value)) {
      throw "Supplement duplicates Classic quest: $($match.Groups[1].Value). Reimport CatVoices."
    }
  }
  $sources = if ($AddonOnly) { @($AddonSource) } else { @($AddonSource, $SoundSource, $CatSource) }
  foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing source: $source" }
    Assert-NoReparseTree $source
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -Force) {
      if ($file.Name -in @('.git', '.idea', 'tests', 'artifacts', 'backups', 'node_modules') -or
          $file.Extension -in @('.bak', '.tmp', '.log')) {
        throw "Non-runtime file in package source: $($file.FullName)"
      }
      if ($file.Extension -eq '.ogg') {
        $isClassic = (Test-PathEquals $file.DirectoryName $SoundSource) -and $classicFiles.ContainsKey($file.Name)
        $isSupplement = (Test-PathEquals $file.DirectoryName $foreverDirectory) -and $foreverFiles.ContainsKey($file.Name)
        if (-not ($isClassic -or $isSupplement)) { throw "Unexpected audio in package source: $($file.FullName)" }
      }
    }
  }
  foreach ($tocName in @('WowVoiceTalkingHead.toc', 'WowVoiceTalkingHead_Mainline.toc', 'WowVoiceTalkingHead_Standard.toc')) {
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
    Write-Host "Validated WowVoice TalkingHead $(Get-AddonVersion) runtime for addon-only update."
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
  $catToc = Join-Path $CatSource 'CatVoices.toc'
  $catLines = @(Get-Content -LiteralPath $catToc -Encoding UTF8)
  if (-not ($catLines -match '^## Interface: 16001\s*$') -or
      @($catLines | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count) {
    throw 'CatVoices TOC must contain Forever metadata only.'
  }
  if (@(Get-ChildItem -LiteralPath $CatSource -Force).Count -ne ($foreverFiles.Count + 2) -or
      -not (Test-Path -LiteralPath (Join-Path $CatSource 'NOTICE.txt') -PathType Leaf)) {
    throw 'catvoices must contain indexed supplemental audio, CatVoices.toc and NOTICE.txt only.'
  }
  Write-Host "Validated WowVoice TalkingHead $(Get-AddonVersion), $($classicFiles.Count) Classic and $($foreverFiles.Count) supplemental recordings."
}

function Resolve-AddOnsDirectory {
  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Missing '$ConfigPath'. Copy config\deploy.targets.example.psd1 and edit it."
  }
  $targets = Import-PowerShellDataFile -LiteralPath $ConfigPath
  $configured = $targets[$Target]
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
  param([switch]$AddonOnly)
  $addons = Resolve-AddOnsDirectory
  $destination = Join-Path $addons 'WowVoiceTalkingHead'
  $sounds = Join-Path $addons 'WowVoiceSounds'
  $catSounds = Join-Path $addons 'CatVoices'
  Assert-DirectChildPath $destination $addons 'WowVoiceTalkingHead'
  Assert-DirectChildPath $sounds $addons 'WowVoiceSounds'
  Assert-DirectChildPath $catSounds $addons 'CatVoices'
  Assert-NoReparseTree $destination
  if (-not $AddonOnly) {
    Assert-NoReparseTree $sounds
    Assert-NoReparseTree $catSounds
  }

  # Back up before the first write. Classic audio is restored from the source
  # library without copying that large library into every backup.
  $backups = Join-Path $RepoRoot 'backups'
  Assert-DirectChildPath $backups $RepoRoot 'backups'
  Assert-NoReparsePath $backups
  $backup = Join-Path $backups ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    Copy-Item -LiteralPath $destination -Destination (Join-Path $backup 'WowVoiceTalkingHead') -Recurse
  }
  if (-not $AddonOnly) {
    if (Test-Path -LiteralPath $catSounds) {
      Copy-Item -LiteralPath $catSounds -Destination (Join-Path $backup 'CatVoices') -Recurse
    }
    New-Item -ItemType Directory -Path (Join-Path $backup 'WowVoiceSounds') | Out-Null
    foreach ($name in $SoundTocs) {
      $file = Join-Path $sounds $name
      if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination (Join-Path $backup 'WowVoiceSounds') }
    }
  }
  $addons | Set-Content -LiteralPath (Join-Path $backup 'destination.txt') -Encoding UTF8
  Write-Host "Backup: $backup"

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
  if ($AddonOnly) {
    Write-Host "Deployed WowVoice TalkingHead to ${Target}: $addons"
    Write-Host 'Sound libraries unchanged. Use /reload in game to load the updated addon.'
    return
  }
  New-Item -ItemType Directory -Path $sounds -Force | Out-Null
  foreach ($file in Get-ChildItem -LiteralPath $SoundSource -File) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $sounds $file.Name) -Force
  }
  New-Item -ItemType Directory -Path $catSounds -Force | Out-Null
  foreach ($file in Get-ChildItem -LiteralPath $CatSource -File) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $catSounds $file.Name) -Force
  }
  Write-Host "Deployed WowVoice TalkingHead, WowVoiceSounds and CatVoices to ${Target}: $addons"
  Write-Host 'Fully restart the game to load newly added audio.'
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
    Copy-Item -LiteralPath $AddonSource -Destination (Join-Path $stage 'WowVoiceTalkingHead') -Recurse
    $packagePaths = @((Join-Path $stage 'WowVoiceTalkingHead'))
    if (-not $AddonOnly) {
      Copy-Item -LiteralPath $SoundSource -Destination (Join-Path $stage 'WowVoiceSounds') -Recurse
      Copy-Item -LiteralPath $CatSource -Destination (Join-Path $stage 'CatVoices') -Recurse
      $packagePaths += @((Join-Path $stage 'WowVoiceSounds'), (Join-Path $stage 'CatVoices'))
    }
    # Convert the guide's Markdown to plain text for opening in Notepad.
    $guide = [IO.File]::ReadAllText((Join-Path $RepoRoot 'USER_README.md'))
    $guide = $guide -replace '(?m)^\s*```[^\r\n]*\r?\n', ''
    $guide = $guide -replace '(?m)^#{1,6}\s+', ''
    $guide = $guide -replace '\[([^\]]+)\]\(([^)]+)\)', '$1 ($2)'
    $guide = $guide.Replace('**', '').Replace('`', '')
    $guide = $guide -replace '\r?\n', "`r`n"
    [IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $guide, [Text.UTF8Encoding]::new($true))
    $suffix = if ($AddonOnly) { '-addon-only' } else { '' }
    $zipName = 'WowVoiceTalkingHead-' + (Get-AddonVersion) + $suffix + '.zip'
    $pendingZip = Join-Path $stage $zipName
    $zip = Join-Path $release $zipName
    $packagePaths += (Join-Path $stage 'README.txt')
    Compress-Archive -LiteralPath $packagePaths -DestinationPath $pendingZip
    # Publish only a completed ZIP; preserve the previous release on build failure.
    if (Test-Path -LiteralPath $zip -PathType Leaf) {
      [IO.File]::Replace($pendingZip, $zip, [NullString]::Value)
    } else {
      Move-Item -LiteralPath $pendingZip -Destination $zip
    }
    foreach ($directory in @($ArtifactsRoot, $release)) {
      foreach ($old in Get-ChildItem -LiteralPath $directory -Filter '*.zip' -File) {
        $sameKind = ($old.Name -like '*-addon-only.zip') -eq [bool]$AddonOnly
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
  }
  finally { Pop-Location; $env:Path = $previousPath }
}

Test-AddonLayout -AddonOnly:($Task -in @('PackageAddon', 'DeployAddon'))
switch ($Task) {
  'Validate' { }
  'Test' { Invoke-Tests }
  'Deploy' { Invoke-Deploy }
  'DeployAddon' { Invoke-Deploy -AddonOnly }
  'Package' { Invoke-Package }
  'PackageAddon' { Invoke-Package -AddonOnly }
}
