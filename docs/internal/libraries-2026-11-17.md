# CatQuest / Voices 2.0.0 and EllesmereUI tracker integration

Imported on 2026-11-17 from the configured Forever installation. The working
tree baseline is saved in `artifacts/review/libraries-20261117/before/`.
External Lua is parsed as data. External addons and audio files are unchanged.

Voices 2.0 appends a pack-contract table after its quest table. The importer
previously selected the last table and therefore saw only JSON-only endings.
The shared parser now prefers the exact `CatQuestVoicePack.quests` assignment;
a regression includes trailing contract/foreign tables and executable Lua
that must never run. The incomplete local trial was replaced before deployment,
and audio/text histories were restored to their pre-import baseline before
the corrected import.

The complete pack retains 5,575 quests and 12,946 recordings: 4,911 descriptions
and 4,819 endings. No files were added or removed; 1,587 SHA-256 hashes changed.
All 19,684 male/female resolver cases use verified timings, with no missing,
invalid or prematurely stopped files. Texts retain 5,617 merged quests,
4,920 descriptions, 19 progress sections and 4,936 endings.

Quest Pins was updated to `ec8d908c9ffdb7c6aeb1853781f1ce585d345c31`, contract 4:
5,922 quests and 5,669 turn-ins. Shared metadata has 3,011 NPCs, 5,751 giver
entries and 5,716 finisher entries. Four new NPC records remain unknown:
12024 (finisher 94273), 255305 (giver 93551), 257437 (finisher 94280), and
270919 (finisher 94270). Their categories require source or in-game evidence;
none participates in voting. No existing race/sex/age was changed or lost.
Detailed source/role evidence is in `classification.json` under the review folder.
The missing-appearance lookup again stopped on HTTP 403 for NPC 13085 and
applied no supplements. No block was bypassed.

The website retains 4,190 comparisons, 12,361 recording identities and 38 groups.
It receives 537 changed description recordings and three text corrections;
NPC cards are unchanged. Unchanged audio identities retain their published paths.

## EllesmereUI fix

CatQuest now draws its speakers through EllesmereUI's public row-provider API.
Blizzard/Questie block scans did not see the buttons inside sibling provider
slots. TalkingHead Ru now checks those slots from its existing row callback,
including after providers registered later. Matching requires the current
quest ID, CatQuest speaker atlas and a click handler. Later Show calls stay
suppressed. Hidden/recycled rows cannot regain stale icons on disable; live
icons are restored on disable/logout. Own playback buttons and native controls
remain unchanged. Tests cover both callback orders, recycled rows, hidden
parents, unrelated buttons, deferred scans and restoration, including ruRU,
enUS and enGB. In-game confirmation remains manual.

The imported-version regression was updated to 2.0.0. The local A/B playback
fixture now uses the actual 2.0 voice labels and measured durations for quests
179, 6 and 98246; the male/female recordings of quest 6 have independent timers.
Historical release notes
and the addon release version are unchanged; this task creates no release ZIP.

## Validation and completed deployment

The full Test task passed after the fixture update. Audio/text importer and
history regressions passed, as did CatQuest compatibility/audit, the Wayfarer
speaker check and verification of all 9,917 Classic audio files. Quest Pins
was rechecked and is current. Source conflicts remain at 568, protected
exclusions at 130, and appearance conflicts at zero.

Audio preloading tests, the API build/tests and all 382 portrait packs passed.
Preparation reused 1,436 portraits; the complete offline pass finished with
`partial=false`, 1,436/1,437 ready. Only the existing camera failure for quest
97290/display 146706 remains. No new model files were needed.
Report: `artifacts/voice-vote-model-cache/verify-report.json`.

The API and catalogue were published after transferring 537 recordings directly
from installed libraries to hash-specific server paths. All 1,474 votes and
1,358 existing comparison records were preserved; SQLite integrity, schema 4
and service health passed. The web image is unchanged. Backup:
`/srv/talkinghead/backups/libraries-20261117-20261117-190507`.
Evidence: `artifacts/voice-vote-deploy/updates/libraries-20261117/`.
Rollback restores the previous catalogues/model manifests and API image while
preserving the live database and added audio.

Public Firefox checks passed: exact catalogue equality, audio hashes/playback,
optimized M2/SKEL hashes and immutable caching, and ready portraits for 92434,
93949, 96222, 99143 and 1116. No production test votes were submitted.
Report: `artifacts/review/libraries-20261117-public.json`.

Final built-in ranking: `2026-11-17T19:06:13.976433279Z`, 38 groups. Its validation
passed and the addon was installed in Forever, preserving local QueueLab entries.
All 46 non-TOC files, including Core.lua, Tracker.lua and BuiltinRanking.lua,
match source bytes. Final addon backup: `backups/20261117-210637-216-c90418`.
In-game confirmation of the EllesmereUI fix remains manual after `/reload`.
