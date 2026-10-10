[CmdletBinding()]
param(
  [ValidatePattern('^\d+\.\d+\.\d+-forever$')]
  [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repo 'artifacts\site-preview'
$downloads = Join-Path $output 'downloads'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$leaf = 'wowvoice-preview-' + [guid]::NewGuid().ToString('N')
$fixture = Join-Path $tempRoot $leaf
$utf8 = [Text.UTF8Encoding]::new($false)
$node = (Get-Command node -ErrorAction Stop).Source

# Run the real packager in an isolated workspace, away from published/pCloud ZIPs.
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
  foreach ($name in @('build.ps1', 'src')) {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $fixture -Recurse
  }
  $tocPath = Join-Path $fixture 'src\TalkingHeadRu.toc'
  $releaseVersion = if ($Version) { $Version } else {
    [regex]::Match([IO.File]::ReadAllText($tocPath), '(?m)^## Version:\s*(\S+)').Groups[1].Value
  }
  $previewVersion = $releaseVersion + '-preview'
  foreach ($toc in Get-ChildItem -LiteralPath (Join-Path $fixture 'src') -Filter '*.toc') {
    $text = [IO.File]::ReadAllText($toc.FullName)
    $text = [regex]::Replace($text, '(?m)^## Version:[^\r\n]*', "## Version: $previewVersion")
    [IO.File]::WriteAllText($toc.FullName, $text, $utf8)
  }
  & (Join-Path $fixture 'build.ps1') -Task PackageAddon
  New-Item -ItemType Directory -Path $downloads -Force | Out-Null
  $addon = "TalkingHeadRu-$previewVersion.zip"
  Copy-Item -LiteralPath (Join-Path $fixture "artifacts\WoWVoice\$addon") -Destination (Join-Path $downloads $addon) -Force
  $cat = [regex]::Match([IO.File]::ReadAllText((Join-Path $fixture 'src\CatQuestAudio.lua')), 'sourceVersion\s*=\s*"([^"]+)"').Groups[1].Value
  if (-not $cat) { throw 'Missing CatQuest source version for preview.' }
  $wayfarerCore = [regex]::Match([IO.File]::ReadAllText((Join-Path $fixture 'src\WayfarerSource.lua')), 'AUDITED_CORE_VERSION\s*=\s*"([^"]+)"').Groups[1].Value
  $wayfarerPacks = @([regex]::Matches([IO.File]::ReadAllText((Join-Path $fixture 'src\WayfarerAudio.lua')),
    '\["Wayfarer_Voices_(?:Alliance|Horde|Shared)"\]\s*=\s*\{version="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (-not $wayfarerCore -or -not $wayfarerPacks.Count) { throw 'Missing Wayfarer compatibility versions for preview.' }
  $manifest = @{ version = $previewVersion; releaseVersion = $releaseVersion; addon = $addon; catQuestVersion = $cat
    wayfarer = @{ core = $wayfarerCore; packs = $wayfarerPacks } }
  [IO.File]::WriteAllText((Join-Path $output 'preview.json'), ($manifest | ConvertTo-Json), $utf8)
  & $node (Join-Path $repo 'tools\build-site.mjs') --preview
  if ($LASTEXITCODE -ne 0) { throw 'Preview site build failed.' }
  Write-Host "Open: $(Join-Path $output 'index.html')"
}
finally {
  $resolved = [IO.Path]::GetFullPath($fixture)
  if ([IO.Path]::GetDirectoryName($resolved) -ne $tempRoot -or [IO.Path]::GetFileName($resolved) -ne $leaf) {
    throw 'Unsafe preview cleanup path.'
  }
  $links = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
  if ($links.Count) { throw 'Refusing to remove a preview workspace with linked entries.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
