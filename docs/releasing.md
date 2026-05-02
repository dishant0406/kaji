# Releasing

`Release` in GitHub Actions builds signed macOS DMGs for `arm64` and `x86_64`, notarizes them, creates a draft GitHub release, generates Sparkle appcasts, and updates the Homebrew cask tap.

## Required Secrets

- `GH_PAT`: token used by `scripts/setup.sh` when fetching Ghostty artifacts in CI
- `DEVELOPER_ID_APPLICATION_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `DEVELOPER_ID_APPLICATION_PASSWORD`: password for that `.p12`
- `KEYCHAIN_PASSWORD`: temporary CI keychain password
- `APPLE_ID`: Apple account email for notarization
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization
- `APPLE_TEAM_ID`: Apple Developer team id
- `SPARKLE_PRIVATE_KEY`: EdDSA private key used to sign Sparkle appcasts
- `HOMEBREW_TAP_TOKEN`: token with write access to the Homebrew tap repo

## Optional Repo Variable

- `HOMEBREW_TAP_REPOSITORY`: override the tap target

If unset, the workflow defaults to `<repo-owner>/homebrew-droid`.

## Homebrew Tap

The public preview cask is `droidkit` in `dishant0406/homebrew-droid`.

Install path:

```bash
brew tap dishant0406/droid
brew install --cask droidkit
```

## Running A Release

1. Push the release-ready branch.
2. Open `Actions -> Release`.
3. Run it with a semantic version like `0.1.0`.
4. Review the generated draft release.
5. Publish when the DMGs and appcasts look correct.

## Local DMG Flow

For the repeated local workflow of bumping the app version, committing, pushing, and building an arm64 DMG, use:

```bash
scripts/release-local.sh --message "Release message" --all
```

Useful options:

- `--version X.Y.Z` to override the default patch bump
- `--arch x86_64` to build the Intel DMG instead of the default arm64 artifact
- omit `--all` if you want the script to use only already-staged changes

## Local Distribution Flow

To bump, commit, push, build the DMG, create or update the GitHub release, update the `droidkit` Homebrew cask, rewrite tap emails, and verify the cask:

```bash
scripts/release-distribute.sh --version 0.0.3 --message "Release 0.0.3" --all --test-install
```

The script uses `git@github.com-personal:<tap-repo>.git` for the tap remote by default and enforces `dishu5570@gmail.com` across tap history with `git filter-repo`.
