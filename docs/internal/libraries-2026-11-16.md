# CatQuest 1.2.4 / Voices 1.4.0

Imported from the configured Forever installation on 2026-11-16. Pre-import
working-tree metadata is preserved in `artifacts/review/libraries-20261116/before/`.
External Lua was parsed as data; no external addon files were changed or OGG
recordings copied into the project.

CatQuest Voices now has 5,575 quests and 12,946 files: 4,911 descriptions and
4,819 endings. Compared with the previous imported snapshot, 118 files were
added, 19 changed by SHA-256, and two removed. The removed male/female endings
for quest 79358 are replaced by one shared recording. Combined texts cover
5,617 quests: 4,920 descriptions, 19 progress sections, 4,936 endings and
12,977 variants. No historical CatQuest transcript fallback is needed.

Quest Pins was updated to commit `5f133bb963f12a4af71d2dc7cc4e0bc8fc25a8b8`:
QuestieDB-Forever contract 4, 5,914 quests and 5,652 turn-ins. A fresh CheckSources
confirmed this snapshot current. The shared database contains 3,007 NPCs,
5,747 giver entries and 5,699 finisher entries. Protected exclusions decrease
from 148 to 130; source conflicts from 604 to 568. No appearance conflicts.

The classification audit covers 96 new or changed NPC records. No previously
known race was lost or replaced. Exact source metadata fills missing fields;
the existing ancient classification applies to NPCs 216289 and 254674 through
their own CatQuest voice labels. There are 69 changed records with unresolved
race or sex; none appear in the voting catalogue. Unknown fields remain unknown.
The detailed report includes source rows, previous/current values and quest
roles: `artifacts/review/libraries-20261116/classification.json`. Examples for
in-game review: NPC 2614 (quests 98109/97986), 4604 (97000), 9273 (94315).
No new classification rules or ranking groups were introduced; 38 groups remain.

The missing-appearance lookup stopped on HTTP 403 for NPC 13085 and applied
no supplements. Existing missing appearances retain the scroll fallback.

The voting catalogue retains 4,190 comparisons and 12,361 audio identities.
Nine new recording identities replace previous revisions, ten previously
unknown NPC cards gain speakers, and quest 79361 has updated text. Unchanged
audio identities retain their published paths. Existing votes remain associated
with their original comparison identities.

The update adjusts the CatQuest runtime regression's expected imported version
to 1.4.0. Release history and the addon release version are unchanged. In-game
validation of this update remains manual.

## Validation and publication

The full Test task passed. The CatQuest audit verified all 12,946 external
files by SHA-256; all 19,684 male/female resolver cases have verified timers,
with no missing/invalid files or short timers. Wayfarer speaker metadata and
all 9,917 Classic recordings match their saved snapshots. Audio preload tests,
the API Docker build/tests and portrait-pack checks passed. All 382 optimized
models are verified, with no unsupported files. Changed portraits 92434,
93949, 96222 and 99143 passed rest/Talk/return pose comparisons.

The complete offline model pass finished with `partial=false`: 1,436/1,437
ready, retaining only the documented camera failure for display 146706,
quest 97290. Preparation reused all 1,436 usable portraits; no additional
model assets were transferred. Evidence: `artifacts/voice-vote-model-cache/verify-report.json`.

The site catalogue and rebuilt API were published; the web image is unchanged.
Nine audio files were streamed directly from the installed libraries to
hash-specific server paths. All 1,465 votes and 1,349 existing comparison rows
were preserved; SQLite integrity, schema and service health checks passed.
Backup: `/srv/talkinghead/backups/libraries-20261116-20261116-103007`.
Deployment evidence: `artifacts/voice-vote-deploy/updates/libraries-20261116/`.
Rollback restores the backed-up catalogue/model manifests and previous API
image while retaining the live database and added audio.

Final built-in ranking: `2026-11-16T10:30:47.694595100Z`, 38 groups. Ranking
validation passed and the addon was installed in Forever. All 46 non-TOC
files match source bytes, including BuiltinRanking.lua; local QueueLab entries
were retained. Addon backup: `backups/20261116-123111-870-b9fad2`.
No CurseForge/GitHub release or release ZIP was created.

Public Firefox verification passed after transient DNS/connection errors:
exact catalogue equality, audio SHA-256/playback, optimized M2/SKEL hashes and
immutable cache headers, and five ready portraits (92434, 93949, 96222, 99143,
1116). Voting requests were intercepted; no production test ballots were sent.
Evidence: `artifacts/review/libraries-20261116-public.json`.
