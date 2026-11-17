# CatQuest / WayfarerRU 1.2.1 — 2026-11-15

Scope: installed core addon compatibility and automatic welcome/update windows;
voice packs were not imported. External addon Lua was read as data, not executed.

CatQuest retains `ShowWelcome`, `ShowWelcomeOnce`, `ShowNews`, `NewsCheck` and
`NewsMarkSeen`, including the delayed login and post-combat paths. The redesigned
windows still use `CatQuestWelcome` and `CatQuestNewsFrame`. The new appearance
page (`HeadLookOpen`) is opened manually from their buttons or the hub, not by
a separate login callback. Existing guards cover the automatic windows and
preserve unread news and the welcome marker. No suppression change is needed.

WayfarerRU 1.2.1 replaces Blizzard StaticPopup dialogs with `Util.Ask`, using a
private dialog and question queue. Its only initial question callers remain
`QuestZones:Offer` and `Zones:OfferKnown`. Existing guards intercept both before
the first-run flags or dialog queue are changed. The pack registration API and
`Packs.list` remain compatible. Updated the audited core version in
`WayfarerSource.lua` to 1.2.1; the screenshot warning was our version mismatch
notice, not an upstream welcome window. Unknown future releases still warn.

Separate data updates discovered during this audit, not imported:

- CatQuest `NpcData.lua` differs from the imported 1.1.1 snapshot: 18 NPC records,
  91 quest-giver entries and 16 finisher entries differ (including additions or
  removals). Details: `artifacts/review/core-121-npc-delta.json`.
- Fresh CheckSources result: Forever Quest Pins changed from `97aea10280c1`
  to `5f133bb963f12a4af71d2dc7cc4e0bc8fc25a8b8` (2026-11-14).

These require the normal metadata import, NPC classification and affected site
catalogue workflow; this core/window audit does not certify their freshness.
The user's in-game check found no visible regression; this audit does not claim
an additional interactive game test.

Validation: full `build.cmd -Task Test` passed; Wayfarer file/resolver audit
verified 9,173 files and 16,390 resolver cases. CatQuest Voices 1.3.0 compatibility
check passed with 9,756 verified entries for each player sex and no missing or
invalid files. Logs: `artifacts/review/core-121-tests.log` and
`artifacts/review/core-121-catquest.log`.

Installed the core version marker update with `DeployAddon -Target Forever`;
installed `WayfarerSource.lua` matches the source hash. No release ZIP was made.
Reload the game interface to refresh the compatibility notice.
