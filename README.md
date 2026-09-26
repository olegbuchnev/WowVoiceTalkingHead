# WowVoice — Forever Beta

This standalone repository keeps the modified WowVoice development sources
outside the live World of Warcraft installation. Runtime addon files live under
`src/`; tests and build tools stay outside that directory and are never deployed.
The runtime code is based on the Midnight version, while `Index.lua`,
`Durations.lua` and the OGG audio come from the Russian Classic sound pack.
This build targets **WoW Forever Beta, Interface 16001**.

For installation and in-game usage, see the [user guide in Russian](USER_README.md).
The release archive includes that guide as `README.md`.

The proposed license is deferred. Its [English draft](docs/internal/license-drafts/LICENSE)
and [Russian translation](docs/internal/license-drafts/LICENSE.ru.md) are retained
for future review, are not adopted for the current release and are excluded
from release archives.

## Layout

```text
src/                             Runtime files copied to AddOns/WowVoice
soundpack/                       Two Forever TOC files for WowVoiceSounds
tests/                           Lua tests with WoW API mocks and pipeline checks
config/deploy.targets.local.psd1  Local Forever Beta path (gitignored)
build.ps1 / build.cmd             Validate, test, deploy and package pipeline
USER_README.md                   Russian user guide; packaged as README.md
artifacts/                       Release ZIP archive (gitignored)
backups/                         Backups created before deployment (gitignored)
```

Edit `src/`, then run Deploy. The installed `AddOns\WowVoice` directory is a
deployment destination, not the project's source directory. OGG audio files are
stored separately and are not included in this repository or its release archive.

## Commands

Run from the repository root in Windows PowerShell or Command Prompt:

### Validate

```shell
.\build.cmd -Task Validate
```

### Test

```shell
.\build.cmd -Task Test
```

### Deploy to Forever Beta

```shell
.\build.cmd -Task Deploy -Target ForeverBeta
```

### Build release package

```shell
.\build.cmd -Task Package
```

Package removes all previous contents of `artifacts/` before creating the new
release archive.

IntelliJ IDEA shows a Run/Play gutter icon for each command block when
**Detect commands that can be run right from Markdown files** is enabled in
**Languages & Frameworks | Markdown**. Use the repository root as the working
directory.

Deploy and Package run Validate first. Test runs separately. Validate, Deploy
and Package require only Windows PowerShell 5.1. Test locates Node.js/npm through
PATH, `NODE_EXE`, IntelliJ's local Node runtimes or standard installation
directories. It runs `npm ci` to install the dependencies pinned in
`package-lock.json`; an internet connection is required if they are not cached.

The tests check Lua 5.1 syntax and behavior with WoW API mocks: quest events,
playback and Dialog restoration, the quest journal, portraits, item speakers,
persistence across reloads, options and block scrolling. Pipeline checks use an
isolated temporary directory without deploying to the game. These checks do not
replace API and visual verification in the Forever client.

## Appearance

The options page offers three appearance presets: Retail (selected by default),
Classic and EllesmereUI. Installing EllesmereUI does not change the default;
an explicitly saved preset is preserved. All three work without additional addons. Switching
presets updates the panel without interrupting playback.

The EllesmereUI preset reads the installed BlizzardSkin module's third-party
window theme: its textured background or the global Modern color and opacity.
Changes are detected while the panel is visible. If the module, texture or valid
settings are unavailable, the preset keeps WowVoice's built-in dark background.
Only the background is inherited; layout and quest fonts remain owned by WowVoice.

Retail follows Blizzard's talking-head composition: a soft translucent background,
a gold portrait frame, the speaker's name above the text on the right, and a close
button that stops playback. It uses the original TalkingHeads artwork bundled in
`src/Media`; attribution is in `src/Media/NOTICE.txt`. It does not require Retail
atlas entries in the Forever client.

