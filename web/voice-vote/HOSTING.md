# Timeweb Cloud deployment

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

- Server: `81.19.135.168`, Ubuntu 26.04, 1 vCPU, 2 GB RAM, 30 GB disk.
- Site: https://talkingheadru.tw1.ru/ (free Timeweb technical domain).
- Admin panel: https://talkingheadru.tw1.ru/admin/.
- Application directory: `/srv/talkinghead`.
- SSH key: `~/.ssh/talkinghead_timeweb_ed25519` on the administrator's computer.
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
