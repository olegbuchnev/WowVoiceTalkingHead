# Timeweb Cloud deployment

## Dragon categories and cameras (deployed 2026-10-17)

Deployed the website changes in `b13cf49` using
`talkinghead-vote-server:dragons-20261017` and
`talkinghead-vote-web:dragons-20261017`. Both services are healthy. Five NPCs now
belong to `dragon/male`, affecting 16 catalogue comparisons. Itharius, Jeziba
and Haleh retain their verified blood elf appearances. The export contains
39 populated groups, including `dragon/male`; there is no empty `dragon/female`.
Emberstrife uses distance 2.8, y -0.12, z -0.24; Awbee uses 1.5, -0.04, 0.

The stopped SQLite/inbox/catalogue backup is
`/srv/talkinghead/backups/dragons-20261017-090041`. All 781 active ballots and
788 comparison rows were preserved, including historical weights. Only their
current-layer classification can change when the speaker metadata changes.
SQLite integrity, volume mounts and unchanged audio/model manifests passed.
Rollback images are tagged `before-dragons-20261017`; restore the previous
catalogues and image tags together, retaining the live schema-4 database.

The full offline pass completed with 1440 of 1441 portraits ready. The existing
fallback for display 146706 (quest 97290, model without a portrait camera)
remains; there were no new failures. Docker build gates and the complete tests
from an isolated checkout of the committed sources passed. Public browser checks
verified portraits and every available voice for five dragons and the three
blood elf exceptions without submitting production ballots. The import dialog
passed five viewport checks, stable copy geometry and checksum verification;
the actual addon Lua decoder and validator accepted its 39-group THR1 string.
Evidence: `artifacts/review/dragon-release/deployment.json`,
`artifacts/review/dragons-public-check.json`, and logs under
`artifacts/review/dragons/`.

## Stable import dialog (deployed 2026-10-17)

Deployed `talkinghead-vote-web:import-dialog-20261017`; the API was not restarted.
The header action is now “Импорт в аддон”, and the dialog title is
“Импорт рейтинга в аддон”. Copy confirmation changes the button label without
adding a paragraph. Both labels share one grid cell so the button keeps its
intrinsic width and height. The label change is announced through `aria-live`.

Desktop/mobile regression checks verify unchanged dialog, button and textarea
bounds after copying. Docker build checks and the public five-viewport check
passed, including THR1 checksum and clipboard verification; no ballots were sent.
Evidence: `artifacts/review/import-dialog-release/deployment.json`,
`import-dialog-image.log` and `import-dialog-public-*.png`.
Rollback: retag `talkinghead-vote-web:before-import-dialog-20261017` as the
configured web image and recreate only `web`; keep the schema-4 API and database.

## Two ranking layers and public addon export (deployed 2026-10-17)

Deployed `talkinghead-vote-server:ranking-layers-20261017` and
`talkinghead-vote-web:ranking-layers-20261017`. Both services are healthy.
SQLite schema 4 keeps one latest ballot per visitor/quest/stage, its effective
weight and generation, one current revision per quest, and historical/current
aggregate columns per choice-set pool and winner. A first fresh ballot in the
current generation multiplies the remaining corresponding historical evidence
by 0.98. Revoting removes the previous effective contribution; toggling the same
generation or replaying an inbox receipt does not decay history again. Releases
without changed file hashes and updates without new ballots do not reduce weight.
The Luce export now consumes fractional aggregate evidence. The welcome pie
chart continues to show raw active comparison wins, not weighted ranking scores.

The header's “Рейтинг для аддона” action exports the existing THR1 encoding
(base64url payload plus SHA-256). The dialog provides copy/import instructions;
the JSON download button was removed from it. JSON remains available through the
API and `ExportAddonRanking`. No addon codec change is required.

An isolated rehearsal on a production SQLite backup preserved all 781 ballots
and all 38 ranking groups. The production migration preserved those same ballots
and 788 comparison rows, retaining unit weights: historical 337, current 444,
769 aggregate rows. The group rankings matched before/after migration exactly.
Catalogue, audio/model manifests, portrait verification and mounts were unchanged.
The stopped database/inbox backup is
`/srv/talkinghead/backups/ranking-layers-20261017-074102`; SQLite integrity passed.

Validation: 57 Java tests, 54 frontend unit tests, Docker browser/build checks,
five public viewport checks, clipboard and THR1 checksum verification, plus
decoding the actual public string with `src/RankingCodec.lua` (38 groups).
Desktop header placement does not add page height; short viewports retain the
existing natural scrolling. No production test ballots were submitted.
The actual `ExportAddonRanking` task also passed. Evidence is under
`artifacts/review/ranking-layers-release/`, `ranking-layers-*-image.log`, and
`ranking-layers-public-*.png`; the Lua check is `ranking-layers-addon.cjs`.

Old images are tagged `before-ranking-layers-20261017`. **Do not retag an old
API image against schema 4.** A rollback before reopening admission can restore
the stopped database/inbox backup and old images together. After new votes are
accepted, retain schema 4 and deploy a forward fix or prepare a reverse migration
that preserves those votes; restoring the old backup would discard them.

## Ranking ties (deployed 2026-10-17)

Deployed `talkinghead-vote-server:ranking-ties-20261017` and the verified
`talkinghead-vote-web:ranking-ties-20261017` build. Both containers are healthy.
Ranking JSON and the THR1 import string now include `tieGroup`: equal observed
scores share the first rank in their tie; unique scores and fallback sources
have `null`. Existing ranks and schema version 1 are preserved. The future addon
importer can use the user's library order within explicit ties only. The export
button remains hidden, and the public frontend image contents are unchanged
because the unused export component is excluded from the production bundle.

The stopped database/inbox backup is
`/srv/talkinghead/backups/ranking-ties-20261017-031512`. All 781 active ballots and
788 comparison rows matched before and after API startup; SQLite integrity
passed. Catalogue, audio/model manifests, portrait verification and volume mounts
are unchanged. Old images remain tagged `before-ranking-ties-20261017`;
rollback retags them and recreates the services while preserving the live database.

All 50 Java tests and Docker build checks passed. Public export verification
confirmed identical JSON/download/import-string payloads and a valid checksum:
38 groups, including 10 with ties. The real `ExportAddonRanking` task refreshed
`artifacts/voice-ranking/addon-voice-ranking.json`. Public browser checks passed
for reload/no-store, layout, chart hover/exit, keyboard and touch selection.
Evidence: `artifacts/review/ranking-ties-release/deployment.json`,
`artifacts/review/ranking-ties-public.json` and `ranking-ties-*-image.log` under
`artifacts/review/`.

## NPC classification and welcome spacing (deployed 2026-10-16)

Deployed `talkinghead-vote-server:npc-layout-20261016` and
`talkinghead-vote-web:npc-layout-20261016` from commit `8330c70` after local review.
Both containers are healthy. The welcome description and start button have more
vertical space, with a visible gap before the chart; the illustration stays
240 px wide. The side-by-side layout now applies up to 1060 px viewport height.
The five desktop viewport checks listed below passed without scrolling.

