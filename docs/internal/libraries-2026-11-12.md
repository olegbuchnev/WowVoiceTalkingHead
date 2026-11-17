# CatQuest 1.1.0 / Voices 1.3.0 and WayfarerRU 1.1.1

Imported from the configured Forever installation on 2026-11-12. All external
Lua was parsed as data; voice recordings remain in the installed libraries.
The pre-import snapshot and detailed reports are in
`artifacts/review/libraries-20261112/`.

## Audio and texts

CatQuest Voices 1.3.0 contains 12,830 files for 5,574 quests, including 4,910
main descriptions and 4,738 endings. Compared by filename and SHA-256 with
1.2.0, 654 files were added; none were removed or changed. All 19,512 resolver
cases have measured timers, with no missing/invalid files or truncated timers.

WayfarerRU 1.1.1 retains RegisterPack, Packs.list and the reversible integration
APIs. The audited core version was updated. All 9,173 voice-pack files remain
identical to 3.3.0 imported on November 11; 16,390 resolver cases passed.
WowVoiceSounds remains unchanged: 9,917 measured recordings, 4,307 quests.

Merged texts cover 5,616 quests: 4,919 descriptions, 19 progress sections,
4,855 endings and 12,865 text variants. CatQuest transcripts are available
without historical fallback; 489 quest sections were added and no previous
text section was changed or lost.

## Speakers

Forever Quest Pins was updated to commit
`df9964be5af889859668eb2efc670b4a6cc7ce60`: QuestieDB-Forever contract 4,
5,682 quests and 5,104 turn-ins. The shared database now has 5,500 giver entries,
5,407 finisher entries and 2,894 NPCs.

The classification audit records 241 new or changed NPC records. Existing
categories were not replaced or lost. Exact CatQuest NPC data fills previously
unknown categories; 113 changed/new records still lack race or sex, and none
participate in the current voting catalogue. Unknown fields remain unknown.
Detailed IDs, quest roles, before/after values and CatQuest source rows are in
`classification.json`. Examples requiring in-game review: NPC 4883 / quest
98192, NPC 7955 / quests 7675, 7676, 97046, 97188, NPC 255829 / quests 94668,
95424, 95425, 95428. Unclassified NPCs without quest roles do not create groups.
The ranking registry remains at 38 groups. The 126 protected exclusions remain
unchanged; source conflicts increase from 495 to 530 and follow the established
priority rules. There are no appearance conflicts.

The missing-appearance lookup stopped on HTTP 403 for NPC 13085; no supplements
were applied and no blocking was bypassed. Existing missing portraits retain
the scroll fallback. In-game validation remains outstanding.

## Website preparation

The catalogue retains 4,190 comparisons and 12,361 recording identities. NPC
cards, texts and audio hashes are unchanged; only the CatQuest package version
changes to 1.3.0. Existing published audio paths are preserved. No OGG transfer
or model additions are needed. The API image includes the updated speaker
registry. The sole previously documented camera exception is display 146706,
quest 97290. Publication and final ranking details are recorded after validation.

## Initial Forever installation

The complete Test task passed. The updated addon was installed into Forever
before website publication at the user's request so in-game testing can start.
All 46 non-TOC files match source bytes; the TOCs retain the configured QueueLab
entries. Backup: `backups/20261112-095700-249-fbd09a`. The prior built-in ranking
is temporarily retained until the final website export.

## Completed publication and final installation

The full offline pass completed with partial=false: 1,435/1,436 ready, only
the known missing camera for quest 97290. All 382 existing portrait packs remain
verified; no model or audio files needed transferring. Audio-preload tests and
the API Docker build (including Maven verify) passed.

The website catalogue and updated API were published. All 1,402 votes and 1,290
existing comparison records were preserved. Backup:
`/srv/talkinghead/backups/libraries-20261112-20261112-080750`.
Public Firefox checks confirmed exact catalogue equality, audio hashes/playback,
five ready portraits and optimized model hashes. No production ballots were sent.

Final built-in ranking: `2026-11-12T08:08:52.019568808Z`, 38 groups. Ranking
validation passed; TalkingHead Ru 1.4.5-forever was installed again into Forever.
All 46 non-TOC files, including BuiltinRanking.lua, match source bytes. Local
QueueLab entries were retained. Final backup:
`backups/20261112-100914-711-42f7db`.

Evidence: `artifacts/voice-vote-deploy/updates/libraries-20261112/`,
`artifacts/review/libraries-20261112-public.json`, and the full model report
`artifacts/voice-vote-model-cache/verify-report.json`.
No CurseForge/GitHub publication or release archive was created.
