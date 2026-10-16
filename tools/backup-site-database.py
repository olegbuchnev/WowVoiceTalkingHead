"""Download a consistent Timeweb voting database snapshot using OpenSSH.

The same standard-library-only script runs remotely through python3's stdin.
Only the database volume and deployed JSON catalogue are archived; no audio.
"""

from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE, **kwargs).stdout.strip()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_container(container):
    return json.loads(run("docker", "inspect", container))[0]


def copy_data(source, destination):
    # Fail closed on links/special files or unexpected audio, including nested files.
    for item in [source, *source.rglob("*")]:
        if item.is_symlink() or not (item.is_dir() or item.is_file()):
            raise RuntimeError(f"Unsupported database entry: {item}")
        if item.suffix.lower() == ".ogg":
            raise RuntimeError(f"Audio must not enter database backups: {item}")
    shutil.copytree(source, destination)


def check_database(path):
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as connection:
        result = connection.execute("PRAGMA integrity_check").fetchall()
        if result != [("ok",)]:
            raise RuntimeError(f"SQLite integrity check failed: {result}")
        tables = [row[0] for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        return {name: connection.execute(
            'SELECT COUNT(*) FROM "' + name.replace('"', '""') + '"').fetchone()[0]
            for name in tables}


def snapshot(app, destination):
    compose = ["docker", "compose", "--project-directory", str(app),
               "-f", str(app / "compose.yaml"), "-f", str(app / "compose.production.yaml")]
    container = run(*compose, "ps", "-aq", "api")
    if not container or "\n" in container:
        raise RuntimeError("Expected exactly one existing API container")
    info = inspect_container(container)
    mounts = {mount["Destination"]: Path(mount["Source"]) for mount in info["Mounts"]}
    data, catalogue = mounts["/data"], mounts["/catalogue"]
    if not (data / "votes.sqlite").is_file():
        raise RuntimeError("The deployed votes.sqlite database is missing")
    was_running = info["State"]["Running"]
    try:
        if was_running:
            run("docker", "stop", "--time", "60", container)
        if inspect_container(container)["State"]["Running"]:
            raise RuntimeError("API is still running; refusing an inconsistent copy")
        copy_data(data, destination / "data")
        (destination / "catalogue").mkdir()
        for name in ("catalogue.json", "site-catalogue.json", "audio-manifest.json"):
            source = catalogue / name
            if source.is_symlink() or not source.is_file():
                raise RuntimeError(f"Missing or linked catalogue: {source}")
            shutil.copy2(source, destination / "catalogue" / name)
    finally:
        if was_running:
            run("docker", "start", container)
            deadline = time.monotonic() + 120
            while True:
                state = inspect_container(container)["State"]
                health = state.get("Health", {}).get("Status", "none")
                if state["Running"] and health in ("healthy", "none"):
                    break
                if not state["Running"] or time.monotonic() >= deadline:
                    raise RuntimeError("API failed to recover after snapshot; inspect docker logs")
                time.sleep(2)
    # The service is back before integrity checks, compression and downloading.
    counts = check_database(destination / "data" / "votes.sqlite")
    manifest = {
        "createdUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "applicationDirectory": str(app), "apiImage": info["Config"]["Image"],
        "apiImageId": info["Image"], "apiWasRunning": was_running,
        "sqliteIntegrity": "ok", "tableRows": counts,
        "files": {str(p.relative_to(destination)).replace(os.sep, "/"): sha256(p)
                  for p in sorted(destination.rglob("*")) if p.is_file()},
    }
    (destination / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def remote_backup(app):
    import fcntl  # Only the Linux host needs this module.
    import signal
    # Finish the snapshot/restart even if the SSH client disconnects.
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    app = Path(app).resolve(strict=True)
    # Lock across the full snapshot; a concurrent backup must not restart our API.
    with (app / ".database-backup.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.umask(0o077)
        backups = app / "backups"
        backups.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="database-snapshot-", dir=backups) as temporary:
            destination = Path(temporary)
            manifest = snapshot(app, destination)
            archive = backups / (destination.name + ".tar.gz")
            partial = archive.with_suffix(archive.suffix + ".partial")
            with tarfile.open(partial, "w:gz") as bundle:
                for item in sorted(destination.iterdir()):
                    bundle.add(item, arcname=item.name)
            partial.rename(archive)
        print(json.dumps({"archive": str(archive), "sha256": sha256(archive),
                          "bytes": archive.stat().st_size, "manifest": manifest}))


def download():
    root = Path(__file__).resolve().parent.parent
    required = ("TALKINGHEAD_SITE_SSH_HOST", "TALKINGHEAD_SITE_SSH_KEY", "TALKINGHEAD_SITE_REMOTE_DIR")
    missing = [name for name in required if not os.environ.get(name, "").strip()]
    if missing:
        raise RuntimeError("Set in config/build.env.local.ps1 or environment: " + ", ".join(missing))
    host = os.environ["TALKINGHEAD_SITE_SSH_HOST"]
    key = Path(os.environ["TALKINGHEAD_SITE_SSH_KEY"]).expanduser()
    app = os.environ["TALKINGHEAD_SITE_REMOTE_DIR"]
    if not key.is_absolute():
        key = root / key
    if not re.fullmatch(r"/[A-Za-z0-9_./-]+", app):
        raise RuntimeError("TALKINGHEAD_SITE_REMOTE_DIR must be an absolute Linux path without spaces")
    output = Path(os.environ.get("TALKINGHEAD_SITE_BACKUP_DIR", str(root / "backups/site-database"))).expanduser()
    if not output.is_absolute():
        output = root / output
    if not re.fullmatch(r"[A-Za-z0-9_.@-]+", host) or host.startswith("-"):
        raise RuntimeError("Invalid TALKINGHEAD_SITE_SSH_HOST (expected user@host)")
    if not key.is_file():
        raise RuntimeError(f"SSH key not found: {key}; set TALKINGHEAD_SITE_SSH_KEY")
    for command in ("ssh", "scp"):
        if not shutil.which(command):
            raise RuntimeError(f"Install OpenSSH: missing {command}")
    output.mkdir(parents=True, exist_ok=True)
    options = ["-i", str(key), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
               "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15",
               "-o", "ServerAliveCountMax=4"]
    print(f"Taking database snapshot on {host}; the voting API will pause briefly.", flush=True)
    command = "python3 - --remote " + shlex.quote(app)
    result = json.loads(run("ssh", *options, host, command,
                            input=Path(__file__).read_text(encoding="utf-8"), encoding="utf-8"))
    remote = result["archive"]
    # The remote-generated path must also be safe for scp's remote-path syntax.
    if not re.fullmatch(r"/[A-Za-z0-9_./-]+", remote):
        raise RuntimeError(f"Unsupported remote archive path: {remote}")
    name = time.strftime("%Y%m%d-%H%M%S", time.gmtime()) + "-" + Path(remote).name
    archive = output / name
    partial = archive.with_suffix(archive.suffix + ".partial")
    print(f"API state preserved. Downloading {result['bytes']:,} bytes; server copy: {remote}", flush=True)
    run("scp", *options, host + ":" + remote, str(partial))
    if partial.stat().st_size != result["bytes"] or sha256(partial) != result["sha256"]:
        raise RuntimeError(f"Downloaded archive failed SHA-256/size verification: {partial}")
    partial.rename(archive)
    archive.with_suffix(archive.suffix + ".sha256").write_text(
        result["sha256"] + "  " + archive.name + "\n", encoding="ascii")
    archive.with_suffix(archive.suffix + ".json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Backup verified: {archive}\nSQLite integrity: ok\nTables: {result['manifest']['tableRows']}")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--remote":
            remote_backup(sys.argv[2])
        elif len(sys.argv) == 1:
            download()
        else:
            raise RuntimeError("Usage: python tools/backup-site-database.py")
    except Exception as error:
        print(f"Database backup failed: {error}", file=sys.stderr)
        sys.exit(1)
