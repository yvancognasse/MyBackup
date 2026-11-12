import tempfile
import os
import hashlib
import unittest
from pathlib import Path
from unittest.mock import patch, Mock

import backend


class BackendTests(unittest.TestCase):
    def test_metadata_only_changes_reuse_verified_content(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "data"
            path.write_bytes(b"original")
            cache = {str(path): backend.content_signature(path)}
            cache[str(path)]["device"] = -1
            cache[str(path)]["ctime_ns"] = -1
            with patch.object(backend, "content_signature", wraps=backend.content_signature) as hashed:
                self.assertTrue(backend.unchanged(path, cache))
                self.assertTrue(backend.unchanged(path, cache))
                self.assertEqual(hashed.call_count, 1)

    def test_same_size_edit_with_preserved_mtime_is_detected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "data"
            path.write_bytes(b"original")
            cache = {str(path): backend.content_signature(path)}
            stamp = path.stat()
            path.write_bytes(b"modified")
            os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            self.assertFalse(backend.unchanged(path, cache))

    def test_legacy_cache_requires_remote_content_verification(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "data"
            path.write_bytes(b"original")
            cache = {str(path): backend.signature(path)}
            self.assertFalse(backend.unchanged(path, cache))
            stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
            remote = {path.name: {"id": "remote", "sha256Checksum": hashlib.sha256(b"original").hexdigest()}}
            with patch.object(backend, "upload_file") as upload:
                result = backend.process_one_file(path, "folder", object(), {}, cache, stats, remote)
            self.assertEqual(result, "skipped")
            upload.assert_not_called()
            self.assertTrue(backend.unchanged(path, cache))

    def test_hash_failure_is_not_cached_or_uploaded(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "data"
            path.write_bytes(b"data")
            cache = {str(path): backend.signature(path)}
            stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
            with patch.object(backend, "content_signature", side_effect=OSError("unreadable")), patch.object(backend, "write_log"), patch.object(backend, "upload_file") as upload:
                self.assertEqual(backend.process_one_file(path, "folder", object(), {}, cache, stats, {}), "error")
            upload.assert_not_called()
            self.assertNotIn(str(path), cache)
            self.assertEqual(stats["errors"], 1)

    def test_hash_rejects_file_that_keeps_changing(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "data"
            path.write_bytes(b"data")
            with patch.object(backend, "signature", side_effect=[{"size": n} for n in range(4)]):
                with self.assertRaisesRegex(OSError, "changed during verification"):
                    backend.content_signature(path)

    def test_drive_reads_enable_retries_and_request_checksums(self):
        service = Mock()
        service.files().list().execute.return_value = {"files": []}
        self.assertEqual(backend.list_folder(service, "folder"), {})
        self.assertIn("sha256Checksum", service.files().list.call_args.kwargs["fields"])
        service.files().list.return_value.execute.assert_called_with(num_retries=3)
        service.files().create().execute.return_value = {"id": "new"}
        backend.get_or_create_folder(service, "name")
        service.files().list().execute.assert_called_with(num_retries=3)

    def test_drive_listing_recovers_from_connection_reset(self):
        from googleapiclient.http import HttpRequest
        import httplib2
        http = Mock()
        http.request.side_effect = [ConnectionResetError("reset"),
                                   (httplib2.Response({"status": "200"}), b'{"files": []}')]
        request = HttpRequest(http, lambda response, content: __import__("json").loads(content), "https://example.invalid")
        request._sleep = lambda seconds: None
        service = Mock()
        service.files().list.return_value = request
        self.assertEqual(backend.list_folder(service, "folder"), {})
        self.assertEqual(http.request.call_count, 2)

    def test_remote_mismatch_or_missing_checksum_uploads_conservatively(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "data"
            path.write_bytes(b"data")
            for remote in ({"id": "remote"}, {"id": "remote", "sha256Checksum": "different"}):
                with self.subTest(remote=remote):
                    cache = {str(path): backend.signature(path)}
                    stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
                    with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "upload_file", return_value=("updated", "remote")) as upload:
                        self.assertEqual(backend.process_one_file(path, "folder", object(), {"HTTP_TIMEOUT_SECONDS": 1}, cache, stats, {path.name: remote}), "updated")
                    upload.assert_called_once()
                    self.assertTrue(backend.unchanged(path, cache))

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
                return "created", "remote"

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
                return "created", "remote"
            with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "write_log"), patch.object(backend, "upload_file", side_effect=changing_upload):
                result = backend.process_one_file(path, "folder", object(), cfg, cache, stats, {})
            self.assertEqual(result, "error")
            self.assertNotIn(str(path), cache)
            self.assertEqual(stats["errors"], 1)
            with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "upload_file", return_value=("updated", "remote")) as upload:
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
            with patch.object(backend, "get_service", return_value=object()), patch.object(backend, "upload_file", return_value=("updated", "remote")) as upload:
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
                patch.object(backend, "upload_file", return_value=("created", "remote")) as upload,
                patch.object(backend, "emit"),
            ):
                backend.run_backup()
                backend.run_backup()
                self.assertEqual(upload.call_count, 1)
                config.write_text(f"SOURCE_DIRS={source}\nDRIVE_FOLDER_NAME=second\n")
                backend.run_backup()
                self.assertEqual(upload.call_count, 2)

    def test_migration_then_remount_avoids_remote_preparation_and_uploads(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            runtime = root / "runtime"
            runtime.mkdir()
            source = root / "source"
            source.mkdir()
            path = source / "file.txt"
            path.write_bytes(b"data")
            config = runtime / "config"
            config.write_text(f"SOURCE_DIRS={source}\n")
            with (
                patch.multiple(backend, HOME=runtime, ENV_FILE=config, CACHE_FILE=runtime / "cache.json", LOG_FILE=runtime / "run.log"),
                patch.object(backend, "authenticate", return_value=object()),
                patch.object(backend, "build_service", return_value=object()),
                patch.object(backend, "get_service", return_value=object()),
                patch.object(backend, "get_or_create_folder", return_value=("remote", False)) as folders,
                patch.object(backend, "list_folder", return_value={path.name: {"id": "file", "sha256Checksum": hashlib.sha256(b"data").hexdigest()}}) as listing,
                patch.object(backend, "upload_file") as upload,
                patch.object(backend, "emit"),
            ):
                destination = {"root_id": "remote", "sources": [str(source.resolve())]}
                backend.save_cache({str(path): backend.signature(path)}, destination)
                backend.run_backup()
                self.assertTrue(backend.unchanged(path, backend.load_cache(destination)))
                self.assertEqual(listing.call_count, 1)
                folders.reset_mock()
                real_signature = backend.signature
                def remounted(p):
                    return {**real_signature(p), "device": -1, "ctime_ns": -1}
                with patch.object(backend, "signature", side_effect=remounted):
                    backend.run_backup()
                self.assertEqual(folders.call_count, 1)  # Only the Drive root lookup.
                self.assertEqual(listing.call_count, 1)
                upload.assert_not_called()


if __name__ == "__main__":
    unittest.main()