All presets share the Retail layout: portrait on the left, speaker name above
the quest text on the right. Switching styles preserves the content geometry.
All presets inherit the client's localized quest fonts: `QuestTitleFont`
for speaker names and `QuestFont` for dialogue, including their native sizes
so they match quest titles and descriptions. Names wrap
when they exceed the available width, and the text moves down to accommodate them.

Presets share a 570 by 155 panel at 100% scale. Existing custom dimensions are
preserved until a preset is selected, which restores this common size while
keeping the panel's position. The options page provides a silent player preview
for dragging the panel, horizontal centering and a position reset.
Starting the preview stops current quest playback, restores the NPC Dialog
settings and opens the draggable player model without sound. A second click
closes the preview; interrupted playback does not resume automatically.

The default position is bottom center above the action bars, following Retail's
`BottomManagedFrameContainer` bottom anchor. WowVoice follows that boundary
without joining Blizzard's alert stack. If the container is unavailable, it uses
the `TalkingHeadUI.xml` fallback of 96 UI units above the bottom edge. Saved
positions take priority; `/wv head reset` restores the default. Previewing or
switching appearance presets preserves the default anchor until a position is saved.

The default geometry follows Blizzard's talking head: a 115 by 115 model at
(21, -21), the name at (152, -25), a 3-unit gap before dialogue and a 42-unit
right text inset. The full-width 2-unit progress bar is a WowVoice addition.

Every preset has a close button in the upper-right corner that stops playback.
Retail and Classic use the stock WoW cross; EllesmereUI uses the borderless
`uitools-icon-close` glyph with a brighter hover state, matching its options window.
The heading leaves room for the button. The progress bar
spans the bottom of the panel with equal side insets, below both portrait and text.
The close button provides hover and pressed feedback. Other
WowVoice buttons can still use EllesmereUI styling when it is available.

## Portrait camera profiles

Camera framing is selected from the loaded model's `GetModelFileID()`, so it
also works for journal replays without a nearby NPC. `CameraProfiles.lua`
contains initial, uncalibrated model-family settings, including non-playable
quest givers such as ogres, furbolgs, centaurs, murlocs and dragons. Goblins and
trolls have dedicated offsets and more distance. Male goblins use a separate
profile with a small leftward shift to leave room for the nose during speech,
confirmed for the tested model. Female trolls use a separate
centered profile; the accepted male troll lateral offset is preserved. Female
blood elf models also have a separate, wider and higher framing to leave
room for their talking animation in both directions, confirmed for the tested
model. Female orcs have a separate profile with more distance and a small
leftward and upward shift, also confirmed for the tested model.
Other orc models and all tauren variants retain the accepted zoom, distance,
position and rotation. Camera profiles are estimates refined through in-game
feedback, not Blizzard-authored cameras.
Unrecognized models or unavailable APIs keep the original framing.