Updated only NPC metadata in 11 existing comparisons: OOX quests 648, 836 and
2767 use the narrator; quests 1369, 1371, 1375, 1381, 1386, 7046, 7066 and 7067
use centaur/male. The ranking export now contains 38 race/sex groups. Existing
audio paths, recordings, texts, model cache and optimized portrait packs were
preserved. All 780 active ballots and 787 historical comparison rows matched
before and after API startup. The stopped database and catalogue backup is
`/srv/talkinghead/backups/npc-layout-20261016-164158`; SQLite integrity passed.
Old images remain tagged `before-npc-layout-20261016`; rollback restores the
backed-up catalogue and old image tags, retaining the current vote database.

Full offline verification completed: 1440 of 1441 cached appearances ready;
the sole failure remains the documented display 146706 for quest 97290, which
uses the existing placeholder. No new model failures occurred. Report:
`artifacts/voice-vote-model-cache/verify-report.json`. Public Firefox checks
passed for all four affected centaur NPCs and three narrator comparisons,
including playback from all three libraries. Chart reload/no-store, hover,
keyboard, touch, desktop layout and audio preload/volume checks also passed;
test ballots were intercepted and never submitted to production.

The addon test suite, 49 backend tests and Docker build checks passed. Forever
Quest Pins was checked on 2026-10-16 at 16:23 UTC and remains current at commit
`999243d962372f124d337495571176de19807552`. The updated addon was installed in
ForeverBeta, with backup `backups/20261016-192734-471-dc5890`.
Deployment evidence: `artifacts/review/npc-layout-release/deployment.json`,
`artifacts/review/npc-layout-public-check.json`, and `npc-layout-*.log` /
`npc-layout-public-*.png` under `artifacts/review/`.

## Welcome community results (deployed 2026-10-16)

Deployed `talkinghead-vote-server:community-20261016` and
`talkinghead-vote-web:community-20261016` from commit `b2b5d31` after local review.
Both containers are healthy. The database volume and pending inbox were copied
while the API was stopped to `/srv/talkinghead/backups/community-20261016-155134`;
SQLite integrity passed before and after deployment. Existing mounts and all
catalogue hashes are unchanged. Public totals at verification: 770 comparisons
(WowVoice 185, CatQuest 274, Wayfarer 311), read from the live API's memory cache.
The old images remain tagged `before-community-20261016` for each application;
rollback retags those images and recreates `api` and `web`, preserving newer votes.
Public Firefox checks passed for reload/no-store, desktop layout without scrolling,
hover/click/exit, keyboard/Escape, mobile touch selection, and audio preloading,
playback and volume persistence. Test votes were intercepted in the browser.
Deployment evidence: `artifacts/review/community-deploy.log`,
`community-public-*.png`, and `community-*-image.log` in the same directory.

The welcome page has a borderless pie chart below the start button, using the
existing library colors and names directly on sectors. Hover/focus enlarges and
offsets the sector, revealing that library's counts and percentage beside it
(below on mobile). Touch can pin the selection; mouse clicks do not pin or
retain focus, and leaving a sector clears its hover details. Keyboard focus
shows details while focused; Escape clears the selection. Small
or zero shares have accessible text selectors instead of overlapping labels.
Labels describe comparisons won, not unique participants. One participant can
contribute wins on different quests; a replacement choice still replaces its
previous contribution. Percentages use all active comparisons as denominator.
`/api/votes/community` returns
aggregate active choices without participant identifiers or a visitor cookie;
replacement ballots replace their previous contribution. This is raw vote share,
not the demographic Luce ranking. Empty/error states preserve the start action.
The API eagerly loads active choices at startup and maintains the aggregate in
memory after successful commits (including revotes and inbox recovery). Reads
do not query SQLite; failed/obsolete writes do not change the cache. This assumes
one API instance; external database edits require a restart. Responses and browser
fetches use `no-store`; the page fetches on mount, reload and restoration from the
back/forward cache. The optional development snapshot below still overrides the
local API response when present.
The local preview at http://127.0.0.1:5174/ uses an aggregate production snapshot (770 active comparisons,
2026-10-16 15:15 UTC), stored in ignored `data/voice-vote/community-preview.json`.
Only the Vite development server reads this optional file; removing it restores
the local API counters. The production database and local ballots are unchanged.
Sector labels follow each sector's area centroid instead of a fixed radius.
The welcome-only layout targets a Full HD 16:9 screen with approximately 900 px
of usable browser height, allowing for browser controls and bookmarks. The
illustration retains its original 240 px desktop width. The main area distributes
available viewport height between the welcome and chart blocks, avoiding a large
empty lower third on tall windows. The chart grows from 320 to 380 px with height;
windows up to 1000 px high place the illustration beside the description and use
a 300 px chart. Text sizes are retained. Verified without scrolling at 1920x900,
1920x1080, 2048x1024, 2560x1280 and 1600x780, including selected-sector details.
Natural scrolling remains available when needed; voting layout is unaffected.
All 48 backend tests and desktop/mobile rendering, empty/single-library results,
retry and transition checks passed. Screenshots: `artifacts/review/community-*.png`.
The interactive revision also passed hover/exit, keyboard and touch selection
checks. Screenshots: `artifacts/review/community-interactive-*.png`.
The memory-cache tests cover eager restart recovery, reads with the vote table
unavailable, immutable snapshots, concurrent readers, recording updates, rollback
and obsolete inbox deliveries. `npm run test:community` verifies fresh fetches on
mount/reload, back/forward restoration and retry; the frontend build also passes.

## Stalled texture retry (2026-10-16)

Deployed frontend `talkinghead-vote-web:texture-retry-20261016`. Loaded actors
with incomplete textures and no tracked downloads retry the portrait after
the readiness timeout, sharing the two-attempt limit with context-loss recovery.
Slow downloads retain late completion; the comparison and audio remain mounted.
See [DIAGNOSTICS.md](DIAGNOSTICS.md) for the original Kator incident and limits
of the evidence. The ranking button remains hidden.

The Docker build passed layout, ranking fixture, audio, catalogue/model cache
and portrait recovery checks. Seven deliberately aborted texture requests on
Kator reproduced the failure and recovered both locally and on the public site.
Public audio preload/volume checks passed; no production ballots were submitted.
The API container and catalogue hashes were verified unchanged. Models and audio
were not updated. Previous frontend: `:before-texture-retry-20261016`; image
metadata backup: `/srv/talkinghead/backups/texture-retry-20261016-122816`.
Rollback retags the previous image and recreates only `web` with `--no-deps`.
Evidence: `artifacts/review/texture-retry-*`, `artifacts/review/portrait-1426-*`.

## Unrated groups and missing categories (2026-10-16)

Deployed API `talkinghead-vote-server:unrated-groups-20261016` and the reviewed
catalogue. Within personally unseen comparisons, known race/sex groups with
no eligible retained ballots now precede covered and unknown groups. Old
recording ballots retain group coverage when speaker metadata still matches.
Weighted group diversity and current-recording coverage remain in each tier.

