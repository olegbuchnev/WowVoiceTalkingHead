# WowVoice — Forever Beta

This standalone repository keeps the modified WowVoice development sources
outside the live World of Warcraft installation. Runtime addon files live under
`src/`; tests and build tools stay outside that directory and are never deployed.
The runtime code is based on the Midnight version, while `Index.lua`,
`Durations.lua` and the primary OGG audio come from the Russian Classic sound pack.
The release also bundles supplemental CatQuest recordings for quests absent from
that pack. Original WowVoice recordings always take priority.
This build targets **WoW Forever Beta, Interface 16001**.

For installation and in-game usage, see the [user guide in Russian](USER_README.md).
The release archive includes that guide as plain-text `README.txt` (UTF-8).

The proposed license is deferred. Its [English draft](docs/internal/license-drafts/LICENSE)
and [Russian translation](docs/internal/license-drafts/LICENSE.ru.md) are retained
for future review, are not adopted for the current release and are excluded
from release archives.

## Layout

```text
src/                             Runtime files copied to AddOns/WowVoice
soundpack/                       Complete Classic audio and two Forever TOCs
catvoices/                       Filtered CatQuest audio, metadata and attribution
tests/                           Lua tests with WoW API mocks and pipeline checks
config/deploy.targets.local.psd1  Local Forever Beta path (gitignored)
build.ps1 / build.cmd             Validate, test, deploy and package pipeline
USER_README.md                   Russian user guide; converted to README.txt for packaging
artifacts/WoWVoice/              Latest release ZIP; stable folder for cloud sync (gitignored)
backups/                         Backups created before deployment (gitignored)
```

Edit `src/`, then run Deploy. The installed `AddOns\WowVoice` directory is a
deployment destination, not the project's source directory. OGG files are local
build inputs (gitignored) and are included in the complete release archive.
Populate them with `tools/import-classic-audio.js <WowVoiceSounds directory>` and
`tools/import-forever-audio.js <CatQuest_Voices directory>` using Node.js after
`npm ci`. Both tools read already extracted local sound packs.

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

Build a release archive only when explicitly requested. Routine changes can be
tested and deployed locally while accumulating the next release; do not run
Package after every change or update the shared pCloud archive automatically.

```shell
.\build.cmd -Task Package
```

Package creates the new ZIP in a temporary staging directory, then places it in
`artifacts/WoWVoice/` and removes older ZIPs, including archives left directly in
`artifacts/` by earlier builds. The `WoWVoice` directory is never recreated, so it
can be paired with a cloud folder for synchronization. A failed archive build
leaves the previous release in place.

For pCloud, configure Sync once between the local `artifacts/WoWVoice` folder and
a cloud folder named `WoWVoice`, then share the cloud folder's link. Each Package
build updates the local archive; pCloud handles uploading it. Synchronization
and public sharing are configured separately in pCloud, not by the build script.

