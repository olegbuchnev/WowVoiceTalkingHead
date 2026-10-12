# Timeweb Cloud deployment

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
