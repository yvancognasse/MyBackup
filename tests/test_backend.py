import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import backend


class BackendTests(unittest.TestCase):
    def test_scan_excludes_application_runtime(self):
        with tempfile.TemporaryDirectory() as temp:
            parent = Path(temp)
            runtime = parent / "MyBackup"
            runtime.mkdir()
            (runtime / "token.json").write_text("secret")
            ordinary = parent / "ordinary"
            ordinary.mkdir()
            (ordinary / "data.txt").write_text("data")
            (ordinary / "outside-link.txt").symlink_to(runtime / "token.json")

            with patch.object(backend, "HOME", runtime):
                dirs, files = backend.scan_tree([parent], skip_hidden=False)

            self.assertNotIn(runtime, dirs)
            self.assertNotIn(runtime / "token.json", files)
            self.assertNotIn(ordinary / "outside-link.txt", files)
            self.assertIn(ordinary / "data.txt", files)

    def test_cache_uses_private_json(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "cache.json"
            sample = {"/example/file": {"size": 4, "mtime_ms": 123}}
            with patch.object(backend, "CACHE_FILE", path):
                backend.save_cache(sample)
                self.assertEqual(backend.load_cache(), sample)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertTrue(path.read_text().startswith("{"))

    def test_one_remote_listing_per_folder(self):
        with tempfile.TemporaryDirectory() as temp:
            parent = Path(temp)
            runtime = parent / "runtime"
            runtime.mkdir()
            source = parent / "source"
            source.mkdir()
            for index in range(100):
                (source / f"{index:03d}.txt").write_text("content")
            config = runtime / "config"
            config.write_text(f"SOURCE_DIRS={source}\nMAX_WORKERS=8\n")
            calls = {"list": 0, "upload": 0}

            def list_folder(service, folder_id):
                calls["list"] += 1
                return {}

            def upload_file(service, path, folder_id, drive_item, cfg):
                calls["upload"] += 1
                return "created"

            with (
                patch.object(backend, "HOME", runtime),
                patch.object(backend, "ENV_FILE", config),
                patch.object(backend, "CACHE_FILE", runtime / "cache.json"),
                patch.object(backend, "LOG_FILE", runtime / "run.log"),
                patch.object(backend, "authenticate", return_value=object()),
                patch.object(backend, "build_service", return_value=object()),
                patch.object(backend, "get_service", return_value=object()),
                patch.object(backend, "get_or_create_folder", return_value=("remote", False)),
                patch.object(backend, "list_folder", side_effect=list_folder),
                patch.object(backend, "upload_file", side_effect=upload_file),
                patch.object(backend, "emit"),
            ):
                backend.run_backup()
                self.assertEqual(len(backend.load_cache()), 100)

            self.assertEqual(calls, {"list": 1, "upload": 100})


if __name__ == "__main__":
    unittest.main()
