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

    def test_cache_is_bound_to_destination_and_source_mapping(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "cache.json"
            first = {"root_id": "drive-A", "sources": ["/source"]}
            sample = {"/source/file": {"size": 4}}
            with patch.object(backend, "CACHE_FILE", path):
                backend.save_cache(sample)  # Legacy cache must be ignored in production.
                self.assertEqual(backend.load_cache(first), {})
                backend.save_cache(sample, first)
                self.assertEqual(backend.load_cache(first), sample)
                self.assertEqual(backend.load_cache({**first, "root_id": "drive-B"}), {})
                self.assertEqual(backend.load_cache({**first, "sources": ["/other"]}), {})
                self.assertEqual(backend.load_cache(first), sample)

    def test_changed_during_upload_is_not_cached_and_retries(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "file.txt"
            path.write_text("before")
            cache = {str(path): {"size": -1}}
            stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
            cfg = {"HTTP_TIMEOUT_SECONDS": 1}
            def changing_upload(*args):
                path.write_text("modified during upload")
                return "created"
            with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "write_log"), patch.object(backend, "upload_file", side_effect=changing_upload):
                result = backend.process_one_file(path, "folder", object(), cfg, cache, stats, {})
            self.assertEqual(result, "error")
            self.assertNotIn(str(path), cache)
            self.assertEqual(stats["errors"], 1)
            with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "upload_file", return_value="updated") as upload:
                self.assertEqual(backend.process_one_file(path, "folder", object(), cfg, cache, stats, {}), "updated")
                self.assertTrue(backend.unchanged(path, cache))
                self.assertEqual(backend.process_one_file(path, "folder", object(), cfg, cache, stats, {}), "skipped")
                self.assertEqual(upload.call_count, 1)

    def test_changed_source_updates_even_a_newer_remote_copy_of_same_size(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "file.txt"
            path.write_text("data")
            stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
            remote = {path.name: {"id": "existing", "size": 4, "modifiedTime": "2099-01-01T00:00:00Z"}}
            with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "upload_file", return_value="updated") as upload:
                self.assertEqual(backend.process_one_file(path, "folder", object(), {"HTTP_TIMEOUT_SECONDS": 1}, {}, stats, remote), "updated")
                self.assertEqual(upload.call_args.args[3]["id"], "existing")

    def test_missing_and_unreadable_sources_raise_instead_of_succeeding(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(FileNotFoundError):
                backend.scan_tree([root / "disconnected"], True)
            def unreadable(*args, **kwargs):
                kwargs["onerror"](PermissionError("Access denied"))
                return iter(())
            with patch.object(backend.os, "walk", side_effect=unreadable), self.assertRaisesRegex(OSError, "incomplete"):
                backend.scan_tree([root], True)

    def test_destination_change_uploads_again_and_same_destination_skips(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            runtime = root / "runtime"
            runtime.mkdir()
            source = root / "source"
            source.mkdir()
            (source / "file.txt").write_text("data")
            config = runtime / "config"
            config.write_text(f"SOURCE_DIRS={source}\nDRIVE_FOLDER_NAME=first\n")
            with (
                patch.multiple(backend, HOME=runtime, ENV_FILE=config, CACHE_FILE=runtime / "cache.json", LOG_FILE=runtime / "run.log"),
                patch.object(backend, "authenticate", return_value=object()),
                patch.object(backend, "build_service", return_value=object()),
                patch.object(backend, "get_service", return_value=object()),
                patch.object(backend, "get_or_create_folder", side_effect=lambda service, name, parent=None: (f"{parent}/{name}", False)),
                patch.object(backend, "list_folder", return_value={}),
                patch.object(backend, "upload_file", return_value="created") as upload,
                patch.object(backend, "emit"),
            ):
                backend.run_backup()
                backend.run_backup()
                self.assertEqual(upload.call_count, 1)
                config.write_text(f"SOURCE_DIRS={source}\nDRIVE_FOLDER_NAME=second\n")
                backend.run_backup()
                self.assertEqual(upload.call_count, 2)


if __name__ == "__main__":
    unittest.main()
