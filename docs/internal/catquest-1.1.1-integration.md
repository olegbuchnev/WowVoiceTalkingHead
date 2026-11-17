# CatQuest 1.1.1: complete player suppression

User request, 2026-11-12: suppress all CatQuest playback, including manual
playback, instead of the previous book/lore/world exceptions. Wayfarer policy
is unchanged. CatQuest Voices remains at 1.3.0 and the current site catalogue,
texts, NPC cards, recording identities and hashes match the published snapshot.
No website deployment is needed. Quest Pins remains current at df9964be5af8.

The screenshot shows CatQuest's News.lua window. The dungeon master is the
Dungeon.lua narrator: intros, encounter starts, boss-death endings and quest
follow-ups, using Books & Lore recordings. CatQuest 1.1.1 changes the boss-kill
trigger and combat ducking; it does not add quest voice recordings.

The integration guards Speak/Enqueue/queue playback, BridgeSpeak, world queue
consumption, world diagnostic playback, SelfTest, private playback slash commands,
CatQuest_Toggle, dungeon/lore commands, news and welcome functions. Shared game
sound APIs and voice pack data are not modified. Existing player/queue/world
sessions are stopped once on takeover. Settings including the implicit enabled
DungeonMaster default are temporarily suppressed. The update does not mark news
as read. Owned hooks and preferences are restored on disable/logout; later
third-party replacements are retained. Early/late load and repeated refreshes
are covered by regression fixtures, alongside direct playback by TalkingHead Ru.

Evidence: `tests/validate-catquest-silence.js`, updated CatQuest runtime scenarios,
and logs under `artifacts/review/catquest-111/`. No external Lua was executed and
no external addon or OGG file was modified. The user confirmed after /reload on 2026-11-12 that CatQuest no longer shows
the popup or plays independently, and its recordings work through TalkingHead Ru.

Installed in Forever after validation. All Lua/runtime scenarios passed; the
packaging gate initially misidentified the blocked upstream test command as our
own developer command. The blacklist now uses a table, and the fixture closes
its ZIP even when that assertion fails. The packaging/deployment pipeline and
remaining release-statistics/Pins tests passed on their final runs. All 46
installed non-TOC files match source bytes; local QueueLab is preserved.
Backup: `backups/20261112-120318-659-88caa9`.
Built-in ranking: `2026-11-12T10:00:15.895472368Z`, 38 groups.