All seven previously missing groups now have 36 comparisons: dreadlord/male
(6), human_child/male (11), human_child/female (6), orc_child/male (6),
orc_child/female (2), quilboar/male (4), and stone_construct/male (1).
Mangletooth (3430) was already linked to quests 878, 879, 906 and 5052;
display 1346 / model 125497 establishes the missing quilboar category.
In total, 38 comparison metadata entries changed, including Rockbiter's
mountain_giant category (sex unknown) and the newly ambiguous Pins giver for
quest 94449. Pins is current at `999243d962372f124d337495571176de19807552`.
Shared metadata was also deployed to ForeverBeta.

Backup: `/srv/talkinghead/backups/empty-groups-20261016-121349`.
All 757 active ballots and 760 comparison rows were preserved field-for-field;
SQLite integrity passed. Audio IDs/hashes (11,437 recordings), model assets,
375 verified optimized packs, and the frontend image are unchanged. The ranking
button remains hidden. Rollback uses the catalogue pair and previous API image
`:before-empty-groups-20261016`, preserving the live database and pending inbox.

Validation: server and addon suites passed. Full offline verification completed
at 1,441/1,442 portraits with only the existing quest 97290 / display 146706
missing-camera exception. The public queue returned 4,103 unique comparisons
with the 36 uncovered comparisons first. One representative of each group
rendered and played every available library recording in the browser; public
audio preload/volume checks passed. No production ballots were submitted.
ExportAddonRanking refreshed the local JSON with all 37 groups. The two generic
child groups remain no_data fallbacks: their remaining NPCs have no quest links,
and old generic-child ballots do not transfer to corrected human/orc categories.
Evidence: `artifacts/review/empty-groups-*` and `artifacts/unrated-groups-api-build.log`.

## Compact ranking entries (2026-10-16)

Deployed API image `talkinghead-vote-server:ranking-compact-20261016`.
Ranking entries now contain only `rank`, `source` and `basis`; the unused
`tieGroup` field was removed from JSON and its encoded string. Sorting,
scores and database schema are unchanged. Schema version 1 is still being
prepared before release of the addon importer. The frontend container was
verified unchanged; the ranking button remains hidden.

The server verification suite and browser export fixture passed. Public JSON,
string checksum and the real ExportAddonRanking task were verified with all
37 groups. Previous API image: `:before-ranking-compact-20261016`; rollback
requires only retagging and recreating the API, preserving the live database.
Evidence: `artifacts/ranking-compact-*`.

## Ranking button hidden (2026-10-16)

At the user's request, restored the frontend image
`talkinghead-vote-web:before-ranking-20261016` and removed the ranking dialog
entry point from `src/main.jsx`. The public button stays hidden until the
user workflow is ready. API, database and the ExportAddonRanking task are
unchanged. The API container was verified unchanged during the web-only update.
The ranking frontend image remains available for future development.

## Addon community ranking (2026-10-16)

Deployed `talkinghead-vote-server:ranking-20261016` and
`talkinghead-vote-web:ranking-20261016`. The public “Рейтинг для аддона” dialog
downloads JSON and copies the same snapshot as a THR1 string. The server fits
regularized Luce choices per race/sex; library updates do not reduce old ballots.
The addon importer remains future work. Local download:
`.\build.cmd -Task ExportAddonRanking`, documented in [BUILD.local.md](../../BUILD.local.md).

SQLite schema 3 enforces one latest ballot per visitor/quest/stage. Migration
retained all 757 latest ballots from 764 stored rows; seven replaced versions
remain in the backup. Each retained ballot was compared field-for-field with
the pre-migration latest-row selection; integrity and uniqueness passed.
Replay ordering prevents an older inbox delivery from replacing a newer choice.

Pre-migration volume backup: `backups/ranking-20261016-111043` under the private
application directory. A separate verified database/catalogue archive was
downloaded to `backups/site-database/20261016-110805-database-snapshot-oum5izhc.tar.gz`.
The API also created its own SQLite backup before schema conversion. Previous
images remain tagged `:before-ranking-20261016`. The old API cannot read schema 3;
rollback requires a compatible data migration or the saved snapshot, with care
to preserve ballots accepted after deployment. Never restore over newer votes.

Only application images changed in that deployment; catalogue hashes were unchanged.
The category data below were still unpublished at that point. Bundled ranking metadata
enumerates 37 known groups; current deployed quest metadata takes precedence.
The verified export has 28 ranked groups, two partial groups and seven without
votes, with all three library places present in every group.

Validation: all 40 server tests, Docker frontend audio/layout/cache/ranking gates,
the actual build download task, and public desktop/mobile ranking checks passed.
Downloaded JSON exactly matched the decoded string and SHA-256. Public audio
preloading, playback reuse and volume checks passed with mocked ballots/audio.
No test ballots were submitted. Evidence: `artifacts/ranking-*`.

## Categories prepared on 2026-10-15 (published 2026-10-16)

The user deferred deployment on 2026-10-15, then requested publication to make
the missing voting groups available on 2026-10-16. The deployment recorded above
includes these changes in both the site and installed beta addon:

- `dreadlord`: exact CatQuest Voices label or verified appearance, appearance
  taking priority; NPC sex is independent. Varimathras (2425) and Lord Banehollow
  (9516), six voting comparisons.
- `human_child` / `orc_child`: verified child appearance or known race plus
  child age, preserving male/female subdivisions. Shared data changed for 33
  children; the voting catalogue has 17 human-child and eight orc-child comparisons.

- `stone_construct`: verified display 6589 / model 126072, NPC 7918 (quest 2954),
  preserving `sex=male`. Generic `elemental-golem` voices do not classify robots
  or other golems.
- `mountain_giant`: Rockbiter (7765, quest 2844), verified display 1918 / model
  124952, separate from stone constructs and ogres. Sex remains unknown.
  Combined local metadata: `artifacts/review/classify-npcs-catalogue/`.

Previous prepared metadata: `artifacts/review/dreadlord-children-catalogue/`; comparison
diff: `artifacts/review/dreadlord-children-changes.json`. Audio, text, model IDs
and display IDs are unchanged. New category identities must not inherit old
generic-child, unknown or scourge ballots. Server exporter regressions cover
this separation; the completed publication gates are recorded above.

## Imp category (2026-10-14)

Imported Wayfarer's exact `imp-male` as `imp/male`, ahead of broad CatQuest
NPC demographics and `goblin-male` voice labels. Only Impsy (14470) changed;
affected comparisons: 7602, 7603, 8420, 8421, 8422. The rule is in the shared
importer and generator, with regressions for priority, speaker identity and
ambiguous labels. It is also installed in ForeverBeta. Quest Pins is current
at `30106821e96e90df5f171c195ff15a68689b471b`.

The addon suite, source checks, five exporter tests and audio preload tests
passed. Full offline verification completed at 1,441/1,442 portraits, retaining
only the known quest 97290 / display 146706 missing-camera exception. Existing
375 optimized packs, models, audio paths and application images are unchanged.

Backup: `/srv/talkinghead/backups/imp-20261014-193826`.
Preserved all 708 existing vote/comparison records and the pending inbox;
SQLite integrity passed. Old goblin-category ballots remain historical and
do not contribute to current demographic results for these comparisons.
Evidence: `artifacts/review/imp-*`. Rollback restores the catalogue pair from
the backup and restarts services, retaining the live votes volume.
Public quests 8421 and 7602 reached ready with `imp/male` and played successfully;
the public audio preload and volume regression passed without production ballots.

