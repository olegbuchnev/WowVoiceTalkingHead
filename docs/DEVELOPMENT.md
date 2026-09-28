# Development guide

WowVoice TalkingHead is a Forever Beta build based on WowVoice, with talking
heads and quest playback controls. This repository keeps its development sources
outside the live World of Warcraft installation. Runtime addon files live under
`src/`; tests and build tools stay outside that directory and are never deployed.
The runtime code is based on the Midnight version, while `Index.lua`,
`Durations.lua` and the primary OGG audio come from the Russian Classic sound pack.
The release also bundles supplemental CatQuest recordings for quests absent from
that pack. Original WowVoice recordings always take priority.
This build targets **WoW Forever Beta, Interface 16001**.

The in-game title is **WowVoice TalkingHead**, and its addon ID and folder are
`WowVoiceTalkingHead`. The command remains `/wv`; audio folders are `WowVoiceSounds`
and `CatVoices`.
The cloud sync directory also retains its existing name and shared link.

For installation and in-game usage, see the [user guide in Russian](../USER_README.md).
The release archive includes that guide as plain-text `README.txt` (UTF-8).

The proposed license is deferred. Its [English draft](internal/license-drafts/LICENSE)
and [Russian translation](internal/license-drafts/LICENSE.ru.md) are retained
for future review, are not adopted for the current release and are excluded
from release archives.

## Layout

```text
src/                             Runtime files copied to AddOns/WowVoiceTalkingHead
soundpack/                       Complete Classic audio and two Forever TOCs
catvoices/                       Filtered CatQuest audio, metadata and attribution
tests/                           Lua tests with WoW API mocks and pipeline checks
config/deploy.targets.local.psd1  Local Forever Beta path (gitignored)
build.ps1 / build.cmd             Validate, test, deploy and package pipeline
USER_README.md                   Russian user guide; converted to README.txt for packaging
artifacts/WoWVoice/              Latest full and addon-only ZIPs; stable cloud sync folder (gitignored)
backups/                         Backups created before deployment (gitignored)
```

Edit `src/`, then run Deploy. The installed `AddOns\WowVoiceTalkingHead` directory is a
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
`artifacts/WoWVoice/` and removes older full ZIPs, including archives left directly in
`artifacts/` by earlier builds. The `WoWVoice` directory is never recreated, so it
can be paired with a cloud folder for synchronization. A failed archive build
leaves the previous release in place.

### Build a small addon update (without audio)

```shell
.\build.cmd -Task PackageAddon
```

Creates `artifacts/WoWVoice/WowVoiceTalkingHead-<version>-addon-only.zip` containing only
`WowVoiceTalkingHead/` and the same plain-text `README.txt` from `USER_README.md` as the full archive. Use it to
deliver code fixes to users who already have the full sound library installed.
It includes the entire runtime addon, including textures and audio indexes,
and can be built without local `soundpack/` or `catvoices/` directories.
Runtime layout and TOC checks still run. The version is not changed.

The shared folder retains one full release and one addon-only update. Building
either kind replaces only that kind, preserving the other archive and the short
link. Full releases remain necessary for first installation or new recordings.

For pCloud, configure Sync once between the local `artifacts/WoWVoice` folder and
a cloud folder named `WoWVoice`, then share the cloud folder's link. Each Package
build updates the local archive; pCloud handles uploading it. Synchronization
and public sharing are configured separately in pCloud, not by the build script.