`CameraModels.lua` maps 1,218 model files using the
[WoW community listfile](https://github.com/wowdev/wow-listfile/releases/tag/202609242243).
Only model identities are derived from that source. Regenerate the table with
`node tools/build-camera-models.js <community-listfile.csv>` using that release.
`PortraitCameraOverrides` allows individual model corrections; `/wv diag`
includes the current model file ID and camera profile. All three styles share
these settings. The standalone Stop button is hidden whenever the talking head
is enabled; disabling the head restores the saved auto/always/off button mode.

## Quest speaker recovery

Journal replay also supports quests accepted before WowVoice was installed.
Captured per-character speaker data takes priority. When it is missing or has
no identity, the addon checks bags for an exact quest-starter item match, then
looks up the giver by quest ID in `WowVoiceIndex`. The bundled index contains
giver IDs for 3,686 of 4,205 quests; this is metadata coverage, not a guarantee
that every model is available in the Forever client.

Recovery never matches by title or substitutes the turn-in NPC. Conflicting
giver records are ignored. An unambiguous display ID already captured for the
same NPC on another quest of this character can be reused; otherwise the panel
loads the creature by NPC ID. Inferred NPC records remain transient. Recovered
item metadata is saved so its icon survives consumption and reloads. Captured
items and game objects are never replaced with an inferred NPC.

Unavailable metadata or models leave the document icon visible while audio
continues. No external addon or database download is required.

On login and quest-log changes, voiced journal quests have their portraits
preloaded in the background. Requests are deduplicated by NPC or captured display
ID and started at most four times per second. Successful lookups stay in memory
for this session. Failed warmups stop after a bounded attempt window; a later
quest-log update can retry them after a cooldown. The visible portrait also
retries for up to 20 seconds without restarting audio. Readiness is confirmed by
`OnModelLoaded`, not merely a positive display ID: metadata can arrive before the
render resources. Every load reapplies the camera. A cold client cache can still
cause an initial delay.

## Local configuration

`config/deploy.targets.local.psd1` is intentionally not committed. Start from
`config/deploy.targets.example.psd1` if the local file does not exist, and set
the Forever Beta AddOns directory:

```powershell
@{
  ForeverBeta = 'C:\Games\World of Warcraft\_classic_beta_\Interface\AddOns'
}
```

`ForeverBeta` is the only supported deployment target; PTR, Retail and All are
not supported. Use `-ConfigPath` to load a configuration file from another
location. The destination must exist and end in
`_classic_beta_\Interface\AddOns`. Deployment rejects junctions and symlinks.

## Deployment and backups

Before writing any files, Deploy creates `backups/<timestamp-id>/` containing
the existing `WowVoice` directory and the two sound pack TOC files it will
replace. It then synchronizes `src/` into `AddOns\WowVoice`, removing old files
that are no longer present in the source. Existing IDE workspace state under
the installed addon's `.idea` directory is preserved.

Only `WowVoiceSounds.toc` and `WowVoiceSounds_Mainline.toc` are copied into
`WowVoiceSounds`. OGG audio and other sound pack files remain unchanged. Other
addons and `WTF` are not modified. Run `/reload` after deployment.

To roll back, restore `WowVoice` and the two TOC files from the appropriate
backup directory. Its `destination.txt` records the AddOns destination.

## Release package

Package creates a ZIP archive, using the version from `src/WowVoice.toc`:

```text
artifacts/WowVoice-<version>.zip
```

The ZIP contains:

```text
WowVoice/                         Complete addon from src/
WowVoiceSounds/
  WowVoiceSounds.toc
  WowVoiceSounds_Mainline.toc
README.md                         Russian user guide from USER_README.md
```

Tests, development tools, IDE settings, backups and OGG audio are excluded.
Maintain the installation and usage instructions in [USER_README.md](USER_README.md)
in Russian; the repository README is for development documentation in English.

## Sound pack source

Original project: [HappyDridex/wowvoice, release v1.0](https://github.com/HappyDridex/wowvoice/releases/tag/v1.0).
The required archive is [WowVoice-classic-1.15.zip](https://github.com/HappyDridex/wowvoice/releases/download/v1.0/WowVoice-classic-1.15.zip).
The recorded SHA-256 from the verification on September 26, 2026 is:

```text
72a56917473756cd853c4cef7e8feb91b663aeee55c743cdd78f484016858133
```

That verification found all 10,891 installed OGG files identical to the archive
by SHA-256. The repository's `Index.lua` and `Durations.lua` also matched the
archive. Sound pack changes are limited to the TOC files for Interface 16001.
Keep the Classic duration table; do not replace it with the Midnight version.

## IntelliJ IDEA run configurations

Create a **Shell Script** run configuration for each desired task:

- Script path: `$ProjectFileDir$\build.ps1`
- Interpreter path: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
- Interpreter options: `-NoProfile -ExecutionPolicy Bypass -File`
- Working directory: `$ProjectFileDir$`
- Script options: `-Task Validate`, `-Task Test`,
  `-Task Deploy -Target ForeverBeta` or `-Task Package`.

If **Shell Script** is not listed, enable JetBrains' Shell Script plugin. IDEA
can then store selected configurations as project files under `.run/`.
