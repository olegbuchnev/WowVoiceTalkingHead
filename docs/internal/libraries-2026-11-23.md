# CatQuest 2.0.4 / Voices 2.1.0 and Hyjal

Imported 2026-11-23 from the configured Forever installation. Baseline and
audit evidence: `artifacts/review/libraries-20261123/`. External addon Lua was parsed as data;
external addon files and recordings were not modified or copied into the project.

## Imported data

The pack now contains 5,729 quests and 13,356 OGG files: 5,065 descriptions
and 4,983 endings. Compared with Voices 2.0.0, exactly 154 descriptions and
164 endings were added, matching the author's Hyjal 2.1.0 news. The author
also lists eleven incoming quests and three unvoiced Oldenwood crafting quests
whose completion text is still missing; these are release claims, not an
independent in-game completeness check. File delta: 411 added, one removed,
31 changed SHA-256 hashes. A changed hash does not by itself prove rerecording.
Merged texts contain 5,771 quests: 5,074 descriptions, 19 progress sections,
5,100 endings. No historical text fallback was needed.

Quest Pins was refreshed to `587983de1487f6f429029dd0d8765bc964f2af93`, contract 4:
6078 quests and 5902 NPC turn-ins.
The combined database contains 3,041 NPCs, 5,909 giver entries and 5,954
finisher entries. There are 591 source conflicts, 136 protected exclusions
and 0 appearance conflicts; the documented source priorities apply.

## NPC classification

Reviewed 103 new/changed NPC records against source tuples, stage-specific voice
labels and cached model evidence. 21 retain unknown fields; none appears
in the voting catalogue. No new classification rule was inferred from names or
generic voices. NPC 254674 lost the previous ancient/male inference because
its own descriptions now combine narrator (93404) and creature/ancient (93601).
The conservative classifier preserves uncertainty; check 93601, 93404 and
93594 in-game. The full evidence is in classification.json.

| NPC | Unknown-field quests (giver/finisher) |
| --- | --- |
| 11185 | 94333 (finishers) |
| 15175 | 94340 (finishers) |
| 214954 | 96379 (finishers) |
| 222530 | 82062 (finishers) |
| 248367 | 91754 (givers), 91755 (givers), 91770 (givers), 91754 (finishers), 91755 (finishers) |
| 249855 | 92070 (finishers) |
| 253097 | 92754 (finishers) |
| 253166 | 92817 (finishers) |
| 254357 | 93196 (finishers) |
| 254674 | 93601 (givers), 93404 (finishers), 93594 (finishers) |
| 254770 | 93430 (finishers) |
| 255678 | 93606 (finishers) |
| 260825 | 92147 (givers), 96252 (givers), 92147 (finishers), 96145 (finishers), 96252 (finishers), 96296 (finishers) |
| 262024 | 94323 (finishers) |
| 262033 | 94341 (finishers) |
| 262044 | 94360 (finishers) |
| 264089 | 90865 (givers), 90865 (finishers) |
| 265586 | 91923 (givers), 91923 (finishers) |
| 268168 | 96145 (givers) |
| 268743 | 96987 (finishers) |
| 270919 | 94270 (finishers) |

Missing-appearance lookup stopped on HTTP 403 for NPC 13085, applying zero
supplements. No block was bypassed. Existing catalogue fallbacks remain.

## Website changes and validation

The site retains 4,190 comparisons and 12,361 recordings; new Hyjal descriptions
have no second library recording to compare. There are 13 changed recording
identities and two changed texts (544, 545). Quests 8922, 8923 and 8929 now
have unknown speakers because the imported sources explicitly protect ambiguous
starters; no single NPC is guessed. Their previous votes remain historical.

All 13,356 OGG files passed the CatQuest audit, with no audit errors. All 20,320
male/female resolver cases use verified durations, with zero blocked cases or
short timers. Wayfarer speaker and audio-history checks passed. All 382 portrait
packs passed parser and WebGL verification, with no unsupported models.
The full build Test task passed, including runtime behavior, all imported data,
release isolation and local deployment fixtures. The API image passed Maven
verification; audio preload tests passed.

## Completed publication and Forever deployment

Full offline validation completed with partial=false: 1,436/1,437 portraits
ready. The only failure is the previously documented missing camera for quest
97290/display 146706, retaining the existing scroll fallback. No new model
assets were needed. All 382 optimized packs are verified and installed.

Published 4,190 comparisons and 12,361 audio identities, including 13 changed
recordings streamed directly from the installed library. The 12,348 unchanged
identities retain their exact manifest entries. The API image was rebuilt with
the updated speaker registry; the web image is unchanged.

All 1540 votes and 1415 prior comparison rows were preserved. SQLite
integrity, schema 4, container mounts and health passed. Consistent database,
pending inbox, catalogue and model-manifest backup:
`/srv/talkinghead/backups/libraries-20261123-20261123-013745`.
Deployment evidence: `artifacts/voice-vote-deploy/updates/libraries-20261123/`.

Public Firefox checks passed after retrying a transient local DNS failure:
exact catalogue equality, audio hashes/playback, packed M2/SKEL hashes and
immutable caching, and ready portraits for 92434, 93949, 96222, 99143 and 1116.
No production test ballots were submitted. Public check evidence:
`artifacts/review/libraries-20261123-public.json`.

Final built-in ranking: `2026-11-23T01:38:28.254061666Z`, 38 groups. ExportAddonRanking,
bundling and ranking validation passed; TalkingHead Ru was deployed to Forever
with local QueueLab preserved. All 46 non-TOC files match source bytes, including
BuiltinRanking.lua. Addon backup: `backups/20261123-033851-529-80300b`.
In-game Hyjal playback remains a manual check after /reload. No release version
bump, release ZIP, tag or GitHub Pages publication was performed.

Rollback: restore the backed-up catalogues/model manifests and retag
`talkinghead-vote-server:before-libraries-20261123` to the configured API image,
then restart services while preserving the live votes database, pending inbox
and added audio files. Never replace new votes with the backup database.
