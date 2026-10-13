# Voice voting server

Java 25, Spring Boot 4.1.1, SQLite. Source code belongs to this repository;
the database and local catalogue are excluded from Git and addon packages.

Model preparation and incremental updates when the quest catalogue grows:
[step-by-step instructions](../../web/voice-vote/MODEL-CACHE.md).
The model cache belongs to the web service; Java does not download models.

## Local launch

Run `voice-vote.cmd` from the repository root. It exports the trusted catalogue,
builds the Java application when needed, and starts both services in the
background. Open http://127.0.0.1:5174/ manually. The Java API listens on
127.0.0.1:8081; Vite proxies `/api/votes` while preserving the browser's Host.
The launcher prints process IDs and stop commands. Logs are in
`artifacts/voice-vote-preview/`.

Local preview prerequisites: JDK 25+, Node.js and the project's installed voice libraries.
The standalone Java API requires only Java 25+, a prepared catalogue and writable
database storage. It does not need WoW, Node.js, the repository or network access
to model services.
Maven Wrapper downloads the pinned Maven distribution automatically.
The root Node dependencies are needed by the catalogue exporter (`npm ci`).
For foreground Java development, from this directory:

```powershell
node ../../web/voice-vote/export-vote-catalogue.mjs
npm ci --prefix admin
npm run build --prefix admin
./mvnw.cmd verify
java --enable-native-access=ALL-UNNAMED -jar target/voice-vote-server-0.1.0.jar
```

Default paths are relative to this directory. Configuration overrides:

| Environment variable | Default |
| --- | --- |
| `VOICE_VOTE_PORT` | `8081` |
| `VOICE_VOTE_DB` | `../../data/voice-vote/votes.sqlite` |
| `VOICE_VOTE_CATALOGUE` | `../../data/voice-vote/catalogue.json` |
| `VOICE_VOTE_SECURE_COOKIE` | `false` (local HTTP only) |
| `VOICE_VOTE_ADMIN_PASSWORD_FILE` | `../../config/voice-vote-admin-password.local.txt` |

`VOICE_VOTE_API` configures the Vite proxy target for a non-default API port.
The convenience launcher uses the default ports. Use separate foreground
processes when overriding them.

## Data and API

- `GET /api/votes/health`: application identifier.
- `GET /api/votes/summary`: personal library counters; creates an anonymous
  `HttpOnly`, `SameSite=Lax` cookie with a random 256-bit token, valid for one year.
  Only its SHA-256 hash is stored in the database. No login or fingerprinting.
- `GET /api/votes/queue`: current quest priorities (`questID`, `rated`, `votes`).
  Requires the visitor cookie and disables caching. Unrated comparisons come
  first, then the lowest global vote counts, with randomized ties. Counts refer
  to exact current comparisons, so changed recording IDs start at zero while
  library version numbers alone do not reset coverage.
- `POST /api/votes`: `{questID, selectedId, variantIds}`. Requires the visitor
  cookie, a same-origin request and a JSON body of at most 16 KiB.
  Returns the confirmed source and updated personal counters.

The trusted catalogue supplies NPC ID, display ID, model file ID, race, sex,
library version and audio hashes. Browser-supplied metadata is not used.
It includes every description with verified audio from at least two distinct
libraries, not just the three original fixtures. Wayfarer modules count as one
source. Unknown NPC/display/model IDs use 0; unknown race and sex use null.
Blocked or ambiguous givers are not assigned an arbitrary NPC. Their votes are
still stored by quest, with unknown demographics kept separate from known groups.
The exporter writes `catalogue.coverage.json` alongside the snapshot, listing
missing speaker fields and model-resolution errors. This report is not required
by the Java runtime. All catalogue data lives under `data/voice-vote`, separately
from server source code; on hosting, configure its path with `VOICE_VOTE_CATALOGUE`.
The exporter reads and hashes installed audio directly and resolves Forever model
IDs on the preparation machine. Its deterministic schema version 2 JSON contains
only metadata: no local paths, audio URLs or audio files. The Java API validates
this snapshot at startup and on voting requests, and checks ballots against its
recording IDs. Legacy path-bearing catalogues and invalid snapshots are rejected.
Runtime audio access is not needed. Replacing the snapshot changes the accepted
comparison IDs; ballots for previous recordings receive HTTP 409.

Refresh the catalogue and restart Vite after updating library metadata. The local
audio service also verifies each requested file before delivering those exact
bytes, including Range requests; replacing an installed recording cannot silently
serve different audio under its previous ID. A future public audio host must
likewise serve immutable recordings matching the published IDs and hashes.
The Java API trusts the prepared catalogue; it does not rehash remotely served
audio when receiving a vote.

Each variant also carries `revisions`: up to three distinct SHA-256 values from
the shared per-file history, newest observed first. Unchanged files across pack
releases occupy one slot. The exporter refuses current recordings outside this
audited window; the server validates unique hashes and membership of the current
hash. Re-export the catalogue when upgrading from schema 1. Existing SQLite
votes remain compatible and retain their original comparison IDs.
This window does not make old audio available on the site or transfer ratings
to new bytes. The site compares prepared current recordings, not files installed
in a visitor's game. Applying ratings in the addon is a separate future step.

