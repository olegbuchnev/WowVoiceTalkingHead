# Docker deployment

For the complete React site with a private Java API, use the
[full-site Compose instructions](../../web/voice-vote/DOCKER.md). The standalone
Compose below exposes Java on loopback for development or a separately managed
frontend proxy.

The image contains the Java voting API, the React admin panel and the results-export CLI.
The public voting frontend, audio files, model assets, catalogue and real votes are not baked into it.
The runtime uses the official [Eclipse Temurin Java 25 image](https://hub.docker.com/_/eclipse-temurin),
runs as UID/GID 10001, and includes an HTTP health check. The multi-stage build
runs the Java tests before packaging the runtime.

## Prepare on the development machine

From the repository root:

```shell
node web/voice-vote/export-vote-catalogue.mjs artifacts/voice-vote-deploy/catalogue.json
docker build -t talkinghead-vote-server:local server/voice-vote
docker save -o artifacts/voice-vote-deploy/talkinghead-vote-server.tar talkinghead-vote-server:local
```

The default image targets the builder's platform (tested on Linux amd64).
For an ARM host build with `docker buildx build --platform linux/arm64 --load ...`
on a builder that supports that platform. No registry publication is automatic.
Alternatively tag and push to your chosen registry, then set `VOICE_VOTE_IMAGE`
on the host to that tag/digest.

## Start on the host

Transfer the image archive, `compose.yaml`, `.env.example` and `catalogue.json`.
Place the catalogue in its own directory, for example `/srv/talkinghead/catalogue`.
Next to `compose.yaml`, copy `.env.example` to `.env` and set its absolute
`VOICE_VOTE_CATALOGUE_DIR` path. Create a strong admin password (20–64 ASCII
characters) in a private file readable by container UID 10001, and set
`VOICE_VOTE_ADMIN_PASSWORD_FILE` to its absolute host path. Compose mounts it as
a read-only secret; never include it in the image or Git. Then run:

```shell
docker load -i talkinghead-vote-server.tar
docker compose up -d --no-build --wait
docker compose logs --tail 100 api
```

The API is published on host loopback `127.0.0.1:8081` by default. Set
`VOICE_VOTE_HOST_PORT` if occupied. Route `/api/votes`, `/api/admin` and `/admin`
through the site's HTTPS
reverse proxy, preserving the browser's original Host. Secure cookies default
to true in Compose; set false only for local HTTP testing. A proxy in another
container must share a Docker network with the API instead of using host loopback.
The API listens on `0.0.0.0` inside the container (`SERVER_ADDRESS`).

Open `/admin/` to sign in. See [ADMIN.md](ADMIN.md) for access and counting rules.

The named `votes` volume stores `/data/votes.sqlite`, WAL files, the durable
`/data/votes.sqlite.pending/` inbox and `/data/exports`.
It survives image upgrades and container recreation. Keep the Compose project
name stable. `docker compose down` keeps it; **do not use `down --volumes` for
production**, as that deletes the stored votes. Named-volume behavior is described
in the [Docker documentation](https://docs.docker.com/engine/storage/volumes/).

The catalogue directory is mounted read-only. Replace `catalogue.json` atomically
inside that directory after library updates; the API reads the new snapshot.
Mounting the directory allows replacement without keeping an old bound inode.
For an image update, load/pull it and run `docker compose up -d --no-build --wait`.

## Export and preserve existing data

```shell
docker compose exec -T api java --enable-native-access=ALL-UNNAMED -jar /app/server.jar export-results
docker compose cp api:/data/exports ./exports
```

See [RESULTS.md](RESULTS.md) for JSON/CSV fields and version-aware counting rules.
An export is aggregate reporting, **not a database backup**.

A fresh volume starts empty. The image does not automatically import development
votes. To migrate them, stop the source API and take its SQLite file, or create a
consistent online backup using SQLite's backup API (never copy only the main file
from an active WAL database). On the target, stop the API, put the backup at
`/data/votes.sqlite` in its volume, ensure UID/GID 10001 can write the database
and directory, then start the API. Preserve the original backup. Take regular
consistent SQLite backups in addition to exported aggregates.

Accepted votes may still be in the inbox. For a complete stopped-server backup,
preserve `votes.sqlite.pending/` alongside SQLite. For an online SQLite-only
backup/export, wait until the admin inbox is empty to include all accepted votes.

## Local container verification

After building the image, from the repository root:

```shell
python server/voice-vote/tests/docker-smoke.py
```

Requires Docker Compose and a prepared local catalogue. The test creates its own
randomly named Compose project, verifies health, a vote, container recreation,
cookie/volume persistence and live export, then removes only its test containers
and volumes. It never writes to the development voting database.