## Water elemental category (2026-10-14)

Imported the explicit `elemental-water` label from CatQuest Voices and Wayfarer
as `elemental_water`, with canonical `sex=male` for one unsexed group. Both
libraries identify Duke Hydraxis (13278); CatQuest's NPC table had empty race/sex.
The shared generator now classifies NPCs 5895, 11862 and 13278, whose three
appearances resolve to water elemental model 126426. Updated 11 comparisons.
Historical null/orc-category ballots remain historical and are not inherited.
The new ResultsExporter regression verifies separate current/historical counts.

Forever Quest Pins advanced to `30106821e96e90df5f171c195ff15a68689b471b`
(3,982 source quests); merged quest-giver relationships did not change.
Shared metadata passed import/check tests and the addon suite, and was deployed
to ForeverBeta. Offline verification completed at 1,441/1,442 portraits with
only the known quest 97290 / display 146706 missing-camera exception.
Model assets, optimized derivatives and application images were unchanged.

Backup: `/srv/talkinghead/backups/hydraxis-20261014-155025`.
All 696 existing vote/comparison records and deployed audio paths were preserved;
SQLite integrity passed. Public quests 7486, 96 and 6562 reached ready with
`elemental_water/male` and played successfully. Public audio preloading and volume
checks passed without test ballots. Evidence: `artifacts/review/hydraxis-*`.
Rollback uses the two catalogue JSON files from the backup; preserve the live
votes volume and restart services after restoring the catalogue pair.

## Weighted voice-group queue (2026-10-14)

Deployed `talkinghead-vote-server:group-queue-20261014` from commit `fabaa5f`.
The API now samples race/sex groups with a soft recency penalty, keeping explicit
narrators separate from unknown NPCs. Group size does not increase selection
probability; consecutive group appearances remain possible. Unrated comparisons
stay ahead of repeats, and lower coverage determines ordering within a group.
Pending accepted votes and recent stored votes contribute to the penalty.

The Docker build passed the Java verification suite, including group sampling,
API ordering, restart persistence and pending-vote tests. Twenty public queue
requests returned all 4,103 unique comparisons and exercised 31 groups across
their first five entries. The API retained the weighted ordering rather than
sorting it back by global coverage. No ballots were submitted. Public audio
preloading, playback reuse and cookie volume checks also passed.

Backup: `/srv/talkinghead/backups/group-queue-20261013-215204` (UTC).
All 622 existing votes and 622 comparison records were preserved; SQLite integrity
passed. The web container and catalogue/audio manifest hashes are unchanged.
The backup includes SQLite, the pending inbox and the previous API image ID.
To roll back, retag `talkinghead-vote-server:before-group-queue-20261014` as
`:local` and recreate only `api`; do not restore the database over newer votes.
Evidence: `artifacts/review/group-queue-*`.

## External skeleton and emitter optimization (2026-10-13)

Deployed `talkinghead-vote-web:portrait-packs-20261013` with 375 verified M2
packs and three packed external skeletons. All 26 previous source-format
fallbacks are now supported: three SKID models and 23 particle/ribbon models.
The previous 349 derived files are byte-identical. Full body geometry, materials,
effects, cameras and required Stand/Talk animation are retained.

Quest 1116 / model 119376 previously took 38,509 ms in the reported browser
trace. Its geometry and skeleton compressed payload fell from about 10.27 MB
to 0.81 MB. A fresh public Firefox check reached ready in 4,969 ms, with
`portraitPack: true` on both M2 and SKEL requests. This is a measured check,
not a latency guarantee for every connection. Published bytes, SHA-256 URLs
and year-long immutable cache headers were verified for all three SKID pairs.

Validation: 375 source/packed comparisons through the actual viewer parser,
no unsupported or failed packs; neutral, nine Talk samples and reset comparisons
for the affected model families; 20 versioned WebGL cases with 506 hashed
resource requests and no resource requests on repeat loads; 54 unit tests;
Docker audio/layout/cache gates. Public portraits 1116, 898, 271, 154 and 92468
loaded and played successfully. The deployed audio-preloading and volume checks
passed. Browser voting requests were mocked; no test ballots were submitted.

Backup: `/srv/talkinghead/backups/portrait-packs-20261013-193522`.
Only the web container and model derivatives changed; the API container and
voting data were left intact. Roll back the saved `verification.json` and retag
`talkinghead-vote-web:before-expanded-packs-20261013` as `:local`, then recreate
only `web`. New derivative files may remain; the old manifest does not select
them. Logs and verification artifacts: `artifacts/review/portrait-pack*`.
The update-libraries skill now requires optimization and explicit review of
every unsupported file before model delivery.

## Browser model cache and catalogue revalidation (2026-10-13)

Deployed `talkinghead-vote-web:model-cache-20261013`. Portrait resources now use
per-file SHA-256 query versions with `public, max-age=31536000, immutable`.
The small per-portrait version manifest is revalidated; unchanged resources keep
their URLs across deployments. Hashes cover the actual packed/fallback model and
adapted viewer bytes. Mismatched hashes fail with non-cacheable 410 responses.
Preparation/deployment requirements are in [MODEL-CACHE.md](MODEL-CACHE.md).

The earlier catalogue fix changes the client from `no-store` to `no-cache`,
allowing revalidation and reuse of its compressed body across page reloads.
Public Firefox verification confirmed 200 then 304 for the catalogue, a ready
portrait and a model reused after reload with its original cached request ID.
No production ballots were submitted. All 52 web unit tests, the image build's
audio/layout/cache gates, and real cached-viewer neutral/talk/reset checks for
quests 179, 925, 5657 and 97326 passed. The latter made no model requests on
repeated portraits; all 53 initial resource requests carried content hashes.

Only the web container was replaced. The API container and catalogue hashes were
verified unchanged; the votes volume was untouched. Rollback image references:
`/srv/talkinghead/backups/model-cache-20261013-185146` and
`/srv/talkinghead/backups/catalogue-cache-20261013-183803`.
Logs: `artifacts/review/model-cache-*` and `catalogue-cache-*`.

## CatQuest 0.7.0 catalogue update (2026-10-13)

Updated CatQuest and Voices metadata, including current Forever Quest Pins.
The catalogue now contains 4,103 comparisons and 11,437 recordings: 295 added
comparisons, none removed. Transferred 2,565 new audio files directly from the
installed libraries (332,356,313 bytes) to hash-addressed paths; unchanged
recording IDs retain their previous paths. Previous audio remains available.

Backup: `/srv/talkinghead/backups/catquest-0.7.0-20261013-181810`, including
SQLite, the pending inbox, previous catalogues/model manifests and image IDs.
All 544 existing votes and 544 comparison records were preserved. Both services
are healthy; database integrity and unchanged application image IDs were checked.
The local weighted race/sex queue changes are not included in this data update.

Full offline verification completed at 1,441/1,442 portraits, with only the known
quest 97290 / display 146706 missing-camera exception. Added 185 original model
resources. Packed-model checks passed: 349 verified, 26 original-format
fallbacks, no failed packs. New model families passed neutral/talk/reset WebGL
checks. The compressed model delta, including verified packs, was 21,454,213 bytes.

