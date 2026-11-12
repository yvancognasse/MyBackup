import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import backend


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        self.root.mkdir()
        self.path = self.root / 'removed.txt'
        self.entry = {'drive_id': 'file-id', 'drive_parent_id': 'parent-id', 'sha256': 'digest'}
        self.cache = {str(self.path): dict(self.entry)}
        self.cfg = {'SOURCE_DIRS': [self.root], 'SKIP_HIDDEN': True, 'DELETE_REMOVED': True}
        self.stats = {'errors': 0, 'deleted': 0}
        self.service = Mock()
        self.remote = {'id': 'file-id', 'name': self.path.name, 'parents': ['parent-id'],
                       'sha256Checksum': 'digest', 'mimeType': 'text/plain', 'trashed': False}
        self.service.files().get().execute.return_value = self.remote
        self.log = patch.object(backend, 'write_log').start()
        patch.object(backend, 'emit').start()
        self.addCleanup(patch.stopall)

    def run_cleanup(self, scanned=()):
        backend.trash_removed_files(self.service, self.cfg, self.cache, self.stats, scanned)

    def test_retention_is_default_and_errors_block_cleanup(self):
        config = Path(self.temp.name) / 'config'
        config.write_text(f'SOURCE_DIRS={self.root}\n')
        with patch.object(backend, 'ENV_FILE', config), patch.dict(backend.os.environ, {}, clear=True):
            self.assertFalse(backend.load_env()['DELETE_REMOVED'])
        self.cfg['DELETE_REMOVED'] = False
        self.run_cleanup()
        self.cfg['DELETE_REMOVED'] = True
        self.stats['errors'] = 1
        self.run_cleanup()
        self.service.files().get.assert_called_once()  # Setup only.
        self.service.files().update.assert_not_called()
        self.assertIn(str(self.path), self.cache)

    def test_missing_tracked_file_is_trashed_by_id(self):
        self.run_cleanup()
        self.service.files().update.assert_called_once_with(fileId='file-id', body={'trashed': True}, fields='id')
        self.service.files().delete.assert_not_called()
        self.assertEqual(self.stats['deleted'], 1)
        self.assertNotIn(str(self.path), self.cache)

    def test_present_excluded_and_symlink_files_are_kept(self):
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                if symlink:
                    self.path.unlink()
                    self.path.symlink_to(self.root / 'missing-target')
                else:
                    self.path.write_text('exists')
                self.run_cleanup()  # Deliberately absent from scan, e.g. excluded.
                self.service.files().update.assert_not_called()
                self.assertIn(str(self.path), self.cache)

    def test_disconnected_source_blocks_deletion(self):
        self.root.rmdir()
        self.run_cleanup()
        self.service.files().update.assert_not_called()
        self.assertEqual(self.stats['errors'], 1)
        self.assertIn(str(self.path), self.cache)

    def test_hidden_untracked_and_outside_paths_are_kept(self):
        self.cache = {str(self.root / '.hidden'): self.entry,
                      str(Path(self.temp.name) / 'outside'): self.entry,
                      str(self.root / '..' / 'outside'): self.entry,
                      str(self.root / 'legacy'): {'sha256': 'digest'}}
        self.run_cleanup()
        self.service.files().update.assert_not_called()
        self.assertEqual(len(self.cache), 4)

    def test_changed_moved_renamed_and_folder_copies_are_kept(self):
        for change in ({'sha256Checksum': 'edited'}, {'parents': ['elsewhere']},
                       {'name': 'renamed.txt'}, {'mimeType': 'application/vnd.google-apps.folder'}):
            with self.subTest(change=change):
                self.service.files().get().execute.return_value = {**self.remote, **change}
                self.run_cleanup()
                self.service.files().update.assert_not_called()
                self.assertIn(str(self.path), self.cache)

    def test_reappearing_file_is_kept(self):
        def read_remote(**kwargs):
            self.path.write_text('returned during network read')
            return self.remote
        self.service.files().get().execute.side_effect = read_remote
        self.run_cleanup()
        self.service.files().update.assert_not_called()

    def test_another_live_source_path_protects_same_drive_id(self):
        live = self.root / 'live.txt'
        live.write_text('data')
        self.cache[str(live)] = dict(self.entry)
        self.run_cleanup([live])
        self.service.files().update.assert_not_called()

    def test_remote_not_found_is_forgotten_without_mutation(self):
        from googleapiclient.errors import HttpError
        import httplib2
        self.service.files().get().execute.side_effect = HttpError(httplib2.Response({'status': '404'}), b'not found')
        self.run_cleanup()
        self.service.files().update.assert_not_called()
        self.assertNotIn(str(self.path), self.cache)
        self.assertEqual(self.stats['errors'], 0)

    def test_enabling_cleanup_backfills_old_verified_entries_without_upload(self):
        self.path.write_bytes(b'data')
        self.cache[str(self.path)] = backend.content_signature(self.path)
        remote = {'id': 'file-id', 'sha256Checksum': self.cache[str(self.path)]['sha256']}
        self.stats['skipped'] = 0
        with patch.object(backend, 'upload_file') as upload:
            result = backend.process_one_file(self.path, 'parent-id', object(), self.cfg,
                                              self.cache, self.stats, {self.path.name: remote})
        self.assertEqual(result, 'skipped')
        upload.assert_not_called()
        self.assertEqual(self.cache[str(self.path)]['drive_id'], 'file-id')
        self.cache[str(self.path)]['device'] = -1
        self.assertTrue(backend.unchanged(self.path, self.cache))
        self.assertEqual(self.cache[str(self.path)]['drive_id'], 'file-id')

    def test_failed_trash_keeps_cache_for_retry(self):
        self.service.files().update().execute.side_effect = ConnectionResetError('network')
        self.run_cleanup()
        self.assertEqual(self.stats['errors'], 1)
        self.assertEqual(self.stats['deleted'], 0)
        self.assertIn(str(self.path), self.cache)

    def test_already_trashed_copy_is_forgotten_without_mutation(self):
        self.remote['trashed'] = True
        self.run_cleanup()
        self.service.files().update.assert_not_called()
        self.assertNotIn(str(self.path), self.cache)

    def test_end_to_end_keep_then_trash_after_option_change(self):
        runtime = Path(self.temp.name) / 'runtime'
        runtime.mkdir()
        config = runtime / 'config'
        config.write_text(f'SOURCE_DIRS={self.root}\n')
        self.path.write_bytes(b'data')
        with (
            patch.multiple(backend, HOME=runtime, ENV_FILE=config, CACHE_FILE=runtime / 'cache', LOG_FILE=runtime / 'log'),
            patch.object(backend, 'authenticate', return_value=object()),
            patch.object(backend, 'build_service', return_value=self.service),
            patch.object(backend, 'get_service', return_value=self.service),
            patch.object(backend, 'get_or_create_folder', return_value=('parent-id', False)),
            patch.object(backend, 'list_folder', return_value={}),
            patch.object(backend, 'upload_file', return_value=('created', 'file-id')) as upload,
        ):
            backend.run_backup()
            saved = backend.load_cache()[str(self.path)]
            self.assertEqual(saved['drive_id'], 'file-id')
            self.remote['sha256Checksum'] = saved['sha256']
            self.path.unlink()
            backend.run_backup()
            self.service.files().update.assert_not_called()
            self.assertIn(str(self.path), backend.load_cache())
            config.write_text(f'SOURCE_DIRS={self.root}\nDELETE_REMOVED=true\n')
            backend.run_backup()
            self.service.files().update.assert_called_once()
            self.assertNotIn(str(self.path), backend.load_cache())
            upload.assert_called_once()


if __name__ == '__main__':
    unittest.main()
