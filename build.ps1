[CmdletBinding()]
param(
  [ValidateSet('Validate', 'Test', 'Deploy', 'Package')]
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
  $line = Get-Content -LiteralPath (Join-Path $AddonSource 'WowVoice.toc') -Encoding UTF8 |
    Where-Object { $_ -match '^##\s+Version:\s*(.+?)\s*$' } | Select-Object -First 1
  if (-not $line) { throw 'Missing addon version.' }
  $version = [regex]::Match($line, '^##\s+Version:\s*(.+?)\s*$').Groups[1].Value
  if ($version -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') { throw 'Unsafe addon version.' }
  return $version
}

function Test-AddonLayout {
  if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'USER_README.md') -PathType Leaf)) {
    throw 'Missing USER_README.md for the release archive.'
  }
  foreach ($source in @($AddonSource, $SoundSource)) {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing source: $source" }
    Assert-NoReparseTree $source
    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -Force) {
      if ($file.Name -in @('.git', '.idea', 'tests', 'artifacts', 'backups', 'node_modules') -or
          $file.Extension -in @('.ogg', '.bak', '.tmp', '.log')) {
        throw "Non-runtime file in package source: $($file.FullName)"
      }
    }
  }
  foreach ($tocName in @('WowVoice.toc', 'WowVoice_Mainline.toc', 'WowVoice_Standard.toc')) {
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
  $soundFiles = @(Get-ChildItem -LiteralPath $SoundSource -Force)
  if ($soundFiles.Count -ne 2) { throw 'soundpack must contain exactly the two Forever TOCs.' }
  foreach ($name in $SoundTocs) {
    $toc = Join-Path $SoundSource $name
    if (-not (Test-Path -LiteralPath $toc -PathType Leaf)) { throw "Missing sound TOC: $name" }
    $lines = @(Get-Content -LiteralPath $toc -Encoding UTF8)
    if (-not ($lines -match '^## Interface: 16001\s*$')) { throw "Wrong sound Interface: $name" }
    if (@($lines | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count) {
      throw "Sound TOC must contain metadata only: $name"
    }
  }
  Write-Host "Validated WowVoice $(Get-AddonVersion) and two Forever sound TOCs."
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
  $addons = Resolve-AddOnsDirectory
  $destination = Join-Path $addons 'WowVoice'
  $sounds = Join-Path $addons 'WowVoiceSounds'
  Assert-DirectChildPath $destination $addons 'WowVoice'
  Assert-DirectChildPath $sounds $addons 'WowVoiceSounds'
  Assert-NoReparseTree $destination
  Assert-NoReparsePath $sounds
  foreach ($name in $SoundTocs) { Assert-NoReparsePath (Join-Path $sounds $name) }

  # Back up before the first write; OGG files are never copied or synchronized.
  $backups = Join-Path $RepoRoot 'backups'
  Assert-DirectChildPath $backups $RepoRoot 'backups'
  Assert-NoReparsePath $backups
  $backup = Join-Path $backups ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  if (Test-Path -LiteralPath $destination) {
    Copy-Item -LiteralPath $destination -Destination (Join-Path $backup 'WowVoice') -Recurse
  }
  New-Item -ItemType Directory -Path (Join-Path $backup 'WowVoiceSounds') | Out-Null
  foreach ($name in $SoundTocs) {
    $file = Join-Path $sounds $name
    if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination (Join-Path $backup 'WowVoiceSounds') }
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
  New-Item -ItemType Directory -Path $sounds -Force | Out-Null
  foreach ($name in $SoundTocs) {
    Copy-Item -LiteralPath (Join-Path $SoundSource $name) -Destination (Join-Path $sounds $name) -Force
  }
  Write-Host "Deployed WowVoice and two sound TOCs to ${Target}: $addons"
  Write-Host 'Existing OGG files were left in place. Reload the game UI to load the changes.'
}

function Invoke-Package {
  Remove-CheckedDirectory $ArtifactsRoot $RepoRoot 'artifacts'
  New-Item -ItemType Directory -Path $ArtifactsRoot | Out-Null
  $stage = Join-Path $ArtifactsRoot 'package-stage'
  New-Item -ItemType Directory -Path $stage | Out-Null
  try {
    Copy-Item -LiteralPath $AddonSource -Destination (Join-Path $stage 'WowVoice') -Recurse
    Copy-Item -LiteralPath $SoundSource -Destination (Join-Path $stage 'WowVoiceSounds') -Recurse
    # Convert the guide's Markdown to plain text for opening in Notepad.
    $guide = [IO.File]::ReadAllText((Join-Path $RepoRoot 'USER_README.md'))
    $guide = $guide -replace '(?m)^\s*```[^\r\n]*\r?\n', ''
    $guide = $guide -replace '(?m)^#{1,6}\s+', ''
    $guide = $guide -replace '\[([^\]]+)\]\(([^)]+)\)', '$1 ($2)'
    $guide = $guide.Replace('**', '').Replace('`', '')
    $guide = $guide -replace '\r?\n', "`r`n"
    [IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $guide, [Text.UTF8Encoding]::new($true))
    $zip = Join-Path $ArtifactsRoot ('WowVoice-' + (Get-AddonVersion) + '.zip')
    Compress-Archive -LiteralPath @((Join-Path $stage 'WowVoice'), (Join-Path $stage 'WowVoiceSounds'), (Join-Path $stage 'README.txt')) -DestinationPath $zip
    Write-Host "Package created: $zip"
  }
  finally { Remove-CheckedDirectory $stage $ArtifactsRoot 'package-stage' }
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

Test-AddonLayout
switch ($Task) {
  'Validate' { }
  'Test' { Invoke-Tests }
  'Deploy' { Invoke-Deploy }
  'Package' { Invoke-Package }
}
