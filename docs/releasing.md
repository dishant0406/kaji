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

The workflow writes `Casks/droid.rb` into the tap repo and creates the repo automatically if it does not already exist.

Default install path:

```bash
brew tap <repo-owner>/homebrew-droid
brew install --cask droid
```

## Running A Release

1. Push the release-ready branch.
2. Open `Actions -> Release`.
3. Run it with a semantic version like `0.1.0`.
4. Review the generated draft release.
5. Publish when the DMGs and appcasts look correct.
