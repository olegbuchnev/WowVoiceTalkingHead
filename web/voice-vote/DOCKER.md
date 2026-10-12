# Voting site deployment

For the current Timeweb host and its 2 GB memory limits, see [HOSTING.md](HOSTING.md).

The site uses two Linux containers: `web` serves the built React application,
Nginx and a small audio/model asset service; `api` runs Java, SQLite and the admin
panel. Only the web port is published, on host loopback. Java is reachable through
the Compose network. Both containers run as non-root users.

Before public deployment, follow [model-cache preparation](MODEL-CACHE.md),
including the full offline check and import into the `model_cache` volume.
Set `VOICE_VOTE_MODEL_OFFLINE=true` after import to disable upstream cache misses.

## Build and prepare data

From the repository root, with the current external voice libraries installed:

```shell
node web/voice-vote/export-site.mjs artifacts/voice-vote-deploy/catalogue
docker build -t talkinghead-vote-web:local -f web/voice-vote/Dockerfile .
docker build -t talkinghead-vote-server:local server/voice-vote
docker save -o artifacts/voice-vote-deploy/talkinghead-vote-web.tar talkinghead-vote-web:local
docker save -o artifacts/voice-vote-deploy/talkinghead-vote-server.tar talkinghead-vote-server:local
```

The exporter creates `catalogue.json` for Java, `site-catalogue.json` for the
public UI and `audio-manifest.json` with relative paths and hashes, plus a coverage
report. It copies no audio. Export all files together after library updates.
No local Windows paths, database, credentials or external OGG files enter either
image. Builds target the builder's platform (tested on Linux amd64).

## Start on a host

Transfer both image archives, this directory's `compose.yaml`, `.env.example` and
the exported `catalogue/` directory. Install the external voice libraries in a
separate host directory, preserving the AddOns-relative folder/file structure
listed in `audio-manifest.json`. Mount that directory read-only; do not package
its audio into images or release archives. It must match the exported hashes.

Copy `.env.example` to `.env` beside Compose and set absolute host paths:

- `VOICE_VOTE_CATALOGUE_DIR`: the directory with all three JSON files.
- `VOICE_VOTE_LIBRARIES_DIR`: the external libraries directory.
- `VOICE_VOTE_ADMIN_PASSWORD_FILE`: a private file containing a random password
  of 20–64 ASCII characters, readable by Java UID 10001.
- `VOICE_VOTE_SECURE_COOKIE=true` for HTTPS. Use `false` only for local HTTP.

```shell
docker load -i talkinghead-vote-web.tar
docker load -i talkinghead-vote-server.tar
docker compose up -d --no-build --wait --wait-timeout 180
docker compose logs --tail 100 web api
```

Locally open `http://127.0.0.1:8080/`; the admin panel is at `/admin/` on the same
address. The first startup checks all mapped library files and can take longer
with Docker Desktop bind mounts. Models are fetched on demand from Wowhead and
cached in the `model_cache` volume. Audio is read directly from the mounted
libraries and hash-checked when served. An updated file with an old hash is
rejected instead of being evaluated as the old recording.

For public access, use an HTTPS reverse proxy on the host to forward the entire
site to `127.0.0.1:8080`, preserving the original `Host` header. Users visit that
HTTPS domain for both the site and API. Do not publish Java's port. A reverse proxy
running in another container should join the Compose network and target `web:8080`.

## Browser access protection

The frontend uses relative API URLs. Nginx rejects API/admin requests with a
foreign Origin or cross-origin Fetch Metadata, including cross-origin preflight,
and sends no permissive CORS headers. Voting routes have a burst-tolerant request
limit per voter cookie (per source address before a cookie exists). Admin access
still requires its password/session and CSRF protection.

This prevents another browser origin from using the API. It cannot prove that an
HTTP client is the React application: anonymous public endpoints remain callable
by clients that construct equivalent requests. There is no secret in React.

## Updates and persistent data

The `votes` volume stores SQLite and the durable `.pending` inbox. Preserve both;
never use `docker compose down --volumes` on the real deployment. See the server
[backup instructions](../../server/voice-vote/DOCKER.md) and
[admin/export documentation](../../server/voice-vote/ADMIN.md).

The standalone Java Compose and this full-site Compose use the same project name
and votes volume. Stop the old stack with `docker compose down` (without
`--volumes`) before switching. Keep the project name unchanged to reuse its data.

After library updates, replace the catalogue snapshot and matching externally
installed libraries together, then restart both services. After camera or client
code changes, rebuild the web image; it reads the addon's shared Lua camera
profiles. Production does not read files from a developer checkout.

Image archives and metadata can be prepared locally without publishing anything.
The hosting domain, HTTPS certificate and external library installation remain
host configuration.