Public Firefox checks loaded portraits and played every available voice for
quests 3381, 4970, 8058, 8544, 495 and 97326 without production ballots.
The public catalogue matches the staged snapshot. Audio preloading, playback
reuse and cookie volume checks passed against the deployed frontend with mocked
vote/audio requests. Artifacts: `artifacts/review/catquest-0.7.0-*` and
`artifacts/voice-vote-deploy/updates/catquest-0.7.0/`.

## Creature categories, camera and debug update (2026-10-13)

Deployed image `talkinghead-vote-web:categories-camera-20261013` with the
female orc child camera confirmed by the user in game: quest 97326, model 125362,
profile `orc_child_female`, distance 1.5, offset Y 0.02 / Z 0.04.
The image was rebuilt from the final repository sources after confirmation.

The catalogue changes 34 comparisons for 17 NPCs to `ancient/male`,
`furbolg/male` or `banshee/female`. Sex is a single canonical group value for
ancients/furbolgs. Explicit CatQuest Voices creature categories precede Wayfarer
and broad NPC voice labels. Old votes and comparison IDs were not migrated:
previous classifications remain historical, and corrected categories collect
independent votes. Audio hashes, recording IDs/paths, texts, portrait assets and
the 3,808-comparison set are unchanged. The React debug JSON now includes the
exact catalogue `race` and `sex`, including null values and unavailable portraits.

Backup: `/srv/talkinghead/backups/furbolg-20261013-075908`.
Deployment verified that all 530 existing votes and 530 comparison records
were preserved; SQLite integrity and both container health checks passed.
The backup includes the database, pending inbox, previous catalogue and image ID.

Validation artifacts are in `artifacts/review/furbolg/`: addon suite, 49 web
unit tests, layout, portrait recovery/debug fields and audio preloading passed.
`ResultsExporterTest` confirms separate identities and no inherited race votes.
Full offline portrait verification completed at 1,425/1,426, with only the known
quest 97290 / display 146706 missing-camera exception. The full run used
`verified-catalogue.json`; the final snapshot differs only in race/sex fields,
and deployment preflight verified identical portrait/audio workload.
Packed-model verification passed: 342 verified, 22 original-format fallbacks,
no failed packs. The final female orc profile also passed a focused render check
in neutral pose, nine talk frames and reset. Audio preloading and cookie-based
volume checks passed again against the deployed frontend without real ballots.
Live Firefox checks also loaded and played quests 8231, 7636, 5657 and 97326,
confirming ready portraits, catalogue-matching debug categories and contained text.

The voting site and Java API share one Ubuntu server. Nginx on the host terminates
HTTPS and proxies the entire site to `127.0.0.1:8080`. Java has no public port.

## Current host

- Server connection: private `config/build.env.local.ps1` (`TALKINGHEAD_SITE_SSH_HOST`).
  Ubuntu 26.04, 1 vCPU, 2 GB RAM, 30 GB disk.
- Site: https://talkingheadru.tw1.ru/ (free Timeweb technical domain).
- Admin panel: https://talkingheadru.tw1.ru/admin/.
- Application directory: `/srv/talkinghead`.
- SSH key: private `TALKINGHEAD_SITE_SSH_KEY` in the same local configuration.
- Public firewall ports: SSH 22, HTTP 80 for ACME/redirect, HTTPS 443.
- A 1 GB swap file provides emergency headroom; it is not a RAM replacement.

## Runtime and secrets

Use the image-only `compose.yaml` prepared by the deployment bundle together with
[compose.production.yaml](compose.production.yaml). The override limits Java to
896 MiB (384 MiB heap) and the web container to 384 MiB, and rotates container logs.

```sh
cd /srv/talkinghead
docker compose -f compose.yaml -f compose.production.yaml up -d --no-build --wait
docker compose -f compose.yaml -f compose.production.yaml ps
docker stats --no-stream
```

The `.env` file contains paths and flags, not the admin password. The password
is in `/srv/talkinghead/secrets/admin-password.txt`, owned by UID/GID 10001 with
mode 0400; its parent directory is accessible only to root. Compose mounts the
file read-only in the API container. The initial password comes from the ignored
local file `config/voice-vote-admin-password.local.txt`. Never put it in Git,
image archives, logs or frontend configuration.

## Data

- `catalogue/`: the three JSON exports, updated together.
- `libraries/`: externally installed audio files, transferred directly from the
  installed libraries according to `audio-manifest.json`, preserving relative
  paths. Audio is not copied into the repository, image or release archives.
- `talkinghead-vote_model_cache`: prepared models, read without upstream fetches
  (`VOICE_VOTE_MODEL_OFFLINE=true`).
- `talkinghead-vote_votes`: SQLite, WAL and the durable pending-vote inbox.

The initial model snapshot has one documented camera failure: quest 97290,
display 146706. Its portrait uses the scroll placeholder. All 1,270 other
available portraits passed the offline browser audit. Quests without a display
ID also use the placeholder. Keep this exception visible in cache audit reports.

