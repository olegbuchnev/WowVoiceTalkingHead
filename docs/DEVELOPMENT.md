# Development guide

WowVoice TalkingHead is a Forever Beta build based on WowVoice, with talking
heads and quest playback controls. This repository keeps its development sources
outside the live World of Warcraft installation. Runtime addon files live under
`src/`; tests and build tools stay outside that directory and are never deployed.
The runtime code is based on the Midnight version, while `Index.lua`,
`Durations.lua` and the primary OGG audio come from the Russian Classic sound pack.
An optional, separately installed CatQuest_Voices supplies quests absent from
that pack and alternate recordings of shared quests. No CatQuest audio is copied
or redistributed. Shared recordings use the source selected in options (WowVoice by default).
This build targets **WoW Forever Beta, Interface 16001**.

The in-game title is **WowVoice TalkingHead**, and its addon ID and folder are
`WowVoiceTalkingHead`. The command `/thead` opens settings; `/thead help` lists commands.
The original `/wv` and `/wowvoice` aliases are not registered; the bundled audio folder is `WowVoiceSounds`.
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
tests/                           Lua tests with WoW API mocks and pipeline checks
config/build.env.local.ps1      Local environment variables (gitignored)
build.ps1 / build.cmd             Validate, test, deploy and package pipeline
USER_README.md                   Russian user guide; converted to README.txt for packaging
artifacts/WoWVoice/              Latest full and addon-only ZIPs; stable cloud sync folder (gitignored)
backups/                         Backups created before deployment (gitignored)
```

Edit `src/`, then run Deploy. The installed `AddOns\WowVoiceTalkingHead` directory is a
deployment destination, not the project's source directory. OGG files are local
build inputs (gitignored) and are included in the complete release archive.
Populate Classic audio with `tools/import-classic-audio.js <WowVoiceSounds directory>`.
`tools/import-forever-audio.js <CatQuest_Voices directory>` reads external streams
to generate compatibility metadata, transcripts and hashes only; it never copies audio.
Both tools require Node.js and `npm ci`.

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
and can be built without a local `soundpack/` directory.
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

The player website is hosted at https://olegbuchnev.github.io/WowVoiceTalkingHead/.
Run `npm run build:site` (Node.js 24) to generate `artifacts/site/` locally.
`tools/build-site.mjs` builds the landing page from README.md and the full guide
from USER_README.md; download URLs and screenshots come from README.md as well.
Keep its named sections (Installation, Features, Settings, CatQuest compatibility,
and Credits, using their current Russian headings), or update the generator when
renaming them. Presentation lives in `site/style.css`.

`.github/workflows/pages.yml` publishes only the generated website on changes to
its inputs on main. GitHub Pages uses the GitHub Actions publishing source.
Do not upload the repository root, audio inputs, or release ZIPs to Pages.
Updating the release links in README.md also updates the website automatically.
Each download button shows its own release version and artifact update date.
The site builder queries GitHub Releases for the exact URLs in README.md, using
the later of the release publication and asset update timestamps (displayed in UTC).
These dates describe the archives, not when their audio recordings last changed.
The build needs network access; `GITHUB_TOKEN` is optional locally and supplied by
Actions. Missing/unpublished assets or API failures stop publication, preserving
the existing site rather than displaying guessed dates. Updating README download
links after publication refreshes this metadata automatically. After replacing an
asset on an existing release, run the Publish website workflow manually if no
README change follows.
The full-download card also shows the upstream WowVoice and Cathey audio versions,
using the same labels as the in-game options. The site reads sound TOCs from the
full download's release tag, not from main or a newer addon-only tag. It prefers
`X-Source-Version` and recognizes the exact legacy pack versions described below;
unknown source versions stop the build rather than publishing a guessed number.

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

For a local download report, run `stats.cmd` (or `stats.cmd -NoOpen` without
opening the browser). `tools/release-stats.ps1` reads the public GitHub API,
paginates releases and assets, and writes HTML, CSV and JSON to the gitignored
`artifacts/stats/` directory, outside the pCloud release sync folder. It needs no
token or extra dependencies. Run it again to refresh the snapshot. Counts cover
existing full and addon-only ZIP assets only, including repeated/test downloads; they do not measure
unique users, website clicks or pCloud downloads. The report stays local, while
the underlying public-repository counters remain public. No site analytics is added.

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

The default `/thead channel auto` selects the playback channel for each recording.
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
volume. `/thead volume 0..1` is an additional Dialog-relative multiplier in both paths
(default 1). NPC Dialog suppression applies to both playback paths,
unless `/thead duck off` is selected.

Changing the background preference does not restart or move the current voice;
the next recording uses the new preference. If background sound is disabled
during a Master recording, minimizing can still interrupt that recording.
`/thead channel sound` and `/thead channel music` retain their explicit overrides.
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

`/thead perf` reports session-local pending work, maximum slice duration, overruns,
errors, and per-job total/max step time. `/thead diag` includes the same report.
The measurements cover this queue, not total frame time or all other addons.
Regression tests verify budget sharing, combat behavior, idle shutdown, native
overrun reporting, and 100 inventory queries for 25 quests/100 slots (previously
2,500). These are controlled mocks, not an in-game FPS benchmark.

## Quest playback queue

`src/QuestQueue.lua` owns the gameplay queue; `src/QuestQueuePlayer.lua` renders
the grouped playlist and its layout preview. Both ship in the regular release.
The optional `/tt` harness under `dev/queue-lab/` uses the same runtime handlers
and is excluded from release archives. See [the harness guide](../dev/queue-lab/README.md).

An idle `QUEST_DETAIL` starts playback immediately. If playback is busy or paused,
the description is held as an offer and joins the waiting queue on `QUEST_ACCEPTED`.
Groups belong to the quest giver, including quests turned in to another NPC;
the talking head retains the actual speaker. Each quest keeps its stages together
in `a`, `p`, `c` order. Abandoning a quest removes its pending stages, while
`QUEST_TURNED_IN` distinguishes successful completion from abandonment.

Manual Play starts the earliest pending stage of the selected quest and replaces
the current line without discarding other waiting entries. Play-next moves the
whole quest after the remaining stages of the current quest. The head's Next
button skips one line; closing the head discards that line and pauses the rest.
Playlist quest deletion removes all stages of that quest, and Clear-all stops
queue playback and removes the queue. Journal, tracker and catalogue playback
replace the current line; the remaining queue continues afterward. Catalogue
playback does not change the saved audio-source preference.

Natural transitions use a 1-second gap between quests (0.7-second head fade,
then 0.3 seconds hidden) and a 0.4-second gap within one quest. Manual transitions
start immediately. The playlist scrolls to the top when the active record changes.

`WowVoiceQueueDB` is a per-character SavedVariable in all three TOCs. On
`PLAYER_LOGOUT`, real queue entries are serialized before playback is stopped;
lab records and layout samples are excluded. Restoration runs once on
`PLAYER_ENTERING_WORLD`, accepting elapsed times from zero up to, but excluding,
300 seconds. The current line restarts from the beginning; a paused queue stays
paused. A completed line waiting in the transition gap is not replayed.
There is no expiry during a continuous session. SavedVariables depend on the
client writing them at logout/reload; arbitrary crashes are not guaranteed saves.

Autoplay and descriptions-only preferences affect admission, not playback or
restoration of existing entries. The migration and flags are described below.
`tests/queue-session-scenarios.lua` covers migration, persistence and admission
changes; queue settings and harness scenarios cover controls and event handling.
Run `node tests/run.js` and `node tests/validate-queue-lab.js`. Packaging exclusion
of the harness is checked by `tests/pipeline.ps1`.

## Appearance

Quest descriptions play automatically by default. Disable
«При получении задания» in the «Воспроизведение» options section to opt out
(`WowVoiceDB.autoPlayAccept`). The one-time playlist migration
(`playlistAutoPlayApplied = 2`) enables `autoPlay`, `autoPlayAccept` and
`autoPlayTurnIn`, including saves with the earlier boolean migration marker.
Subsequent checkbox choices are preserved.
With autoplay disabled, quest giver and description capture still runs,
and manual replay from the journal or tracker remains available.
«При сдаче задания» independently controls all progress and completion
dialogue (`QUEST_PROGRESS` and `QUEST_COMPLETE`, sections `p` and `c`) for both
audio packs. `WowVoiceDB.autoPlayTurnIn` defaults to true. Neither preference
blocks manual description replay. Changing either
preference does not interrupt or start the current recording.
All autoplay switches and the descriptions-only filter govern new queue entries.
Already queued lines retain manual and automatic playback and session persistence
even when these switches are off. The master autoplay switch closes layout preview,
but does not stop audio or clear the existing queue.

The on-screen quest tracker has small replay arrows to the left of voiced quest
titles. They replay the description using
the current quest ID and leave the tracker layout unchanged. These controls are
always available for voiced quests; there is no separate visibility preference.

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
Questie controls share availability, playback and progress reminders
with the native controls. Visual placement still requires verification in-game.

For the exact reminder decision order, saved-state semantics and examples, see
[Алгоритм напоминаний об озвучке](QUEST_REMINDERS.md) (developer notes).
The silent gold glow around tracker buttons and the replay notification are
always available while the addon is enabled. Initialization removes the obsolete
button and reminder preferences, including saved opt-outs.
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
upward. A fresh appearance resets the offset.
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
including heard quests. The same animated
glow stays visible until preview stops, options close, or real
playback replaces the preview. Hidden tracker controls remain hidden.

`/thead remindertest [questID]` previews the same replay notification below
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
and restores parents and font animation modes before normal final layout. `/thead diag` reports
`Text scale preview: vertex` when this path was selected.
Portrait loading and camera updates explicitly disable native model blending;
player previews also pass `false` to `SetUnit`'s blend argument. This keeps reuse
of the same PlayerModel consistent across player tests and NPC playback. Speaker
capture/cache refresh requests arriving during a scale drag are coalesced and
applied after release/cancellation, so they cannot clear the frozen model mid-drag.
The last three drags retain a bounded, session-only diagnostic summary: camera
refreshes, viewport resizes (`view`), load/reload requests, show/hide events, zero-alpha writes, sampled
visibility/readiness, display changes, pause/blend state and playback completion.
Read it with `/run WowVoice:HeadScaleDiagnostics()` (also included in `/thead diag`).
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
Unsupported capture uses this same live fallback. `/thead diag` reports the last
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
bottom edge. Saved positions take priority; `/thead head reset` restores the default.
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
`PortraitCameraOverrides` allows individual model corrections; `/thead diag`
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
455 of the original 703 supplemental voiced quests (the 0.2.0 snapshot). It also marks 316 confirmed object or
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

`BUILD.local.md` is a tracked command guide without personal paths.
Copy `config/build.env.example.ps1` to `config/build.env.local.ps1` (gitignored)
and set the Forever Beta AddOns directory. The example uses a fictional path:

```powershell
$env:WOWVOICE_FOREVER_BETA_ADDONS = 'D:\ExampleWoW\_classic_beta_\Interface\AddOns'
```

Deploy and DeployAddon load this file automatically in the build process only.
Its assignments override inherited environment variables; without the file,
the inherited variable is used. Windows user/system environment settings are
not modified. Other tasks do not load or require the local environment file.
Repository paths are derived from the script location.

`ForeverBeta` is the only supported deployment target; PTR, Retail and All are
not supported. The old `config/deploy.targets.local.psd1` is no longer read
automatically. Explicit `-ConfigPath` still accepts the PSD1 format shown in
`config/deploy.targets.example.psd1` and bypasses the local environment file.
The destination must exist and end in
`_classic_beta_\Interface\AddOns`. Deployment rejects junctions and symlinks.

## Deployment and backups

### Local debug panel

`src/CatQuestSpeakers.lua` contains the complete CatQuest NPC database and quest
giver/finisher maps, imported as data by `tools/import-catquest-speakers.js`.
Its header records the upstream version and file SHA-256. Description portraits
use giver metadata only when the existing indexes lack an NPC; live captures,
item/object identities and explicit ambiguous-starter exclusions retain priority.
Imported identities stay transient. All packages carry this database.

Run `node tools/audit-catquest.js <CatQuest directory> <CatQuest_Voices directory>`
after imports. This read-only audit compares every NPC/giver/finisher record,
all subtitle variants, complete compatibility metadata and external file
hashes, including Classic overlaps. Any mismatch produces a nonzero exit code.
`upstreamGaps` lists absent upstream quest data separately;
books and zone lore are outside this quest database audit.

The public voice catalogue ships in every build through `src/Comparison.lua` and
`src/VoiceComparison.lua`, listed in all three TOCs. Open options and choose
«Послушать озвучку» in the «Выбор озвучки» section. The section uses the standard
heading/divider, smooth circle radio choices with centered clickable captions,
and a dedicated Blizzard help-i tooltip target. No tooltip overlays the heading or choices.
The catalogue replaces the settings content inside the same category.
The page has an «Озвучка заданий» heading, the quest ID field
with the ID range alongside and a Back button
beside the heading. Back or closing/reopening Settings returns to the main
view and preserves its scroll position. Back and closing Settings clear the catalogue filter and selection,
so returning shows the full catalogue from the top.
`/wvvoices` opens this view; `/wvdebug` remains an alias. The quest field uses coordinate-field styling.
The catalogue contains only quests with known description audio in the Classic
and CatQuest indexes. Typing filters these IDs by prefix, numerically
sorted in a grid spanning the page width (8 columns at normal width, up to 12).
The grid fills the remaining page width and height; all results remain available
through the scrollbar/mouse wheel. Only visible cells are pooled, so a broad
prefix does not create thousands of buttons. Each 52-pixel tile has the quest ID
and two fixed play slots: blue WowVoice on the left, orange CatQuest on the right.
A missing source recording leaves its slot empty. A known recording unavailable
in the installed packs is disabled and grey. A legend sits above the grid.
If CatQuest_Voices or its live index is not loaded, hide its buttons and legend,
exclude CatQuest-only quests, and show only the WowVoice count in the footer.
Late loading restores its catalogue and controls. A loaded but incompatible pack
still has disabled controls, matching the version warning in the options.
Clicking an icon immediately replaces
playback through our talking head, preserving the filter, results and scroll.
Only the clicked play button has a bright filled selection; tiles have no selection outline.
Selection follows both quest ID and source as cells are reused. Focus loss, Escape and
playback leave the grid visible; Escape only clears input focus. Empty input shows
the entire catalogue. Enter replays the entered ID; empty/invalid input is ignored.
`/wvdebug 179` opens it with a quest ID filled in. Playback uses the normal
audio transport without requiring the quest in the log. Comparison does not update
normal availability, source preferences or reminder cooldowns. Missing quest text or speaker metadata
uses the normal fallback. The reminder test still requires a visible tracked quest.

The extra stop, reminder, preview, logging and diagnostics buttons and their
page-specific handlers have been removed. Shared runtime commands remain available.
CatQuest previews use the same complete `src/CatQuestAudio.lua` index and resolver as
normal playback, including exact durations for both sexes and compatibility guards.
No separate comparison metadata or importer is required.
Only compatible external CatQuest_Voices can supply the CatQuest button.
The source version and live duration/voice/sex metadata must match. Failures disable
only the affected file in the comparison view. Normal playback retains its own policy.
Both release archive types include the catalogue. The old deployment flag `-LocalDebug`
is accepted as a no-op; ordinary deployment removes obsolete local panel/index files.

Before writing any files, Deploy creates `backups/<timestamp-id>/` containing
the existing `WowVoiceTalkingHead` directory and the two sound pack TOC files it will
replace. It then synchronizes `src/` into `AddOns\WowVoiceTalkingHead`, removing old files
that are no longer present in the source. Existing IDE workspace state under
the installed addon's `.idea` directory is preserved.

The complete Classic audio and its two TOCs are copied into WowVoiceSounds.
Existing extra files are preserved. CatVoices, CatQuest and CatQuest_Voices
are never changed by deployment. The large Classic audio library is not backed up.
Other addons and WTF are not modified. Fully restart after adding new sounds.
To roll back, restore WowVoiceTalkingHead and sound TOCs from the backup;
destination.txt records the target directory.

## Release package

The options header shows the addon version and the upstream audio pack versions,
read from each installed pack's `X-Source-Version` TOC metadata. Audio import tools
copy this field from the original TOC and preserve its filename in `X-Source-TOC`.
Classic imports prefer `WowVoiceSounds_Vanilla.toc` over the generic TOC; the
original Classic 1.15 archive has version 1.0.1 in that client-specific TOC and
0.1.0 in the generic one. All 10,891 bundled Classic recordings match that archive
byte-for-byte. Cathey's supplemental recordings come from CatQuest_Voices 0.2.2.

Older published packs without source metadata are recognized by their exact
adaptation versions (WowVoiceSounds 1.0.3-forever.1).
Unknown versions are not guessed by stripping suffixes. Labels use the installed
WowVoiceSounds and CatQuest_Voices packs, never the CatQuest player or the
latest online release. There is no separate combined database revision.

The website records verified upstream audio publication dates in
`site/audio-releases.json`, keyed by the upstream audio version. Each entry
includes the source archive URL and SHA-256. The full download card shows this
date; only the addon-only card shows the addon's update date. Repacking unchanged
audio must not advance its date. When importing a new audio version, verify its
source archive and add its publication date; an unknown version shows no guessed
date. The current Classic 1.0.1 archive was published on 2026-08-13 (GitHub asset
upload date), independently of the original v1.0 release's earlier creation date.

Package creates a ZIP archive, using the version from `src/WowVoiceTalkingHead.toc`:

```text
artifacts/WoWVoice/WowVoiceTalkingHead-<version>.zip
```

The ZIP contains:

```text
WowVoiceTalkingHead/              Complete addon from src/
WowVoiceSounds/                   Complete Classic audio and two Forever TOCs
README.txt                        Plain-text Russian user guide from USER_README.md
```

Tests, development tools, IDE settings, backups and internal manifests are excluded.
Maintain the installation and usage instructions in [USER_README.md](../USER_README.md)
in Russian; the repository README presents the addon to players. This document contains development details.

The bundle includes 10,891 Classic recordings. External CatQuest Voices 0.2.2
adds 738 quests (737 descriptions, 464 turn-ins, 1,678 files with gender variants).
The runtime index now includes the complete CatQuest library: 1,979 quests,
1,978 descriptions, 1,687 turn-ins and 4,895 files. Saved `sharedQuestVoice`
selects WowVoice (default) or CatQuest for overlapping recordings. Routing is
per section: a recording available from only one source uses that source.
Unavailable/incompatible CatQuest resets the saved preference to WowVoice.
Restoring the library enables selection again without automatically selecting CatQuest.
The options radio buttons are disabled with an explanatory tooltip in this case.
Changing preference invalidates availability caches without interrupting playback.
Catalogue A/B buttons use explicit sources independently of this preference.
CatQuest audio is read directly from CatQuest_Voices/Sounds/q; the legacy CatVoices
pack and ForeverAudio.lua are no longer used.
The import manifest and SHA-256 hashes are retained in
`docs/internal/forever-audio-manifest.json`, outside the release. The supplied
CatQuest pack's loaded Lua index takes priority. JSON-only entries are recovered
only when they contain a turn-in without a description, which the upstream Lua
index omits (quest 99080 in both 0.2.0 and 0.2.2). Every referenced OGG must exist and pass stream
validation before outputs are replaced. Such quests get completion playback but
no description replay button; missing sections remain silent. The manifest records
the recovered IDs and reads the source version from its TOC.
Some Forever turn-ins use temporary translations from English and may differ
from the Russian client text, as documented by CatQuest's author.
Source credit is preserved in generated metadata and the user guide:
CatQuest and CatQuest_Voices are by [Cathey](https://t.me/catheyco) (daniilcathey).

## Optional CatQuest coexistence

Core.lua temporarily suppresses CatQuest 0.2.0/0.2.2's `autoDetail`, `autoProgress`
and `autoComplete` while WowVoice is enabled. The `readAfterAccept` path also
checks `autoDetail`, so it cannot enqueue a duplicate reading. CatQuest retains
books, location lore, NPC greetings/gossip, manual reading, UI and history.
The separate Story modules are commented out in CatQuest's own 0.2.2 TOC.

This uses CatQuest's initialized settings table without private namespace access
or upstream file edits. WowVoice has optional TOC dependencies on the two audio
packs; the original CatQuest_Voices itself requires CatQuest. A late
CatQuest ADDON_LOADED event defers synchronization until its handler finishes;
PLAYER_LOGIN also synchronizes. `/thead off` and PLAYER_LOGOUT restore the original
flags before serialization; `/thead on` captures and suppresses them again. Manual
changes away from the temporary false value are preserved on restoration.
CatQuest settings remain editable: manually re-enabling its quest autoplay can
allow simultaneous playback until the next takeover/reload. Manual reading is
independent and is not stopped when WowVoice starts. `/thead diag` reports takeover.

AudioSources.lua resolves supplemental recordings independently of either player's UI.
Only a loaded, supported CatQuest_Voices can supply supplemental recordings.
Without it, supplemental quests play no sound and show no head. Classic remains
independent. An old manually installed CatVoices is ignored. The old bundled/external
selector is removed; the new preference only selects overlapping recordings. Old `audioSource` saves
are discarded on load. `/thead source` (including old arguments) reports status
without changing it; `/thead diag` gives detailed diagnostics. The options header
shows the active source version as "Озвучка CatQuest". Classic remains unchanged.
CatQuest does not use our packs.

The importer also generates src/CatQuestAudio.lua for the exact external 0.2.2
release, including per-file durations and JSON-only recovery. At runtime the
external TOC version and each live entry's duration, gender flag and voice must
match this metadata. Unknown releases or changed entries are unavailable, not
played with stale timings. These checks cannot detect an OGG replaced under the
same version and identical Lua metadata: only the offline importer verifies hashes.
ADDON_LOADED/PLAYER_LOGIN refresh source-dependent UI and failure caches without
interrupting active sound. Availability failures are keyed by path, version and duration.
Tests cover absence, late loading, repeated initialization, enabled/disabled
transitions, restored saves, independent book/lore preferences and database changes.

All available quest transcripts are imported from CatQuest's `c.x/m/f` subtitle
sentences into `src/CatQuestTexts.lua`. Both text and audio metadata include
Classic overlaps. The three TOCs load the same standalone text
database in full and addon-only packages. Text lookup is independent of
installed audio sources and their versions, with variants selected by player
gender. `CatQuestAudio.lua` contains only audio compatibility metadata.

The talking head uses this database only when the playback context has no text;
captured/game journal text stays authoritative and fallback text is not saved
into character data. This includes debug playback outside the journal and
Classic playback without CatQuest installed. CatQuest's wording may differ from
Classic recordings or the game. Timing-based subtitle scrolling is unchanged;
only sentence text is imported here.

The 0.2.2 snapshot contains 1,978 quests, with 1,978 descriptions and 1,686 turn-ins
(4,893 text variants). These include 1,241 Classic quests. Recovered JSON-only
turn-in 99080 has no source transcript, so it retains the no-text message when
the game has not supplied text. Other quests absent from this text database
also retain their existing game/journal lookup. Import reports text coverage
separately in `forever-audio-manifest.json` so updates can be compared.

## Two release packages and website metadata

Package contains WowVoiceTalkingHead and WowVoiceSounds. PackageAddon contains
only WowVoiceTalkingHead. Both include the same text, NPC and compatibility data.
PackageLite was removed because it would now duplicate Package. Neither build
needs a local catvoices directory; existing legacy audio is not deleted automatically.

Pages shows two download cards with actual GitHub asset sizes, versions and dates.
A separate CurseForge link explains optional CatQuest Voices installation; the
supported version is read from CatQuestAudio.lua at the downloadable addon tag.
Historical lite archives remain identifiable in download statistics. No release
archive or public website is published by routine deployment.
