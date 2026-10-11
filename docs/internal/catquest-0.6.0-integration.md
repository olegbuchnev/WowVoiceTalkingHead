# CatQuest Voices 0.6.0 migration — 2026-10-11

Imported metadata and transcripts from installed CatQuest_Voices 0.6.0.
CatQuest itself was already at 0.6.0; its NPC data matches the prior import.
External Lua tables were parsed as data. Audio is read directly from installed
libraries; no voice files are copied into the project or deployment.

| Data | Imported |
| --- | ---: |
| Quests with audio | 3,077 |
| Descriptions / turn-ins | 3,017 / 2,850 |
| OGG files with SHA-256 and measured duration | 7,774 |
| CatQuest transcript sections / variants | 5,807 / 7,701 |
| Merged text quests / variants, including Wayfarer | 3,981 / 9,465 |
| Unified NPC records | 2,539 |
| Unified giver / finisher entries | 4,672 / 4,205 |

Compared with Voices 0.5.0: 136 added filenames, 77 removed filenames,
4,938 changed files with existing names, and 2,700 unchanged files. Counts cover
indexed recordings, not unrelated files remaining in the external directory.
The number of quests and audio sections is unchanged. Audio metadata changed
for 3,753 sections; merged text changed for 649 sections. No text sections were
added or removed. Quest 25 completion now has separate male/female recordings.

The 60 JSON-only turn-ins are still recovered only for this audited version;
their source contains no transcripts. Shared NPC data and source priority are
unchanged. Installed Wayfarer NPC data matches the imported snapshot.
Forever Quest Pins was checked independently: Database/ForeverQuests.lua is
current at commit `ce1da1b14290645eb67a9f9bf373c2088713efe3`.

The CatQuest audit found no mismatches in NPC data, available transcripts,
audio metadata, hashes or measured durations. The actual resolver verified
5,867 sections for each sex, all with measured timing: no missing/invalid OGGs,
short timers, estimates or blocked sections.

The installed CatQuest 0.6.0 code retains autoDetail/autoComplete,
readAfterAccept's autoDetail check, CatQuest_Toggle and CatQuest_ReadQuestLog.
No integration changes are required for those entry points.

Regression fixtures use real 0.6.0 recordings, including quest 25's new completion
variants; future-update scenarios and the development lab now simulate 0.7.0.
The Wayfarer module test returns to the options page before hovering its cards,
matching the visibility guard added for the cursor fix.

Generated files: src/CatQuestAudio.lua, src/QuestTexts.lua,
docs/internal/forever-audio-manifest.json and quest-texts-manifest.json.
Local metadata snapshot and audit/delta/compatibility reports are under
artifacts/review/catquest-0.6.0-*. These contain metadata only.

Reproduce with the installed libraries:

```text
node tools/import-forever-audio.js <CatQuest_Voices>
node tools/audit-catquest.js <CatQuest> <CatQuest_Voices>
node tools/check-catquest-compatibility.js <CatQuest_Voices>
node tools/generate-speakers.js --check
node tools/import-wayfarer-speakers.js <AddOns> --check
build.cmd -Task CheckSources
build.cmd -Task Test
```

All checks above passed. The complete Test task also passed archive/deployment,
release-statistics and Pins-update regression checks. The runtime was deployed
to the configured Forever Beta installation; generated audio/text/NPC metadata,
camera, portrait and options files match the source SHA-256 hashes.

In-game playback after this migration remains to be checked after `/reload`:
CatQuest description/completion playback, gender variants, head/queue timing
and absence of duplicate playback. The user's confirmation of child portrait
framing on quests 1479 and 3741 is recorded separately in the camera checklist.
