# WayfarerRU 1.1.0 / voice packs 3.3.0

Imported 2026-11-11 from the configured Forever AddOns directory. No Wayfarer
packs were present in the adjacent Retail installation. External Lua was parsed
as data; recordings were read directly without copying OGG into the repository.

## Compatibility

Wayfarer Radio automatic stories are now suppressed too, including taxi
chronicles (enabled upstream by default) and running radio. The integration
guards `Radio:Start` when `opts.auto` is set, before a session, audio or UI is
created. An existing automatic session is stopped on takeover; manual stories
remain available. Radio preferences and listening history are unchanged.
The guard is installed before login and on late addon loading; disabling
TalkingHead Ru or logging out restores the original method. All three TOCs
include Wayfarer_Radio as an optional dependency. Regression coverage includes
both automatic paths, active sessions, manual playback, late loading, repeated
refreshes, replacement APIs and restoration without overwriting other hooks.

The upstream core was renamed to WayfarerRU to avoid another addon named
Wayfarer. Both RegisterPack namespaces remain supported. All three TOCs,
availability, version hints, credits and reversible integration recognize the
new core. Disabled WayfarerRU does not fall back to controlling an unrelated
Wayfarer. Automatic playBarks and QUEST_ACCEPTED are suppressed and restored.
Packs.list, format 1, model v4 and quest audio paths remain compatible.

## Imported data

| Pack | Descriptions | Sections | Files | Added | Removed | Changed SHA-256 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Alliance | 1422 | 2898 | 3112 | 129 | 7 | 2963 |
| Horde | 1321 | 2686 | 2986 | 178 | 0 | 2782 |
| Shared | 1261 | 2611 | 3075 | 377 | 1 | 2678 |
| Total | 4004 | 8195 | 9173 | 684 | 8 | 8423 |

66 old files are unchanged. Different hashes do not prove different spoken
audio: PCM was not compared. All previous recording revisions remain in history.
Narrator has no quest audio; radio and world dialogue are outside this import.

Merged texts: 5195 quests, 4498 descriptions, 19 progress sections, 4787 endings,
12211 variants. CatQuest 1.2.0 retains its priority. Quest Pins is updated to
`d92a85cb4a796c0e9721fef01dc625ea75a54713`: contract 4, 5239 quests and 4953
turn-ins. Shared speakers: 5157 giver entries, 5075 finisher entries, 2673 NPCs.

## NPC classification

Existing race, sex and age categories are unchanged. Ten NPCs gained appearances
from exact Wayfarer NPC records. Five new NPCs retain unknown race/sex pending
in-game verification: 13448 (quest 7401), 14185 (7361), 14186 (7362), 14187 (7365),
14188 (7364). None participate in current voting comparisons. Cached ClassicPlus
metadata for new voting portraits agrees with the existing categories.
The ranking registry still contains 38 groups.

Missing-appearance lookup stopped on HTTP 403 for NPC 13085 (quests 96779,
96781-96783). No supplements were applied and no blocking was bypassed.
Unresolved appearances retain the standard scroll fallback.

## Validation and website

Verified hashes and sizes of 9173 files and 16390 Lua resolver cases, speaker
reproducibility and recording history. Added regressions cover the renamed
registration, playback, reversible suppression and unrelated-addon isolation.

Prepared 4190 comparisons and 12361 recordings: 12 added comparisons, seven
changed NPC cards and no changes to existing comparison texts. 3977 new audio
identities require transfer; unchanged identities preserve published paths.
Prepared portraits: 1435/1436, including 1431 reused and four new appearances.
The sole known fallback remains display 146706 / quest 97290 (no camera).
All 382 optimized model packs passed validation, with no unsupported packs.

Detailed evidence and the metadata snapshot before import are under
`artifacts/review/wayfarer-3.3.0/`. In-game checks remain outstanding.
No addon release was created.

## Completed deployment

The full offline verification completed: 1435/1436 ready, partial=false, with
only the known missing camera described above. The build Test task, audio
preload tests and all 382 portrait pack tests passed. Seventeen new model
dependencies and the API image were published with the catalogue. Public
Firefox verified catalogue equality, audio playback/hashes and five portraits,
including four newly supplied appearances; no production ballots were sent.
All 1367 existing votes and 1255 comparison rows were preserved.

Backup: `/srv/talkinghead/backups/wayfarer-330-20261111-20261111-023216`.
Final ranking export: `2026-11-11T02:33:16.075247569Z`, 38 groups. Installed
TalkingHead Ru 1.4.4-forever into Forever; all 46 non-TOC source files match.
The three TOCs retain only the configured four additional QueueLab entries.
Installed BuiltinRanking.lua is byte-identical to the source.
Local addon backup: `backups/20261111-043336-603-c6eb3d`.

Full model report: `artifacts/voice-vote-model-cache/verify-report.json`.
Publication evidence: `artifacts/voice-vote-deploy/updates/wayfarer-330-20261111/`.
