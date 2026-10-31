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

A source folder that is missing or cannot be scanned interrupts the run with an error. Reconnect the source or correct its permissions before retrying. A file modified during upload is reported as an error and remains eligible for the next run; close applications writing that file and run the backup again. Changed source files are uploaded even when their timestamps are older than the Drive copy. No remote files are deleted by these checks.

Run the offline regression suite using the bundled Python environment:

```sh
MyBackup.app/Contents/Resources/venv/bin/python -m unittest discover -s tests -v
```

Builds are prepared and verified in `.build` before replacing the application. The previous bundle is retained in the staging directory if a build or signing step fails.