Do not run `docker compose down --volumes` on this deployment. Back up both
SQLite and its pending inbox, following the [server backup instructions](../../server/voice-vote/DOCKER.md).
Aggregate exports from the admin panel do not replace a database backup.
Download a complete database snapshot with `build.cmd -Task BackupSiteDatabase`;
see [local backup and recovery instructions](../../BUILD.local.md#backupsitedatabase--скачать-полную-резервную-копию-базы-сайта).

## Initial host check

On 2026-10-12, an isolated API container using the production image and memory
limit accepted 100 simultaneous visitors' ballots. All 100 were committed and
exported, with zero inbox failures. Submission p95 was 1.16 seconds during this
artificial burst; API memory after the check was about 197 MiB. This measured
the API on the host, not public Internet latency or 100 simultaneous model/audio
downloads. The separate test container and its `talkinghead-vote_smoke` volume
were removed after validation; the production votes volume was not used.

## Updates

Build images locally using [DOCKER.md](DOCKER.md), transfer and load them, then
run the Compose command above. Do not build frontend/Java images on the small
production server. Import and verify additional model dependencies before
exposing an updated catalogue; see [MODEL-CACHE.md](MODEL-CACHE.md).

## Public launch verification

Portrait diagnostics: [log fields, SSH lookup and baseline](DIAGNOSTICS.md).

### Portrait catalogue and text containment (2026-10-13)

Web image: `talkinghead-vote-web:portraits-20261013`; API image unchanged.
The bundle adds portraits to 177 comparisons for 84 NPCs and localizes seven
missing/English names. All 3,808 comparisons, 9,863 recordings, hashes, texts and
deployed audio paths are retained. The shared addon database and website use
verified exact-NPC supplements, including the first automated Wowhead pass.
`TalkingHeadRuSpeakers` replaces the old internal global in runtime and generation.

Wrapped NPC names now reduce the description viewport inside a fixed bottom
inset. Single-line geometry stays unchanged; extreme names are capped at three
lines. The volume percentage matches the idle speaker icon. Text containment
checks run both in `npm test` and as a required Docker build gate.

Validation: six importer tests, addon tests, 49 frontend unit tests, layout,
portrait recovery, audio preload/volume and Docker checks passed. Full offline
check: 1,425/1,426 ready, with only the existing quest 97290 / display 146706
missing-camera exception. All 342 packed models passed parser verification;
22 unsupported formats retain originals. Default pose checks and eleven additional
new model checks passed. The bundle adds 677 original dependencies without
replacing existing assets; the manifest covers 13,491 dependencies.

Deployment bundle: `/srv/talkinghead/import/portraits-20261013`; backup location:
`/srv/talkinghead/backups/20261013-portraits`. The switch script stops services,
backs up SQLite plus the pending inbox and metadata, then installs the catalogue
and image. Its rollback restores metadata and the old image while preserving
live votes. Local validation logs: `artifacts/review/portraits-*.log`.

### Cumulative portrait update (2026-10-13)

Web image: `talkinghead-vote-web:cumulative-20261013`; API image unchanged.
The catalogue retains 3,808 comparisons and 9,863 recordings, including all
previous recording IDs, hashes, text and deployed audio paths. Thirty comparisons
now have portraits for Ogtinc (8405), Illaya Amberwind (251902), Ayessa Dawnsinger
(251968), Raan Wildwind (263664) and Ursendris (255853). One additional comparison
receives missing speaker sex metadata. Child voice labels provide age and sex,
never a guessed biological race or camera model.

The confirmed Orc Orphan camera and separate male/female human child cameras
are deployed. WebGL context loss replaces the blank frame with the scroll and
rebuilds only the portrait, at most twice per mounted display. Audio, the series
and votes remain intact. Error reports include bounded renderer status for SSH
investigation; this does not establish the cause of the earlier browser-wide freeze.

Validation: 49 frontend unit tests, delayed portrait/context-loss recovery tests,
local and deployed audio-preload/volume regressions, addon tests and Docker gates
passed. Full offline audit: 1,352/1,353 ready; only the documented quest 97290 /
display 146706 has no portrait camera. All 320 derived models passed verification;
16 unsupported formats keep original assets. Ten original/packed rest/Talk/rest
pose comparisons passed. The host verified all 9,863 audio hashes and 12,814 model
dependency hashes; 65 dependencies were added alongside the existing cache.

Public Firefox checks loaded quests 925, 92110, 8257, 92595, 93735, 98284, 94638,
391 and 97922 and played their audio. An injected real WebGL loss on quest 391
(`p-06b9bf68a72f`) produced a server diagnostic and recovered as `p-4d857282416a`
without resetting playback or the series. All voting endpoints were intercepted.
All 383 existing votes from 20 participants remained unchanged; SQLite integrity
passed, pending and quarantine were empty. Both services are healthy.

Consistent backup: `/srv/talkinghead/backups/20261013-cumulative`; staging:
`/srv/talkinghead/import/cumulative-20261013`. To roll back, stop web/API, restore
the three catalogue files and model reports from this backup, retag the image ID
in `web-image.txt` as `talkinghead-vote-web:local`, then restart both services.
Preserve the live votes volume and compatible model assets; never replace votes
collected since the backup with its historical copy.

### Eric portrait metadata (2026-10-13 local time)

NPC 265813 now uses display 144653, confirmed by its exact Wowhead Forever page.
The shared appearance supplement supplies the addon and site. Eleven comparisons
gain the portrait: 96031, 96044, 96046, 96047, 96050, 96055-96058, 96608 and 96629.
All 3,808 comparisons, 9,863 recordings, texts, variant IDs and deployed audio
paths are retained. Existing application images are reused.

Full offline audit: 1,347/1,348 ready, with only the known quest 97290 camera
exception. All 314 portrait packs passed verification; fifteen existing
unsupported formats retain original assets. Eric's neutral pose, nine Talk
samples and return pose matched the original. The host verified 12,749 model
dependency hashes and all audio hashes. Public quest 96629 reached `ready`
(`p-75456e9bc923`), served the verified model 878772 pack and played its audio.
Local and public audio-preload tests passed without production ballots.

All 295 existing votes remained unchanged; SQLite integrity passed, pending and
quarantine were empty. Consistent backup: `/srv/talkinghead/backups/20261013-erik`;
staged metadata: `/srv/talkinghead/import/erik-20261013`. To roll back, stop web/API,
restore the three catalogue files and model reports from this backup, and restart
both services while preserving the live votes volume and model assets.
ForeverBeta has matching speaker metadata; in-game visual confirmation is manual.

### Eleanor portrait metadata (2026-10-13 local time)

NPC 265812 now uses display 144652, confirmed by its exact Wowhead Forever page.
The shared database supplies this appearance to the addon and site. Thirteen
comparisons gain the portrait: 96607, 96658 and 97951–97961. The catalogue still
contains 3,808 comparisons and 9,863 recordings; texts, variant IDs and deployed
audio paths are unchanged. The existing volume web image and API image are reused.

The original cache gained fifteen dependencies. All 314 portrait packs passed
verification, with fifteen unchanged original-format fallbacks; Eleanor's rest,
nine Talk samples and return pose matched the original model. Full offline audit:
1,346/1,347 ready, with only the known quest 97290 camera exception. The host verified
all 9,863 audio and 12,745 model dependency hashes. Public quest 97958 reached ready
(`p-213534e29c74`), served the verified model 997378 pack and played its audio.
The deployed audio-preload and volume regression passed without production ballots.

All 253 previous votes remained unchanged; SQLite integrity passed, pending and
quarantine were empty. Consistent backup: `/srv/talkinghead/backups/20261013-eleanor`;
staged metadata: `/srv/talkinghead/import/eleanor-20261013`. For a catalogue rollback,
stop web/API, restore the three catalogue files and model reports from the backup,
then restart both services, preserving the live votes volume and model assets.
ForeverBeta received the same speaker metadata; in-game visual confirmation is manual.

### Persistent volume controls (2026-10-13 local time)

Web image: `talkinghead-vote-web:volume-20261013`. The shared volume panel supports
the slider, mute/restore and wheel changes in 5% steps. The default is 100%;
`thru_vote_volume` and `thru_vote_previous_volume` cookies retain the setting and
last audible level for one year. HTTPS cookies use Secure and SameSite=Lax.
Inactive speaker waves remain dimmed. The panel sits beside the talking head on
desktop and below it on narrow screens. Portrait diagnostics use only one JSON
text node, without duplicate data attributes.

Validation before deployment: all 47 frontend unit tests, delayed portrait and
audio-preloading browser checks, addon tests and Docker build gates passed.
The audio browser check also verifies mute/restore across a reload, wheel input,
cookie persistence, uninterrupted playback and desktop/mobile placement.
Run it against the deployed bundle with `VOICE_VOTE_TEST_URL` set to the public
origin; its voting and audio endpoints are intercepted, so no test ballots are sent.

Deploy only `web`; the API container, catalogue and persistent volumes are reused.
Rollback image: `talkinghead-vote-web:before-volume-20261013`. Retag it as `:local`
and recreate only `web` with `up -d --no-deps --no-build --wait web`, using both
Compose files. Reload an already open browser tab to load the new controls.

### Portrait diagnostics (2026-10-12)

Web image `talkinghead-vote-web:portrait-diagnostics-20261012`, bundle
`index-VpMBIij7.js`, adds the hidden first-body `portrait-debug` element and
per-mount client reports, request IDs, asynchronous model reads with timing,
container asset logs and host HTTPS logs. The host has the tracing helper at
`/srv/talkinghead/trace-portrait.py`, the log format in
`/etc/nginx/conf.d/talkinghead-assets.conf` and rotation in
`/etc/logrotate.d/talkinghead-assets`.

Live load `p-117cbe549713` (quest 977, model 119369) was traced end-to-end:
44 ms read, 0.576 s container response, 26.278 s edge response, 34.142 s browser
transfer, 38.947 s total portrait readiness. Different layers finish at different
times because of buffering and network transit. Camera setup took 460 ms.
No errors or production ballots; voting endpoints were intercepted. All 43 unit
tests, delayed portrait/telemetry browser checks, mandatory audio-preload image
tests, gzip/request-ID checks, Nginx validation and logrotate dry run passed.
The Java service and vote data were unchanged.

Rollback image: `talkinghead-vote-web:before-portrait-diagnostics-20261012`.
Previous host virtual-host configuration:
`/srv/talkinghead/nginx-before-portrait-diagnostics-20261012.conf`.

### Portrait subsets without geometry reduction (2026-10-12)

Current web image: `talkinghead-vote-web:portrait-packs-20261012`, bundle
`index-DUiARL_U.js`. Versioned `/modelviewer/portrait-v1/classicplus/` URLs serve
313 verified derived M2 files from `model_cache/portrait-packs-v1/`. Fifteen M2
files with external skeletons or emitters use the original cache. Source assets,
textures, geometry quality, full bodies, cameras and lighting are preserved.
Preparation and future updates: [PORTRAIT-PACKS.md](PORTRAIT-PACKS.md).

Validation: 46 unit tests, delayed-portrait and audio-preload browser tests,
production Nginx compression check, actual-viewer parsing comparisons for all
313 derived files, and identical rest/Talk/rest bone and material values across
47 representative main models. The original camera exception for quest 97290
remains unchanged. Added the missing cached Talk variation `7479346.anim`
(136,096 bytes), encountered by the broader animation verification.

Public trace `p-212d9a769d8f` for Umi: M2 818,826 gzip bytes / 3,548,540 decoded
bytes, 234 ms browser download, 2,519 ms total readiness; no failed requests or
browser errors. The earlier same-model trace was 11,353,298 gzip bytes and
38,947 ms total. These are separate observations, not a guaranteed latency ratio.
The public check did not submit votes. Java and the vote database were untouched.

Rollback: retag `talkinghead-vote-web:before-portrait-packs-20261012` as `:local`
and recreate only `web`. Original asset URLs and source cache remain available.

### Audio preloading (2026-10-12)

Web image `talkinghead-vote-web:audio-preload-20261012` preloads every recording
in the current and next comparison, starting on the welcome screen. At series
completion it prepares the next series' first comparison. Completed downloads
are reused as browser blob URLs; old entries are cancelled/released. An early
click before download completion uses normal streaming without waiting for the
entire file. Background preload failures remain silent.

The image build now requires audio cache unit tests and a real Firefox playback
regression test. The same browser scenario passed against the deployed bundle
`index-BqfIzdd3.js`. A separate public smoke check preloaded six real recordings
before Start and played the current variants without extra audio requests.
All voting endpoints were intercepted; no test ballots reached the database.
All 41 unit tests and slow portrait browser tests also passed. Only web was
recreated; the API and persistent data were unchanged. Rollback image:
`talkinghead-vote-web:before-audio-preload-20261012`.

### Slow portrait downloads (2026-10-12)

Web image `talkinghead-vote-web:portrait-loading-20261012` fixes permanent scroll
placeholders after the old 40-second readiness deadline. The readiness check now
uses a 120-second soft timeout and can recover when a model finishes later. It
checks readiness before elapsed time, including after background-tab throttling.
Nginx also compresses binary model responses with gzip level 3 and sends Vary.

Reproduced on the public site with quest 1050 (display 2049, model 950080): the
28,484,602-byte model was still downloading when the old timer stopped checking.
After deployment it reached ready in a fresh Firefox context. Its compressed
transfer is 13,389,779 bytes; decompression was verified byte-for-byte against the
cached original. This reduces transfer size, but a cold large model can still
take substantial time on a slow connection. The 616 quests without a known
display ID continue to use their intentional placeholder.

Readiness timer tests, batch navigation and catalogue-refresh browser checks
passed. Java, catalogue, models and votes were unchanged; live browser checks
intercepted voting endpoints and submitted no production ballots. Rollback image:
`talkinghead-vote-web:before-portrait-loading-20261012` (retag as `:local`, recreate
only `web` using the Compose command above).

### Catalogue refresh in open tabs (2026-10-12)

Web image `talkinghead-vote-web:catalogue-refresh-20261012` adds conditional
catalogue refresh on navigation, focus/visibility, once per visible minute, and
after a rejected obsolete ballot. Only unseen comparisons are refreshed. Active
playback, session chart and series position remain intact; no page reload occurs.
An obsolete ballot still receives normal local confirmation but is not counted
by the API and is never reassigned to replacement recordings.

The web container was replaced; Java, the votes volume and catalogue data were
unchanged. Rollback image: `talkinghead-vote-web:before-catalogue-refresh-20261012`.
Retag it as `talkinghead-vote-web:local` and recreate only `web` with
`up -d --no-deps --no-build --wait web` using both Compose files above.
Existing tabs need one manual reload to load this client code.

All 35 frontend tests and both browser scenarios (batch flow and catalogue
updates during playback/preparation) passed. Conditional GET supports weak ETags
from gzip proxies. Production health and the new bundle were verified over HTTPS;
no test votes were submitted to the production database.

### Explicit narrators and portrait diagnostics (2026-10-13 local time)

Web image: `talkinghead-vote-web:narrator-debug-20261013`; API image unchanged.
All 3,808 comparisons and 9,863 recordings remain available. 305 descriptions now
have an explicit Narrator label, including 98247/98248; 20 incorrect NPC links
were removed (15 previously had a portrait). Narrators retain library choices
and quest votes, with zero NPC/display/model IDs and null race/sex. Historical
ballots are retained; changed speaker identities become historical comparisons
and do not contribute to current race/sex aggregates.

Quest 94007 now displays Elayaa (NPC 254084, display 137999), confirmed by the
exact Wowhead Forever NPC page. Sixteen additional model dependencies were
installed alongside existing assets. The complete pack test verified 314 files,
with 15 supported original-file fallbacks and no errors. Elayaa's original and
packed neutral/Talk poses matched. Full offline audit: 1,345/1,346 ready, only
the existing quest 97290 camera exception. All 9,863 audio and 12,730 model
dependency hashes matched on the host.

`portrait-debug` now contains a single JSON text node for copying all diagnostic
fields at once, while retaining its existing data attributes. Browser regression
checks cover loading, late readiness and diagnostic consistency. Public checks
confirmed quest 94007 ready (`p-42c287578831`), quest 98247's scroll/Narrator label
with two choices, and the deployed audio preloading regression. No real test
ballots were submitted. All 232 pre-update votes remained unchanged; SQLite
integrity and both service health checks passed. Updated addon files are installed
on ForeverBeta; in-game visual confirmation remains manual.

Backup: `/srv/talkinghead/backups/20261013-narrator`; staged data:
`/srv/talkinghead/import/narrator-20261013`. Roll back by stopping web/API,
restoring the three catalogue JSON files and model reports from the backup,
retagging the image ID in `web-image.txt` as `talkinghead-vote-web:local`, then
starting both services. Keep the live votes volume and additional compatible
model assets. The backup is a deployment snapshot, not a scheduled backup.

### Fillion portrait correction (2026-10-13 local time)

Quest 99260 now uses display 137707 for NPC 253285, confirmed from that exact
NPC's Wowhead Forever page. The source libraries had no display for this NPC;
the narrow, documented supplement is in
`docs/internal/npc-appearance-supplements.json`. Existing model assets and
application images were reused. No recording versions or quest texts changed.

Full offline verification: 1,348/1,349 ready, with only the existing quest 97290
camera exception. The Fillion original/packed pose regression and deployed audio
preload test passed. The public portrait reached `ready` with verified portrait
packs (`p-40f98b01a15e`). All 229 existing votes remained unchanged; no test votes
were sent to production. All 9,863 audio and 12,714 model dependency hashes matched.
The addon metadata was also installed on ForeverBeta; an in-game visual check
remains manual.

Backup: `/srv/talkinghead/backups/20261013-fillion-portrait`; staged metadata:
`/srv/talkinghead/import/fillion-portrait-20261013`. For rollback, stop web/API,
restore the three catalogue JSON files and model reports from this backup, then
restart both services. Keep the live votes volume and existing model assets.

### Retired Forever snapshot removed (2026-10-13 local time)

NPC-only catalogue update: 38 additional quest portraits, including Arynia for
quest 940; 3,808 comparisons and all 9,863 recordings retained. Current images
were reused. Model cache was supplemented with 60 files and an updated verified
pack manifest. Full offline audit: 1,348/1,349 ready, only the existing quest
97290 camera exception. All 227 existing votes survived the switch unchanged.

Backup: `/srv/talkinghead/backups/20261012-remove-legacy-forever`; staged metadata:
`/srv/talkinghead/import/remove-legacy-forever-20261012`. To roll back, stop web/API,
restore the three catalogue JSON files and model reports from that backup, then
restart both services with the Compose command above. Keep the live votes volume;
additional model files are compatible with the previous catalogue.
Public quest 940 reached ready (`p-499bdfb5bd8d`), verified model packs were served,
and the deployed audio-preload regression passed without sending real votes.
[Import audit](../../docs/internal/retire-forever-snapshot.md).

### Wayfarer 3.2.0 data update (2026-10-12)

The public catalogue contains 3,808 description comparisons and 9,863 recordings,
using Wayfarer core 1.0.0 and quest modules 3.2.0. Application images are unchanged.
4,010 new recording versions were streamed directly from installed libraries into
hash-specific paths; unchanged IDs retain their previous deployed paths. Existing
audio and votes remain available. All audio hashes were verified before switching.

The model cache gained 69 ready portraits and 478 dependencies. The full offline
pass completed: 1,339 / 1,340 portraits, with only the previously documented camera
fallback for quest 97290 (display 146706). All 12,655 model dependency hashes match.

The consistent backup of SQLite, pending inbox, previous catalogue and model
manifest/reports is `/srv/talkinghead/backups/20261012-wayfarer-3.2.0` (root-only).
All 131 pre-update votes from 12 participants were verified unchanged; SQLite
integrity passed, pending and quarantine were empty. Both containers are healthy.
The public catalogue, an audio hash from each Wayfarer pack, two-variant playback
and a ready portrait were checked in Firefox without external asset requests or
test ballots. Memory after restart was approximately 234 MiB combined.

Staging: `/srv/talkinghead/import/wayfarer-3.2.0-20261012/`. To roll back, stop web/API,
restore the previous three catalogue JSON files and model manifest/reports from
this backup, then restart with Compose. Keep the live votes volume and all audio;
do not overwrite votes collected since the backup. This is a one-time deployment
backup, not an automated backup schedule.

### CatQuest Voices 0.6.1 data update (2026-10-12)

The public catalogue now uses Voices 0.6.1: 3,576 comparisons and 9,207 recordings.
29 comparisons have a changed CatQuest recording hash. Application images did
not change. Existing votes and their original recording hashes remain in SQLite.
All 31 pre-update votes were verified unchanged after the restart; the pending
inbox was empty. Public playback, admin login/export and all 29 new audio hashes
were checked over HTTPS without submitting test votes.

New audio was streamed directly from installed libraries into
`libraries/CatQuest_Voices/revisions/<sha256>/<filename>`. The deployed
`audio-manifest.json` maps these paths; previous recordings remain at their
existing library paths. On the next update, preserve the current server mapping
for unchanged recording IDs and add versioned paths for new IDs. Do not replace
the deployed manifest blindly with the local export's original file paths.

The model cache was reused: all 12,177 dependency hashes match, with 1,270 ready
portraits and the same known camera exception for quest 97290. The full offline
verification report was updated to match the new catalogue.

A consistent SQLite backup, pending inbox, previous catalogue and model reports
are in `/srv/talkinghead/backups/20261012-catquest-0.6.1` (root-only directory).
An additional SQLite copy is in the ignored local directory
`artifacts/voice-vote-deploy/updates/catquest-0.6.1/backup/`. This is a one-time
deployment backup, not a scheduled backup service. Audio and secrets are excluded.

To roll back this data update, stop web/API, restore the three catalogue JSON
files and model reports from that backup, then start both services with the
Compose command above. Previous audio files are still available. Keep the live
votes volume: a catalogue rollback must not overwrite votes collected since
the backup. The staged new metadata is in
`/srv/talkinghead/import/catquest-0.6.1-20261012/`.

### Initial deployment

Deployment completed on 2026-10-12. Both containers are healthy,
all 9,207 audio hashes and 12,177 model dependency hashes match the local snapshot,
the catalogue contains 3,576 quests, and portrait rendering, two audio variants,
admin login and JSON export work through the public HTTPS address. No test ballots were
submitted to the production database. No external browser asset requests were
needed. Container memory after the public browser check was about 373 MiB combined.

HTTP redirects to HTTPS. Let's Encrypt issued the initial certificate, expiring
on 2027-01-10; `certbot.timer` renews it automatically. A successful renewal
reloads Nginx via `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx`.
The renewal dry run passed. The host configuration is
`/etc/nginx/sites-available/talkinghead-vote`; the ACME webroot is
`/var/www/letsencrypt`.

The deployment helper `/srv/talkinghead/enable-https.sh` checks authoritative
and public DNS before requesting a certificate. A hostname entry in the Timeweb
panel is not sufficient until its DNS record is published. Routine certificate
renewal uses Certbot's timer and does not require rerunning the deployment helper.
