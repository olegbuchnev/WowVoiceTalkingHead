# CatQuest 0.5.0 metadata migration — 2026-10-09

Imported from the locally installed CatQuest and CatQuest_Voices 0.5.0.
Upstream Lua tables were parsed as data; upstream code and sound files were not modified.

| Data | Imported |
| --- | ---: |
| Quests with audio | 3,077 |
| Descriptions / turn-ins | 3,017 / 2,850 |
| OGG files with SHA-256 and measured duration | 7,715 |
| Quests with transcripts | 3,017 |
| Description / turn-in transcripts | 3,017 / 2,790 |
| Text variants | 7,642 |
| NPC records | 2,364 |
| Quest-giver / finisher mappings | 3,765 / 4,042 |
| Quests shared with Classic / unique to CatQuest | 2,308 / 769 |
| Combined quests across both audio libraries | 4,974 |

Compared with 0.4.0: 951 added quests, none removed; 2,538 added audio filenames,
4,755 changed files with existing names, and 136 filenames no longer referenced.
420 previously available transcript sections changed. These file counts compare
indexed recordings, not unrelated or stale files left in the installed directory.

60 turn-ins without descriptions are present only in index.json. The importer
recovers their audio for this audited version, but the source supplies no transcripts
for them. Quest 16 is a regression example. Quest 99080, formerly JSON-only, now
has its own live description, completion and text. Quest 86576 gained completion audio.
Missing NPC mappings are recorded as upstream gaps, not filled with guessed identities.

The post-import audit found no mismatches in audio metadata, hashes, measured
durations, available transcripts or NPC tables. Resolver verification for both
sexes found 5,867 sections each, all with measured timing; no missing/invalid OGGs
or short timers. Before import, 5,807 live sections used approximate timing, with
up to 4.789417 seconds of extra time (1166_m.ogg).

Reproduce using installed source directories:

```text
node tools/import-forever-audio.js <CatQuest_Voices directory>
node tools/import-catquest-speakers.js <CatQuest directory>
node tools/audit-catquest.js <CatQuest directory> <CatQuest_Voices directory>
node tools/check-catquest-compatibility.js <CatQuest_Voices directory>
```

Generated runtime files: CatQuestAudio.lua, QuestTexts.lua, CatQuestSpeakers.lua.
The tracked forever-audio-manifest.json contains every indexed file's hash and
duration. Local audit and delta reports are in artifacts/review/catquest-0.5.0-*;
the previous metadata snapshot is in artifacts/review/catquest-0.4.0-before-0.5.0.

CatQuest 0.5.0 retains autoDetail/autoComplete, readAfterAccept's autoDetail check,
CatQuest_Toggle and CatQuest_ReadQuestLog. The existing automatic-playback takeover
and quest-window/journal button detection still match those entry points. The new
private tracker icon handler is outside that suppression. On 2026-10-09 the user
checked both the standard interface and EllesmereUI and reported no visible
conflict. No tracker suppression change was needed for this release.

Future-version fixtures now use 0.6.0, so the newly audited 0.5.0 still exercises
exact timing and the simulated next update exercises fallback behavior.
