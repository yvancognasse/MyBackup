# MyBackup

Native macOS backup application with a Swift interface and Python backend. Build using `create_app.sh`. Google OAuth credentials, authentication tokens, local configuration, caches and logs stay on the Mac and are not part of the source repository.

## Source repository

Public repository: [MyBackup](https://github.com/yvancognasse/MyBackup). This local folder remains the development/build checkout. Git history starts with the current imported source snapshot; earlier local builds are not reconstructed as historical commits.

After authorized changes, run the project checks and update documentation as required in `AGENTS.md`, then commit and push to `origin/main`. Changes reach GitHub when a push succeeds, not automatically on every file save. Generated applications, caches, logs and local secrets are excluded by `.gitignore`.

```sh
git pull --ff-only
# Make and verify the change
git add .
git commit -m "Describe the change"
git push origin main
```

Use `MyBackup.env.example` as a template for local `MyBackup.env`. Provide your own Google OAuth `credentials.json` locally. The generated authentication tokens must never be committed.

## Backup reliability

The cache is tied to the actual Google Drive destination and selected source roots. Changing either, or upgrading from the older cache format, rechecks and sends the source files again. Existing Drive files are updated by name; the old backup destination is preserved. Unchanged files use the local cache, so external Drive deletions are not continuously audited.

A source folder that is missing or cannot be scanned interrupts the run with an error. Reconnect the source or correct its permissions before retrying. A file modified during upload is reported as an error and remains eligible for the next run; close applications writing that file and run the backup again. Changed source files are uploaded even when their timestamps are older than the Drive copy.

## Settings

Settings initially show source folders, the Drive destination, hidden-file handling and retention. A small disclosure icon to the right of **Transfert et performance** expands or collapses the advanced transfer settings. Collapsing the section preserves its values; Save includes hidden settings. The section starts collapsed whenever Settings is reopened.

## Deleted source files

In Settings, **Conserver dans Drive les fichiers supprimés de la source** is checked by default. Uncheck it and save to move tracked Drive copies of deleted source files to the Drive trash after a successful backup. Dormant preferences imported by older versions do not enable cleanup; an explicit choice saved in the new UI is required. This never permanently deletes files or removes folders. For backend-only use, set `DELETE_REMOVED=true` (default: `false`).

Cleanup requires a complete source scan and zero backup errors. It uses the saved Drive file ID, parent folder and SHA-256 checksum. Copies renamed, moved or edited in Drive are preserved. Existing local files, symlinks, hidden files excluded by settings, paths outside the selected roots and Drive copies shared with another live source path are preserved. Missing source roots or cleanup failures stop deletion; failed items stay in the cache for retry.

Older cache entries without a Drive file ID cannot authorize deletion. When cleanup is enabled, still-present files are verified against Drive once to record their IDs. Copies of files already deleted before this tracking was established are retained and noted in the log. Changing the destination or selected roots invalidates the cache, so cleanup never uses another destination's history.

File cache entries now include a SHA-256 content digest. Matching metadata takes the fast path; a changed volume identifier, timestamp, or inode triggers a local content check. Identical content refreshes the metadata without uploading again. Content edits of the same size with a preserved modification time are detected through the change timestamp and digest. Files that change while being read are retried once, then reported as errors if still unstable.

The first run after this update verifies old cache entries against Drive's SHA-256 checksums before upgrading them. This requires reading local content (and may download online-only OneDrive files) and preparing Drive folders once. Matching files are skipped; a missing or different remote checksum causes a conservative upload. Subsequent runs reuse the verified cache. Destination and source-root checks remain in force.

Drive folder searches and paginated file reads retry transient failures up to three times. File listings run in parallel using separate HTTP clients. The interface shows local verification and Drive listing progress; the log records cache size, local verification totals, and fatal failures.

Run the offline regression suite using the bundled Python environment:

```sh
MyBackup.app/Contents/Resources/venv/bin/python -m unittest discover -s tests -v
```

Builds are prepared and verified in `.build` before replacing the application. The previous bundle is retained in the staging directory if a build or signing step fails.
