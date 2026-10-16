"""Offline checks: real SQLite/WAL data, with Docker and SSH replaced by fixtures."""

import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "backup", Path(__file__).resolve().parents[1] / "tools/backup-site-database.py")
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.data = self.root / "volume"
        self.catalogue = self.root / "catalogue"
        self.destination = self.root / "snapshot"
        for directory in (self.data, self.catalogue, self.destination):
            directory.mkdir()
        self.connection = sqlite3.connect(self.data / "votes.sqlite")
        self.addCleanup(self.connection.close)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("CREATE TABLE votes (id INTEGER, text TEXT)")
        self.connection.execute("INSERT INTO votes VALUES (1, 'голос')")
        self.connection.commit()
        pending = self.data / "votes.sqlite.pending"
        pending.mkdir()
        (pending / "accepted.json").write_text('{"vote": 2}')
        (pending / "broken.failed").write_bytes(b"preserve quarantine")
        for name in ("catalogue.json", "site-catalogue.json", "audio-manifest.json"):
            (self.catalogue / name).write_text("{}")
        self.running = True
        self.commands = []

    def docker(self, *args, **kwargs):
        self.commands.append(args)
        if args[1] == "compose":
            return "fixture-api"
        if args[1] == "inspect":
            return json.dumps([{
                "Mounts": [{"Destination": "/data", "Source": str(self.data)},
                           {"Destination": "/catalogue", "Source": str(self.catalogue)}],
                "State": {"Running": self.running, "Health": {"Status": "healthy"}},
                "Config": {"Image": "fixture:local"}, "Image": "sha256:fixture",
            }])
        if args[1] in ("stop", "start"):
            self.running = args[1] == "start"
            return "fixture-api"
        raise AssertionError(args)

    def test_wal_pending_and_catalogue_survive(self):
        with patch.object(backup, "run", self.docker):
            manifest = backup.snapshot(self.root, self.destination)
        self.assertTrue(self.running)
        self.assertEqual(manifest["tableRows"], {"votes": 1})
        self.assertIn("data/votes.sqlite-wal", manifest["files"])
        self.assertEqual((self.destination / "data/votes.sqlite.pending/broken.failed").read_bytes(),
                         b"preserve quarantine")
        self.assertIn("catalogue/audio-manifest.json", manifest["files"])
        self.assertEqual(backup.check_database(self.destination / "data/votes.sqlite"), {"votes": 1})

    def test_copy_failure_restarts_api(self):
        with patch.object(backup, "run", self.docker), \
                patch.object(backup, "copy_data", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                backup.snapshot(self.root, self.destination)
        self.assertTrue(self.running)
        self.assertTrue(any(command[1] == "start" for command in self.commands))

    def test_stopped_api_stays_stopped(self):
        self.running = False
        with patch.object(backup, "run", self.docker):
            backup.snapshot(self.root, self.destination)
        self.assertFalse(self.running)
        self.assertFalse(any(command[1] in ("stop", "start") for command in self.commands))

    def test_audio_rejected_and_api_restarted(self):
        (self.data / "unexpected.OGG").write_bytes(b"not allowed")
        with patch.object(backup, "run", self.docker):
            with self.assertRaisesRegex(RuntimeError, "Audio must not enter"):
                backup.snapshot(self.root, self.destination)
        self.assertTrue(self.running)

    def test_missing_catalogue_restarts_api(self):
        (self.catalogue / "site-catalogue.json").unlink()
        with patch.object(backup, "run", self.docker):
            with self.assertRaisesRegex(RuntimeError, "Missing or linked catalogue"):
                backup.snapshot(self.root, self.destination)
        self.assertTrue(self.running)

    def test_missing_private_config_fails_before_ssh(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(backup, "run") as remote:
            with self.assertRaisesRegex(RuntimeError, "config/build.env.local.ps1"):
                backup.download()
            remote.assert_not_called()

    def test_corrupt_download_is_not_published(self):
        key = self.root / "key"
        key.write_text("fixture")
        output = self.root / "downloads"
        environment = {
            "TALKINGHEAD_SITE_SSH_HOST": "fixture",
            "TALKINGHEAD_SITE_SSH_KEY": str(key),
            "TALKINGHEAD_SITE_REMOTE_DIR": "/fixture",
            "TALKINGHEAD_SITE_BACKUP_DIR": str(output),
        }

        def transport(*args, **kwargs):
            if args[0] == "ssh":
                return json.dumps({"archive": "/fixture/backups/test.tar.gz", "bytes": 7,
                                   "sha256": "0" * 64, "manifest": {"tableRows": {}}})
            Path(args[-1]).write_bytes(b"corrupt")
            return ""

        with patch.dict(os.environ, environment), patch.object(backup, "run", transport), \
                patch.object(backup.shutil, "which", return_value="fixture"):
            with self.assertRaisesRegex(RuntimeError, "SHA-256/size"):
                backup.download()
        self.assertEqual(len(list(output.glob("*.partial"))), 1)
        self.assertEqual(list(output.glob("*.tar.gz")), [])


if __name__ == "__main__":
    unittest.main()