Release folder link: [WowVoice TalkingHead on pCloud](https://e.pcloud.link/publink/show?code=ju6y6alK).

To copy the folder link in IntelliJ IDEA, hover over the block below in the
Markdown preview and click its copy button:

```text
https://e.pcloud.link/publink/show?code=ju6y6alK
```

Keep this cloud folder and its shared link when updating releases. This link is
also listed on the project landing page. Development documentation is excluded from release archives.

### GitHub publication

Show changes to the player-facing README to the user before pushing them.
Publish those changes only after the user approves the preview. Keep its wording
factual and avoid promotional slogans.

Source repository: [olegbuchnev/WowVoiceTalkingHead](https://github.com/olegbuchnev/WowVoiceTalkingHead).
Commit source changes and use `git push origin main` to publish them. Pushing
source does not build or upload release archives. Publish the full and addon-only
ZIPs as GitHub Release assets after the requested package builds; keep the pCloud
copies as well. Do not attach local backups, deployment settings or extracted
audio sources to the repository. Audio belongs in the full release ZIP.

The player-facing README links directly to the full and addon-only ZIP assets
using `/releases/download/<tag>/<filename>`, so clicking starts the download.
For every release, update all corresponding download links in README.md (both
the opening links and the installation/update instructions) to the published
assets. Verify both URLs before pushing the approved README. Keep the previous
working links until the replacement assets are published; do not change the
addon version merely to refresh these links.

Release assets include `SHA256SUMS.txt` for download integrity checks. Checksums
verify that a download matches the published files; they are not an antivirus
certification.

IntelliJ IDEA shows a Run/Play gutter icon for each command block when
**Detect commands that can be run right from Markdown files** is enabled in
**Languages & Frameworks | Markdown**. Use the repository root as the working
directory.

Deploy and Package run Validate first; PackageAddon checks runtime files without
requiring audio sources. Test runs separately. All build tasks require Windows
PowerShell 5.1. Test locates Node.js/npm through
PATH, `NODE_EXE`, IntelliJ's local Node runtimes or standard installation
directories. It runs `npm ci` to install the dependencies pinned in
`package-lock.json`; an internet connection is required if they are not cached.

The tests check Lua 5.1 syntax and behavior with WoW API mocks: quest events,
playback and Dialog restoration, the quest journal, portraits, item speakers,
persistence across reloads, options and block scrolling. Pipeline checks use an
isolated temporary directory without deploying to the game. These checks do not
replace API and visual verification in the Forever client.

## Playback and background sound

The default `/wv channel auto` selects the playback channel for each recording.
With `Sound_EnableSoundWhenGameIsInBG=1`, it uses Master and keeps zone music
playing. During the recording, Master volume is multiplied by the user's original
Dialog volume (100% Master and 30% Dialog becomes 30% Master). This also lowers
music and other game sounds until playback stops. With background sound disabled,
it uses PlayMusic: live Forever testing
confirmed that the voice becomes silent in the background and returns at the
current playback position when the game regains focus. The addon never changes
the background-sound setting. Music playback temporarily enables music and sets
its volume to the user's original Dialog volume without changing Master. It
replaces zone music. Both paths restore their temporary settings on stop,
completion, logout or an explicit playback failure. Settings manually changed
during playback are preserved if they differ from the addon's temporary values.
Consecutive recordings use the original values rather than repeatedly reducing
volume. `/wv volume 0..1` is an additional Dialog-relative multiplier in both paths
(default 1). NPC Dialog suppression applies to both playback paths,
unless `/wv duck off` is selected.

Changing the background preference does not restart or move the current voice;
the next recording uses the new preference. If background sound is disabled
during a Master recording, minimizing can still interrupt that recording.
`/wv channel sound` and `/wv channel music` retain their explicit overrides.
PlayMusic can report less reliable file availability than PlaySoundFile; an
explicit failure is handled, but a successful return cannot prove audibility.

## Background preparation and frame time

`Work.lua` runs a shared cooperative queue with a soft 1 ms budget per frame,
measured with `debugprofilestop`. Jobs yield between small units. The scheduler
uses measured step costs to defer work that is unlikely to fit, and rotates jobs
so an expensive step cannot starve. Native client calls cannot be interrupted;
overruns are recorded rather than presented as a hard guarantee. Without the
profiler, a 64-step ceiling still bounds each slice. No callback remains attached
to `OnUpdate` when the queue is empty. Clients with timers also sleep between
scheduled retries; older clients use a lightweight waiting callback.

Portrait preparation starts three seconds after login/world entry, pauses in
combat and while leaving the world, and resumes automatically. The Classic
reverse speaker index is built incrementally. Each journal scan walks inventory
slots once and saved speaker appearances once, rather than once per quest.
Only current snapshots are committed; inventory changes request a fresh scan.
The warmup worker spaces model requests at least 0.25 seconds apart, with at most
two pending attempts, a two-second attempt timeout and bounded retries. Each
model frame retains its own NPC identity so late events cannot cross speakers.
Finished or exhausted queues stop running until relevant events request work.

Manual playback does not wait for preparation. Before the reverse index is
ready, it resolves only the requested ID synchronously. Existing live capture,
item identity and the visible portrait's retry path remain available immediately.

Quest-progress events coalesce over 0.05 seconds; the scan yields between quests
and remains enabled in combat. Login/world entry resets the silent baseline and
cancels an older scan. Progress changes within one coalescing window are observed
as the latest state. Playback and the golden reminder animation are not queued.

`/wv perf` reports session-local pending work, maximum slice duration, overruns,
errors, and per-job total/max step time. `/wv diag` includes the same report.
The measurements cover this queue, not total frame time or all other addons.
Regression tests verify budget sharing, combat behavior, idle shutdown, native
overrun reporting, and 100 inventory queries for 25 quests/100 slots (previously
2,500). These are controlled mocks, not an in-game FPS benchmark.

## Appearance

Quest descriptions play automatically by default. Disable
«Озвучивать при получении задания» in the options page to opt out
(`WowVoiceDB.autoPlayAccept`). A one-time migration enables this setting after
the unreleased build that defaulted it off; later checkbox choices are preserved.
With autoplay disabled, quest giver and description capture still runs,
and manual replay from the journal or tracker remains available.
«Озвучивать при сдаче задания» independently controls all progress and completion
dialogue (`QUEST_PROGRESS` and `QUEST_COMPLETE`, sections `p` and `c`) for both
audio packs. `WowVoiceDB.autoPlayTurnIn` defaults to true; a saved opt-out is
preserved. Neither preference blocks manual description replay. Changing either
preference does not interrupt or start the current recording.

The on-screen quest tracker has small replay arrows to the left of voiced quest
titles. They replay the description using
the current quest ID and leave the tracker layout unchanged. The options page
can hide these controls independently of journal buttons and the talking head;
`WowVoiceDB.trackerButtons` defaults to true.

Questie support is optional and contained in Tracker.lua. The adapter imports
only TrackerLinePool and QuestieTracker through QuestieLoader. It enumerates
title rows through UpdateQuestTitleLines and reads mode, Quest.Id, label and
expandQuest; it does not inspect the private pool, parse title text or replace
Questie's VoiceOver integration. Post-hooks on Update/UpdateFormatting coalesce
refreshes to the next frame. ResetLinesForChange and row visibility hooks prevent
recycled objective/zone/achievement rows from retaining a play control. The click
handler resolves the current quest ID again. Missing module methods disable the
adapter without affecting Blizzard's tracker. No Questie files or saved settings
are edited and no TOC dependency is added.

The extra column is anchored left of expandQuest, whose anchor persists when the
native minus is hidden for completed quests or item buttons. Quest names, item
buttons, objective indents, wrapping widths and row heights are unchanged. Icons,
gaps and reminder glows follow the actual title FontString font size on formatting
updates; tracker scale is inherited, including a scaled scroll child. Controls
are siblings of the nearest scroll frame to avoid horizontal clipping, and are
hidden when their first-line hit rectangle crosses the viewport's top/bottom.
Scrolling, resize and row show/hide refresh visibility without a permanent poll.
Hover delegates to the row's existing enter/leave handlers for Questie's fading.
Questie controls share availability, playback, options and progress reminders
with the native controls. Visual placement still requires verification in-game.

For the exact reminder decision order, saved-state semantics and examples, see
[Алгоритм напоминаний об озвучке](QUEST_REMINDERS.md) (developer notes).
«Напоминать об озвучке при прогрессе» enables both the silent gold glow around
those tracker buttons and the replay notification (`WowVoiceDB.trackerProgressPulse`, default
true). Its checkbox is indented under the tracker-button option and disabled
when the parent is off, preserving the saved reminder preference.
Each eligible objective change shows the standard gold ActionButton glow with its animated
`IconAlertAnts` edge for 10 seconds. Size and opacity stay constant; there is no
additional pulsing or fading.
The triangle retains its normal 70% opacity (100% on hover); glow brightness is
independent and does not change the icon's opacity.
Further progress restarts that 10-second window; unchanged quest-log updates,
accepting a quest and login/reload do not trigger or extend reminders.
Only quests with description audio get a glow. The same eligible progress also
shows a five-second clickable gold `Вспомнить задание` line below the native
visible message regions. Rendered FontString bounds account for wrapping and
stacked messages, including messages that arrive later. The reminder only moves
downward until hidden, so disappearing status text does not move the click target
upward. A fresh appearance resets the offset. `Напоминать об озвучке при прогрессе` in `Кнопки и напоминания`
controls both effects through the existing `trackerProgressPulse` preference.
Hiding the controls or disabling the reminder immediately removes both effects.
Neither starts playback automatically. Native progress text is never duplicated.
Repeated progress refreshes the line; a hovered line keeps its quest click target
even when another quest changes. Multiple changes prefer the latest
`QUEST_WATCH_UPDATE` quest, falling back to stable quest-ID order. Abandoning a
quest, reacceptance, loading screens, audio unavailability and manual replay clear
its notification. Final objective progress follows the same rules as intermediate
progress: reaching 9/9 or finishing an escort can remind if no listening pause is
active. Whole-quest completion does not hide or suppress the reminder. Unchanged
completion events do not renew it; login with a completed quest stays silent.
`QUEST_ACCEPTED` only resets the quest's baseline and existing reminder. There is
no acceptance timer or cross-quest eligibility rule; old `lastAcceptedQuest` data
is ignored. Baselines stay current with the option disabled; acceptance, missing
cache entries and unchanged snapshots do not count as progress.
`QUEST_REMOVED` cancels a pending scan and clears this quest's baseline, reminder
and listening pause for the current character. A new acceptance cannot inherit
the abandoned attempt's pause. Acceptance itself preserves a fresh pause from
automatic description playback in the new offer, which can precede acceptance.
Descriptions that successfully start automatically or through manual Play suppress
reminders for that character and quest for 30 minutes, even if closed early or
replaced. While that pause remains active, each objective change for the same quest
renews it for another 30 minutes. After 30 minutes without progress, the next change
can remind rather than silently renew an expired pause. Combat, other quests and
unchanged snapshots do not extend it.
`WowVoiceDB.listenedQuests` stores absolute expiry timestamps by player
GUID and quest ID, using server time (or epoch time on older clients). Reload,
zoning and full logout/login preserve the deadline; time spent offline counts.
A successful replay renews the pause. Failed playback and turn-in lines do not
start or extend it. Expiry alone does not show a glow: the next objective change
can trigger one. Expired entries and legacy session booleans without timestamps
are discarded. The pause is recorded by successful description playback in `Speak`
and `ReplayQuest`, independently of the portrait. Duplicate dialogue events that
do not start audio do not renew it. Existing one-hour timestamps are shortened by
30 minutes once for all characters, preserving their original start time; the
`reminderCooldown30Minutes` flag prevents repeating the migration.
«Тест / переместить» also previews the glow on all active tracker replay buttons,
including heard quests and with the reminder preference disabled. The same animated
glow stays visible until preview stops, options close, or real
playback replaces the preview. Hidden tracker controls remain hidden.

`/wv remindertest [questID]` previews the same replay notification below
`UIErrorsFrame`, together with a yellow test message showing that quest's first
objective. Without an ID it randomly selects a voiced journal quest whose replay
button is currently visible in the tracker (including parent visibility, alpha
and screen bounds). An explicit ID must meet the same conditions. With no eligible
quest it only prints an explanation. The selected tracker button glows for ten
seconds; repeating the test replaces that test glow and `off` clears both preview
elements. Test glow does not change real progress pulses or saved cooldowns.
A single background-free text line
uses the system message font and size, with the tracker's replay icon scaled
proportionally on its right, below the bottom visible system message line.
The text uses the original gold color, matching the replay icon.
It lasts five seconds including its fade, stays visible while hovered and starts
a fresh five-second countdown on every mouse leave. Repeated tests also restart
the timer. Tracker glow still lasts ten seconds.
Showing it does not change quest progress, acceptance history or cooldowns.
Clicking the mock line or that quest's tracker button while the mock is active
plays its description without setting or extending the listening pause. An
existing real cooldown remains intact. After the mock ends, ordinary manual Play
uses the usual cooldown again. The mock bypasses real reminder eligibility
without modifying the listening pause.

Replay buttons in the journal list, quest details and on-screen tracker are
hidden when description audio is unavailable. A failed description playback
also hides its replay controls and glow in both journal and tracker for the
current UI session. Reload clears this failure cache; a successful automatic
retry restores availability too. Files listed in the bundled audio index are
assumed available until playback reports failure; the addon does not probe them
by playing audio in the background. Controls have no tooltips;
hover highlighting remains. The former `playTooltips` setting is removed.

The talking head always uses Retail appearance. The head visibility checkbox,
Classic/EllesmereUI themes and the standalone Stop button have been removed.
Loading clears their obsolete saved preferences while preserving panel position,
custom dimensions, scale and playback options. The options page provides a
silent player preview for dragging, horizontal centering and a position reset.

Retail follows Blizzard's talking-head composition: a soft translucent background,
a gold portrait frame, the speaker's name above the text on the right, and a close
button that stops playback. Original TalkingHeads artwork is bundled in
`src/Media`; attribution is in `src/Media/NOTICE.txt`. It does not require Retail
atlas entries in the Forever client. Names and dialogue inherit the client's
localized `QuestTitleFont` and `QuestFont`, including native sizes. Long names
wrap and move the quest text down to prevent overlap.

The panel appears immediately, with no fades during playback or line changes.
When audio ends, Dialog is restored immediately and the entire panel, including
the idle model, fades out together over one second. Model geometry opacity is
set explicitly with `SetModelAlpha`; its ancestor frames remain opaque so the
model does not outlast the background or receive a doubled fade.
The entire panel uses an independent root frame: hiding or fading `UIParent`
leaves the portrait, text and controls visible together. It uses
`FULLSCREEN_DIALOG` at frame level 200 to stay above dialogue/tutorial banners.
This does not depend on Dialogue UI or any other addon's files or load order.
The anchor uses UIParent-relative coordinates and mirrors its effective scale.
The cross, right-click and manual stop dismiss the panel immediately, including
during fade-out; late model loads cannot reveal a dismissed portrait.

The default panel is 570 by 155 at 100% scale. Saved custom dimensions remain.
The options page provides a 50–150% whole-panel scale slider and an integer
percentage field (Enter applies; Escape or focus loss cancels edits). Dragging
uses fractional percentages for continuous preview; the displayed percentage
and the value committed on release are rounded to 1% steps.
The first drag event (including a value callback delivered before mouse-down)
opens an idle panel's silent test automatically. An existing test or real playback
is reused without toggling, restarting or silencing it. An automatically opened
preview starts the normal one-second end-of-line fade immediately on slider release.
Successful numeric scale/coordinate entry shows it for two seconds before that fade;
anchor selection also uses the two-second hold. Explicit Test mode remains open
after these actions, and closing options leaves real playback running.
Automatic preview identity and its hold deadline belong to the current playback
object, so a replacement quest cannot inherit an old deadline. Repeated edits cancel
the previous deadline/fade and reuse the model. Dragging holds the preview until
release; mouse positioning starts a new two-second hold after release. Pressing Test
during automatic preview promotes it to persistent Test mode without reloading.
When `FontStringScaleAnimationMode.Vertex` is available, dragging moves the name
and text scroll frame into a temporary layer with a fixed native effective scale.
A constant looping Scale animation transforms that layer by requested/start scale,
using the same ratio on both axes and a top-left origin. Font strings use Vertex
mode so the glyph geometry scales without recomputing glyph widths or word spacing.
The original text, wrapping and font sizes stay unchanged. Native child anchors
and ScrollFrame clipping do not follow the glyph animation: title/body offsets,
viewport size, scroll-child extent and scroll offset are therefore explicitly
multiplied by the same ratio in the layer's fixed-scale units. Every update uses
the captured values, avoiding cumulative drift; cleanup restores those values.
Each changed preview scale stops the previous text transform before changing
parent geometry. The transform restarts only after the final panel size, anchored
position and scroll clipping have been applied, including non-central pivots.
The portrait also keeps its original native effective scale while dragging by
temporarily ignoring parent scale. Its viewport dimensions and anchor offsets
use the same requested/start ratio, preserving the square aspect ratio without
calling `RefreshCamera` on each step. Release, cancel, closing options or stopping
playback restores the model's scale, size and anchors, stops the text transform
and restores parents and font animation modes before normal final layout. `/wv diag` reports
`Text scale preview: vertex` when this path was selected.
Portrait loading and camera updates explicitly disable native model blending;
player previews also pass `false` to `SetUnit`'s blend argument. This keeps reuse
of the same PlayerModel consistent across player tests and NPC playback. Speaker
capture/cache refresh requests arriving during a scale drag are coalesced and
applied after release/cancellation, so they cannot clear the frozen model mid-drag.
The last three drags retain a bounded, session-only diagnostic summary: camera
refreshes, viewport resizes (`view`), load/reload requests, show/hide events, zero-alpha writes, sampled
visibility/readiness, display changes, pause/blend state and playback completion.
Read it with `/run WowVoice:HeadScaleDiagnostics()` (also included in `/wv diag`).
Nothing is printed automatically or saved to SavedVariables. These counters trace
addon/native events; they do not measure GPU flicker or prove its absence.

Clients without Vertex support instead capture the current panel once through `OffScreenFrame:TakeSnapshot`
and `ApplySnapshot` after allowing two render frames, then scales that texture.
The source is hidden when capture succeeds so it cannot cover the texture.
The latest requested slider value is applied as soon as the capture is ready.
The live panel is temporarily
parented to the offscreen capture at its original effective scale; its model,
text and camera remain unchanged throughout the drag. Mouse release (including
outside the slider) restores the live parent, applies the final scale and refreshes
the portrait camera. Snapshots are limited to one and flushed after use.
Failed capture is retried for at most six frames, then the live panel scales
with its pose/text paused. Slider events are coalesced to the latest percentage
once per frame; duplicate percentages do nothing. The live fallback calls only
`RefreshCamera` after a scale change, preserving zoom, position and rotation
instead of reapplying the portrait profile on every step.
In this fallback, name, body and measuring font strings enable `SetSmoothScaling` only during a
drag, when available, avoiding integer font-height jumps in the preview. Release
or cancellation restores each font string's previous mode and reapplies the
native font at the final effective scale; preview rendering is not kept afterward.
Before changing that mode, a hidden font string measures complete word prefixes
with the name/body's original font, spacing, width and scale. The preview fixes
the current word wraps with explicit newlines and adds enough width to prevent
additional automatic wraps, keeping multiline rendering enabled. Both the
measured candidate and the displayed result must retain the original text height;
otherwise the source remains unchanged. Unreproducible layouts (such as words
spanning several lines) also retain their normal rendering. Release or cancellation
restores the exact source text, widths and wrapping flags; the committed scale
then receives its normal layout. Measurements happen once per drag.
Live scaling refreshes the native scroll-child
rectangle once per changed scale while retaining the frozen scroll offset and
line layout; it does not reset text, fonts or widths during dragging.
Unsupported capture uses this same live fallback. `/wv diag` reports the last
capture status. Cancellation removes pending callbacks as well as the snapshot.
The silent preview resumes its frozen clock; real audio continues and the text
catches up on release. Closing options cancels the temporary scale and unpauses
the model. Ending/replacing playback also clears the temporary state.
The options page includes a panel outline with nine mutually exclusive 32-unit
radio buttons: corners, edge midpoints and center.
The controls use layered 128px `TempPortraitAlphaMask` circles instead of enlarging
the legacy 16px radio sprites: a grey outer ring, dark center and gold selected dot.
The coordinate area has one caption, without a repeated anchor name or keyboard hint.
Numeric fields use `GameFontHighlightSmall` and a thin grey rectangular backdrop,
matching the compact AceGUI slider fields seen in Questie's options.
Selecting a point stores
`headAnchor` and converts the current center into `{ point, point, x, y }` screen
offsets in `headPosition`, without moving the panel. It opens an idle silent preview
or reuses existing playback. The page scrolls vertically to keep every setting
accessible at smaller UI sizes.
The page groups panel geometry, quest autoplay and tracker controls into separate
sections with headings and dividers. X/Y fields next to the diagram expose the
chosen point's coordinates from UIParent's center, in UIParent units:
positive X is right and positive Y is up. The legacy `GetHeadSettings().x/y` remain
center-relative panel-center coordinates; `GetHeadAnchorPosition`/`SetHeadAnchorPosition`
use selected-point coordinates with the same screen-center origin for all nine points.
Changing selection changes the coordinates only by the distance between points on
the panel, never by changing the coordinate origin. Existing saved edge-relative
placement is read without moving the panel. Enter or the apply button validates both fields before changing anything;
signed decimals accept either a dot or comma. Tab switches fields without discarding
drafts, Escape/closing options discard them, and unrelated option refreshes preserve
an active draft. Explicit positioning/scale actions discard the draft before refreshing.
Applied values are read back after screen clamping, displayed to two decimal places
without trailing zeroes. Coordinate entry opens idle preview without interrupting audio.
During mouse movement in preview mode, only the coordinate fields refresh each frame,
and only changed strings are rewritten. Starting a drag discards numeric drafts;
release saves the position and normal preview cleanup clears the movement flag.
The readout uses physical cursor displacement divided by the captured UI scale,
added to the initial panel center and clamped to screen bounds. It therefore updates
even when native StartMoving reports a stale frame rectangle until release. The final
saved position comes from the native rectangle after StopMovingOrSizing.
Scale changes preserve the chosen point of manually positioned panels. A drag
captures its original screen position once, then derives each new center from
that position and the scaled dimensions. Numeric input and release rounding use
the same pivot. Screen clamping takes precedence when growth reaches an edge;
reversing a drag uses the original pivot without accumulating clamp drift.
Movement and horizontal centering retain the explicit point and rewrite its offsets.
Existing center-based saved positions retain their behavior. The automatic default
keeps following the action-bar boundary until a point is chosen or the panel is moved.
The selector displays the current saved point, or bottom for automatic placement.
Scale and position have separate reset buttons; position reset also clears the
explicit anchor choice and restores automatic bottom placement. Saved legacy scale values are
rounded to whole percentages and limited to the supported range when displayed.
Starting the preview stops current playback, restores audio settings and opens
the draggable player model without sound. A second click or closing options
ends the preview; interrupted playback does not resume automatically.
The default position is bottom center above the action bars, following Retail's
`BottomManagedFrameContainer` without joining Blizzard's alert stack. If its
coordinates are unavailable, the anchor falls back to 96 UI units above the
bottom edge. Saved positions take priority; `/wv head reset` restores the default.
Opening an unmoved preview preserves the automatic anchor.

The default geometry uses a 115 by 115 model at (21, -21), the name at (152, -25),
a 3-unit gap before dialogue and a 42-unit right inset reserved for the stock
WoW close button. The full-width 2-unit progress bar has equal side insets below
both portrait and text. The close button has hover and pressed feedback.
Other WowVoice buttons can still match installed EllesmereUI journal/settings
styling; that integration does not change the talking head's Retail appearance.

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
Female tauren have a slight vertical lift with the original zoom and lateral position.
Female undead have a slight downward and rightward correction with the shared
profile's zoom. Male undead have a smaller downward correction to leave a margin
above the head; other undead retain their existing framing.
Other orc and tauren models retain the accepted zoom, distance,
position and rotation. Camera profiles are estimates refined through in-game
feedback, not Blizzard-authored cameras.
Unrecognized models or unavailable APIs keep the original framing.

`CameraModels.lua` maps 1,218 model files using the
[WoW community listfile](https://github.com/wowdev/wow-listfile/releases/tag/202609242243).
Only model identities are derived from that source. Regenerate the table with
`node tools/build-camera-models.js <community-listfile.csv>` using that release.
`PortraitCameraOverrides` allows individual model corrections; `/wv diag`
includes the current model file ID and camera profile.

## Quest speaker recovery

The initial quest-description briefing also resolves the indexed giver when
`QUEST_DETAIL` has no live `npc` or `questnpc`, including quests opened through a
gossip option (for example, quest 2842 from Sovik). Captured NPCs, exact starter
items and game objects keep priority. Inferred identities remain transient, and
this fallback never substitutes the giver for a progress/completion speaker.

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
455 of the 703 supplemental voiced quests. It also marks 316 confirmed object or
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
the existing `WowVoiceTalkingHead` directory and the two sound pack TOC files it will
replace. It then synchronizes `src/` into `AddOns\WowVoiceTalkingHead`, removing old files
that are no longer present in the source. Existing IDE workspace state under
the installed addon's `.idea` directory is preserved.

The complete Classic audio and its two TOCs are copied into `WowVoiceSounds`;
filtered supplemental audio is copied into `CatVoices`. Existing extra files in
the sound directories are preserved. The current `CatVoices` folder is also
backed up when present; the large Classic audio library is not backed up.
Other addons and `WTF` are not modified. Fully restart the game after deployment
so the client can discover newly added sounds.

To roll back, restore `WowVoiceTalkingHead`, the two TOC files and, if present, `CatVoices`
from the appropriate backup directory. Its `destination.txt` records the AddOns
destination. Restore older Classic audio from its original archive if needed.

## Release package

Package creates a ZIP archive, using the version from `src/WowVoiceTalkingHead.toc`:

```text
artifacts/WoWVoice/WowVoiceTalkingHead-<version>.zip
```

The ZIP contains:

```text
WowVoiceTalkingHead/              Complete addon from src/
WowVoiceSounds/                   Complete Classic audio and two Forever TOCs
CatVoices/                       Additional audio, metadata and attribution
README.txt                        Plain-text Russian user guide from USER_README.md
```

Tests, development tools, IDE settings, backups and internal manifests are excluded.
Maintain the installation and usage instructions in [USER_README.md](../USER_README.md)
in Russian; the repository README presents the addon to players. This document contains development details.

The bundle includes 10,891 Classic recordings and 1,497 supplemental recordings
from CatQuest_Voices 0.2.0 for 703 additional quests (702 descriptions and 433
turn-ins, including gender variants). Filtering excludes an entire CatQuest quest if any section of that
quest exists in the Classic duration index. CatQuest itself is not required.
`ForeverAudio.lua` supplies the additional filenames and exact durations read
from each OGG stream. Runtime selection also gives Classic entries priority.
The import manifest and SHA-256 hashes are retained in
`docs/internal/forever-audio-manifest.json`, outside the release. The supplied
CatQuest pack's loaded Lua index takes priority. JSON-only entries are recovered
only when they contain a turn-in without a description, which the upstream Lua
index omits (quest 99080 in 0.2.0). Every referenced OGG must exist and pass stream
validation before outputs are replaced. Such quests get completion playback but
no description replay button; missing sections remain silent. The manifest records
the recovered IDs and reads the source version from its TOC.
Some Forever turn-ins use temporary translations from English and may differ
from the Russian client text, as documented by CatQuest's author.
Source credit is preserved in `CatVoices/NOTICE.txt` and the user guide:
CatQuest and CatQuest_Voices are by [Cathey](https://t.me/catheyco) (daniilcathey).

## Optional CatQuest coexistence

Core.lua temporarily suppresses CatQuest 0.2.0's `autoDetail`, `autoProgress`
and `autoComplete` while WowVoice is enabled. The `readAfterAccept` path also
checks `autoDetail`, so it cannot enqueue a duplicate reading. CatQuest retains
books, location lore, NPC greetings/gossip, manual reading, UI and history.
The separate Story modules are commented out in CatQuest's own 0.2.0 TOC.

This uses CatQuest's initialized settings table, with no required/optional
TOC dependency, private namespace access or upstream file edits. A late
CatQuest ADDON_LOADED event defers synchronization until its handler finishes;
PLAYER_LOGIN also synchronizes. `/wv off` and PLAYER_LOGOUT restore the original
flags before serialization; `/wv on` captures and suppresses them again. Manual
changes away from the temporary false value are preserved on restoration.
CatQuest settings remain editable: manually re-enabling its quest autoplay can
allow simultaneous playback until the next takeover/reload. Manual reading is
independent and is not stopped when WowVoice starts. `/wv diag` reports takeover.

Audio packs remain independent. WowVoice does not read CatQuest_Voices at runtime,
and CatQuest does not use WowVoiceSounds/CatVoices. Either addon works alone.
Tests cover absence, late loading, repeated initialization, enabled/disabled
transitions, restored saves, independent book/lore preferences and database changes.

Quest dialog and journal read buttons are hidden for the same interval. Discovery
is limited to QuestFrame and modern/legacy journal containers: CatQuest's exposed
catQuestButton reference and direct children with the exact CatQuest_Toggle or
CatQuest_ReadQuestLog click handler. Text labels are never used as identity.
ItemTextFrame and GossipFrame are excluded. Each button's IsShown flag is captured
once and restored on release, including originally hidden buttons. OnShow hooks
keep suppressed buttons hidden without replacing their scripts; those hooks are
inert after release. Parent OnShow and deferred PLAYER_LOGIN/ADDON_LOADED scans
cover both initialization orders and a lazily loaded journal. Only a few known
containers are scanned; there is no frame enumeration or periodic polling.

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
