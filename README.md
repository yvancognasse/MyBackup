# MyBackup

Native macOS backup application with a Swift interface and Python backend. Build using `create_app.sh`. Google OAuth credentials, authentication tokens, local configuration, caches and logs stay on the Mac and are not part of the source repository.

## Source repository

Private repository: [MyBackup](https://github.com/yvancognasse/MyBackup). This local folder remains the development/build checkout. Git history starts with the current imported source snapshot; earlier local builds are not reconstructed as historical commits.

After authorized changes, run the project checks and update documentation as required in `AGENTS.md`, then commit and push to `origin/main`. Changes reach GitHub when a push succeeds, not automatically on every file save. Generated applications, caches, logs and local secrets are excluded by `.gitignore`.

```sh
git pull --ff-only
# Make and verify the change
git add .
git commit -m "Describe the change"
git push origin main
```

Use `MyBackup.env.example` as a template for local `MyBackup.env`. Provide your own Google OAuth `credentials.json` locally. The generated authentication tokens must never be committed.