Release folder link: [WoWVoice on pCloud](http://e.pc.cd/ju6y6alK).

To copy the short link in IntelliJ IDEA, hover over the block below in the
Markdown preview and click its copy button:

```text
http://e.pc.cd/ju6y6alK
```

Keep this cloud folder and its shared link when updating releases. This link is
recorded only in the development README, which is excluded from release archives.

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

The on-screen quest tracker has small replay arrows to the left of voiced quest
titles, including when styled by EllesmereUI. They replay the description using
the current quest ID and leave the tracker layout unchanged. The options page
can hide these controls independently of journal buttons and the talking head;
`WowVoiceDB.trackerButtons` defaults to true.
Replay buttons in the journal list, quest details and on-screen tracker are
hidden when description audio is unavailable. Controls have no tooltips;
hover highlighting remains. The former `playTooltips` setting is removed.

The options page offers three appearance presets: Retail (selected by default),
Classic and EllesmereUI. Installing EllesmereUI does not change the default;
an explicitly saved preset is preserved. All three work without additional addons. Switching
presets updates the panel without interrupting playback.

All presets appear immediately, with no fades during playback or line changes.
When audio ends, Dialog is restored immediately and the entire panel, including
the idle model, fades out together over one second. Model geometry opacity is
set explicitly with `SetModelAlpha`; its ancestor frames remain opaque so the
model does not outlast the background or receive a doubled fade.
The model also follows inherited UI opacity and game UI visibility, including
Dialogue UI's hide-interface mode. Hiding the panel does not interrupt audio;
late model loads cannot reveal a portrait over a hidden interface.
The cross, right-click and manual stop dismiss the panel immediately, including
during fade-out. Replacing a line restores full opacity immediately; there are
no delayed callbacks that can hide a newer line or preview.

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

`ForeverSpeakers.lua` bundles 3,765 confirmed single-NPC quest starters, including
450 of the 697 supplemental voiced quests. It also marks 316 confirmed object or
multiple-starter quests so they cannot accidentally inherit a Classic NPC guess.
Captured identities and exact quest-starting items take priority. Missing records
still fall back to the Classic index. No internet connection or other addon is
needed in-game. Model availability in the client is separate from NPC identity.

The factual IDs come from [Wowhead Forever](https://www.wowhead.com/forever/),
using the [public snapshot maintained by Forever Quest Pins](https://github.com/TylerAkins/forever-quest-markers/tree/2d354aa828af29cb2e997b7367f7bb59b75f10e2/data/forever-quests).
The snapshot catalog contains 5,058 quests: 697 parsed pages lack starter data,
279 unusable detail records are excluded, and quest 7507 has no detail file.
This is a coverage snapshot, not a claim that every Forever quest has a portrait.
Russian NPC names are reused by exact NPC ID from the original Classic index;
otherwise the source's English name is retained until a live giver is captured.
Only starter facts are imported, not the external addon's code, map or quest text.

To import a newer extracted snapshot (JSON only):

```shell
node tools/import-forever-speakers.js <data/forever-quests-directory> <commit-SHA>
```

`docs/internal/forever-speakers-manifest.json` records the commit, per-record
SHA-256, excluded records and exact starter IDs. It is excluded from the release.
Running the importer without arguments regenerates the Lua index offline from
this manifest. Imports never infer a giver from the quest title or turn-in NPC.

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

The complete Classic audio and its two TOCs are copied into `WowVoiceSounds`;
filtered supplemental audio is copied into `CatVoices`. Existing extra files in
the sound directories are preserved. The current `CatVoices` folder is also
backed up when present; the large Classic audio library is not backed up.
Other addons and `WTF` are not modified. Fully restart the game after deployment
so the client can discover newly added sounds.

To roll back, restore `WowVoice`, the two TOC files and, if present, `CatVoices`
from the appropriate backup directory. Its `destination.txt` records the AddOns
destination. Restore older Classic audio from its original archive if needed.

## Release package

Package creates a ZIP archive, using the version from `src/WowVoice.toc`:

```text
artifacts/WoWVoice/WowVoice-<version>.zip
```

The ZIP contains:

```text
WowVoice/                         Complete addon from src/
WowVoiceSounds/                   Complete Classic audio and two Forever TOCs
CatVoices/                       Additional audio, metadata and attribution
README.txt                        Plain-text Russian user guide from USER_README.md
```

Tests, development tools, IDE settings, backups and internal manifests are excluded.
Maintain the installation and usage instructions in [USER_README.md](USER_README.md)
in Russian; the repository README is for development documentation in English.

The bundle includes 10,891 Classic recordings and 909 supplemental recordings
for 697 additional quests (697 descriptions and four turn-ins, including gender
variants). Filtering excludes an entire CatQuest quest if any section of that
quest exists in the Classic duration index. CatQuest itself is not required.
`ForeverAudio.lua` supplies the additional filenames and exact durations read
from each OGG stream. Runtime selection also gives Classic entries priority.
The import manifest and SHA-256 hashes are retained in
`docs/internal/forever-audio-manifest.json`, outside the release. The supplied
CatQuest pack's loaded Lua index is authoritative; JSON-only entries are not
imported. Source credit is preserved in `CatVoices/NOTICE.txt` and the user guide:
CatQuest and CatQuest_Voices are by [Cathey](https://t.me/catheyco) (daniilcathey).

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
