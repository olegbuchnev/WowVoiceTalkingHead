# Participation dashboard

Open http://127.0.0.1:8081/admin/ locally, or `/admin/` on the deployed API host.
Enter the password from `config/voice-vote-admin-password.local.txt` at the
repository root. The local file is ignored by Git. If it does not exist, create
a random password of 20–64 ASCII characters in it and restart the Java server.
There is no default password; missing configuration disables login.

The panel shows participating visitors, visits with a saved vote, retained votes,
daily activity, library choices and individual visitor details. Filter by period
or search an anonymous visitor ID. Details list recent visits, recording starts,
quest choices, race, sex and recording version. Refresh updates the report.

## Counting rules

- A visitor is identified by the existing anonymous voter cookie. Only its hash
  is stored. Clearing the cookie creates another identity, not another confirmed person.
- A page load creates a temporary visit ID in browser memory. The server creates
  the visit only when it successfully commits its first ballot. Opening the page
  or listening without voting does not count as a visit or dashboard participant.
- Refreshing the page starts another visit, counted only after another vote.
  The same cookie links both visits to one visitor.
- Recording starts before the first vote stay in memory. After confirmation they
  are submitted, deduplicated by recording within the visit. These are playback
  starts, not completed listens. Failed analytics requests never block voting.
- A visitor has one retained vote per exact comparison. Another choice replaces
  it; changed recording hashes create a new comparison. Per-visit vote counts can
  therefore exceed the number of retained votes across several visits.
- Periods and daily charts use UTC. Retained votes are attributed to their first
  saved date, even when their selection changes later. Participants include those
  returning to change an earlier vote in the period.
- Existing votes and anonymous identities are included immediately. Historical
  visits cannot be reconstructed; their counts begin when analytics is enabled.
  Technical cookie identities without votes are excluded from the participant list.
- No IP addresses, browser fingerprints or full browsing histories are collected
  by this analytics code. Library totals include historical recordings and are
  participation statistics, not a version-normalized quality ranking.

## Access and deployment

The admin UI is built from `admin/` into Java static resources before packaging.
Docker builds it automatically. For manual Java/IDE builds, run `npm ci --prefix
admin` and `npm run build --prefix admin` from `server/voice-vote`, then rebuild Java.
The local launcher also builds changed admin assets.

Set `VOICE_VOTE_ADMIN_PASSWORD_FILE` to a private secret file on the host. Docker
Compose mounts it at `/run/secrets/admin_password`. The password is read on startup
and hashed in memory with BCrypt; changing it requires restarting the server.
Keep it out of source control, logs, image archives and public frontend assets.

Use HTTPS in production and `VOICE_VOTE_SECURE_COOKIE=true`. Proxy `/admin`,
`/api/admin` and `/api/votes` to Java while preserving Host. Authentication uses
a separate HttpOnly, SameSite=Strict session cookie, a 30-minute inactivity
timeout and CSRF tokens. Logout invalidates the session. Admin responses disable
caching. Login allows at most 20 attempts per minute per server process; this is
a shared limit, without collecting client IPs. Sessions reset on server restart.

SQLite schema 2 adds analytics tables without rewriting existing votes. Include
them in the same consistent database backups described in [DOCKER.md](DOCKER.md).
Aggregate exports remain unchanged and exclude individual visitor identities.

## Download results

The authenticated panel has buttons for `results.json`, `quests.csv`,
`race-sex.csv`, `pairwise.csv` and a ZIP containing all four. These use the same
exporter as the command-line tool, with a consistent read-only database snapshot.
Downloads include all committed votes, regardless of the dashboard period filter;
pending ballots appear after they are committed. No visitor IDs are exported.
Only one export runs at a time. The `/api/admin/export/{file}` endpoints require
an authenticated admin session and disable caching.

## Background saving

The "Saving votes" section shows server inbox depth, oldest admission, last
successful commit, write errors and the first 30 waiting ballots (visitor/quest).
It refreshes every five seconds and ignores the report date filter. Processing
and error counters cover the current server process; queued ballots survive restarts.
Participant and vote statistics count committed votes only.

The public UI reacts immediately. HTTP 202 from `/api/votes/submit` acknowledges
durable admission, not a completed database write. Transient database errors leave
the ballot in the inbox and trigger a retry after five seconds. The worker keeps
FIFO order, including replacement choices. Previously accepted library snapshots
remain valid for the worker after a catalogue update. There is no new persistent
queue in the browser. Unreceived requests cannot appear in the server dashboard.
Permanent visit-ownership conflicts are preserved as `.failed` files and counted
separately for investigation; they never block unrelated ballots. Admission
errors are also shown, including a full inbox or unavailable disk.

The inbox lives at `<database path>.pending/`, next to SQLite, inside the same
persistent Docker volume. Keep this directory when upgrading or restoring. Never
run two server instances against the same database/inbox; a file lock enforces
single ownership of the inbox. The default admission limit is 10,000 ballots;
`voice-vote.inbox-capacity` configures it. A full inbox rejects admission with 503;
the open browser page silently retries. Do not remove queued JSON files manually.

For a complete backup, stop Java and preserve both SQLite and its `.pending`
directory, or wait for an empty inbox before taking the usual SQLite online
backup. Aggregate exports include only committed votes. File contents are forced
to disk before admission; Linux directory entries are synced too. Use a local
persistent filesystem with atomic rename support.