SQLite stores comparisons and votes in a transaction with a schema version.
The key is visitor + quest description + speaker + sorted recording IDs.
Retries update the existing vote; choosing another source changes that vote.
Library version changes alone do not create another comparison. Changed
recording bytes produce a new ID and an independent comparison. Earlier votes
remain associated with their original recordings. The full candidate snapshot
is stored, including versions and hashes; absolute audio paths are not in votes.

Race and sex are part of the comparison identity. Correcting a voice category
from `tauren` to the distinct `furbolg` race creates a new comparison, even when
the recordings and portrait stay the same. Do not migrate or inherit the old
ballots: they remain historical, while the corrected race starts with no votes.
The `race-sex.csv` and pairwise exports aggregate current comparisons only;
historical rows with the former classification must not seed either race's
future recommendations. Confirmed 2026-10-13.
The `ancient` and `furbolg` categories each use one group without sex divisions;
`sex=male` is their canonical schema value, regardless of previous library labels.

The client displays each choice immediately and submits it to `POST /api/votes/submit`.
HTTP 202 means the trusted ballot is accepted in a durable server-side inbox,
not yet committed to SQLite. A single worker commits accepted ballots in order,
retrying storage errors. Restarting the server resumes pending work; replay after
a crash is idempotent. The synchronous `/api/votes` endpoint remains for legacy clients.
The browser keeps only in-flight requests in memory and silently retries transient
admission failures while the page remains open. There is no persistent browser queue:
closing the page before admission can lose an unaccepted choice. Accepted choices
survive browser closure. Pending accepted comparisons are excluded from unrated
recommendations for that cookie, including after page reload.

The catalogue is validated once and cached until its file stamp changes. Deploy
catalogue updates by atomic replacement. Read-only database connections are bounded
to eight concurrent queries; the writer connection is separate. WAL allows reports
and queue reads to run alongside short write transactions.

The client keeps no growing history of new votes in localStorage. Old prototype votes
are imported sequentially and removed only after acknowledgement; unverifiable
old recordings remain in localStorage. Repeated old choices collapse into one
vote per comparison. Migration uses the time of import, not a trusted historical
vote timestamp.

Deleting the cookie starts a new anonymous visitor; the old server votes remain.
This is anonymous browser identity, not protection against deliberate repeat
voting from multiple browsers. Personal counters count distinct comparisons.
The UI chart counts local choices immediately since page load and resets on refresh;
the persisted votes and cookie remain. The queue waits for server priorities
before reserving its first two portraits and refreshes them before each batch.
Already reserved portraits stay unchanged. A batch includes at most five unrated
quests, without padding it with repeats. The next batch starts only on request;
after exhaustion, replay batches require an explicit action. If priorities cannot be loaded at startup,
the client warns about possible repeats and falls back to random catalogue order.

## Hosting and backups

Docker image, Compose deployment and transfer instructions: [DOCKER.md](DOCKER.md).
Protected participation dashboard: [ADMIN.md](ADMIN.md).
Version-aware JSON/CSV export: [RESULTS.md](RESULTS.md), machine-readable contract:
[results.schema.json](results.schema.json).

This implementation runs locally; it has not been publicly deployed. A public
deployment needs a Java-capable host with persistent storage, HTTPS and a
same-origin reverse proxy preserving Host. Enable secure cookies there.
GitHub stores the source; GitHub Pages cannot execute this Java API.
Serving audio/models publicly is a separate deployment step.

Prepare a portable catalogue from the repository root:

```powershell
node web/voice-vote/export-vote-catalogue.mjs artifacts/voice-vote-deploy/catalogue.json
```

Copy the built `server/voice-vote/target/voice-vote-server-0.1.0.jar` as
`server.jar` and the exported `catalogue.json` to the host. From that directory:

```shell
java --enable-native-access=ALL-UNNAMED -jar server.jar --voice-vote.catalogue=./catalogue.json --voice-vote.database=./data/votes.sqlite
```

These paths belong to the deployment directory, not the preparation machine.
Keep the existing database when deploying a new JAR or catalogue. Replace the
catalogue atomically, rather than writing over a file used by active requests.
The snapshot format version describes its schema; recording IDs and SHA-256
identify the audio revisions. It is not a signature or proof of origin.

Back up `data/voice-vote/` with the API stopped, or use SQLite's online backup
API. Do not copy only `votes.sqlite` from a running WAL database.
No automatic deletion of votes or retention limits are configured.

## Verification

`./mvnw.cmd verify` checks HTTP validation, cookie isolation, changed catalogue IDs,
duplicate/replacement votes, trusted speaker metadata and persistence across
server restarts. Java fixtures contain no audio files. `npm run test:browser`
in `web/voice-vote` copies only the JAR and portable catalogue into a temporary
directory, removes the AddOns environment setting, and starts Java there with
a new database. Vite runs separately with random ports. Build the JAR first.
Test votes never enter the normal local database. Node tests also verify that
the export contains no audio paths and changed audio fails delivery validation.
