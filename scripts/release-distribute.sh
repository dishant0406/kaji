#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST="$PROJECT_ROOT/Droid/Info.plist"
BUILD_DIR="$PROJECT_ROOT/build"

VERSION=""
MESSAGE=""
ARCH="arm64"
REMOTE="origin"
REPO="dishant0406/droid"
TAP_REPO="dishant0406/homebrew-droid"
TAP_PATH=""
SSH_HOST="github.com-personal"
TAP_EMAIL="dishu5570@gmail.com"
STAGE_ALL=false
TEST_INSTALL=false

usage() {
    cat <<EOF
Usage: $0 --message "Release message" [options]

Options:
  --version X.Y.Z       Explicit release version. Defaults to patch bump.
  --message TEXT        Commit/release message.
  --arch ARCH           arm64 or x86_64. Defaults to arm64.
  --all                 Stage all current Droid repo changes before commit.
  --remote NAME         Droid git remote. Defaults to origin.
  --repo OWNER/REPO     GitHub release repo. Defaults to dishant0406/droid.
  --tap-repo OWNER/REPO Homebrew tap repo. Defaults to dishant0406/homebrew-droid.
  --tap-path PATH       Existing local tap checkout. Defaults to a temp clone.
  --ssh-host HOST       SSH host alias for tap remote. Defaults to github.com-personal.
  --tap-email EMAIL     Email enforced in tap history. Defaults to dishu5570@gmail.com.
  --test-install        Install droidkit into a temp appdir and uninstall after.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:-}"; shift 2 ;;
        --message) MESSAGE="${2:-}"; shift 2 ;;
        --arch) ARCH="${2:-}"; shift 2 ;;
        --all) STAGE_ALL=true; shift ;;
        --remote) REMOTE="${2:-}"; shift 2 ;;
        --repo) REPO="${2:-}"; shift 2 ;;
        --tap-repo) TAP_REPO="${2:-}"; shift 2 ;;
        --tap-path) TAP_PATH="${2:-}"; shift 2 ;;
        --ssh-host) SSH_HOST="${2:-}"; shift 2 ;;
        --tap-email) TAP_EMAIL="${2:-}"; shift 2 ;;
        --test-install) TEST_INSTALL=true; shift ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[[ -n "$MESSAGE" ]] || { echo "Error: --message is required" >&2; exit 1; }
[[ "$ARCH" == "arm64" || "$ARCH" == "x86_64" ]] || { echo "Error: --arch must be arm64 or x86_64" >&2; exit 1; }

cd "$PROJECT_ROOT"
[[ -z "$(git diff --name-only --diff-filter=U)" ]] || { echo "Error: resolve merge conflicts first" >&2; exit 1; }
BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || { echo "Error: detached HEAD is not supported" >&2; exit 1; }

bump_patch_version() {
    local version="$1"
    IFS='.' read -r major minor patch <<<"$version"
    echo "${major}.${minor}.$((patch + 1))"
}

if [[ -z "$VERSION" ]]; then
    current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
    VERSION="$(bump_patch_version "$current_version")"
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Error: invalid version $VERSION" >&2; exit 1; }

if [[ "$STAGE_ALL" == true ]]; then
    git add -A
fi

BUILD_NUMBER="$(( $(git rev-list --count HEAD) + 1 ))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
git add "$INFO_PLIST"

git diff --cached --quiet && { echo "Error: no staged changes to release" >&2; exit 1; }
git commit -m "$MESSAGE"
git push "$REMOTE" "$BRANCH"

if ! "$SCRIPT_DIR/build-release.sh" --arch "$ARCH" --version "$VERSION"; then
    [[ -d "$BUILD_DIR/Droid.app" ]] || { echo "Error: release app bundle was not created" >&2; exit 1; }
    echo "Continuing with hdiutil DMG packaging because create-dmg is unavailable."
fi

DMG_PATH="$BUILD_DIR/Droid-${VERSION}-${ARCH}.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
    rm -f "$DMG_PATH"
    hdiutil create -volname "Droid" -srcfolder "$BUILD_DIR/Droid.app" -ov -format UDZO "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH" >/dev/null
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
TAG="v$VERSION"
HEAD_SHA="$(git rev-parse HEAD)"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH" --repo "$REPO" --clobber
else
    gh release create "$TAG" "$DMG_PATH" --repo "$REPO" --target "$HEAD_SHA" --title "Droid $VERSION" --notes "$MESSAGE"
fi

prepare_tap() {
    if [[ -n "$TAP_PATH" ]]; then
        echo "$TAP_PATH"
        return
    fi
    local temp_dir
    temp_dir="$(mktemp -d)"
    local repo_name="${TAP_REPO#*/}"
    git clone "git@$SSH_HOST:$TAP_REPO.git" "$temp_dir/$repo_name" >/dev/null
    echo "$temp_dir/$repo_name"
}

TAP_DIR="$(prepare_tap)"
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/droidkit.rb" <<EOF
cask "droidkit" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/Droid-#{version}-$ARCH.dmg"
  name "Droid"
  desc "macOS terminal multiplexer for AI coding agents"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :sonoma"

  app "Droid.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Droid.app"],
                   sudo: false
  end

  caveats <<~EOS
    Droid is currently distributed as an unsigned developer preview.

    This cask removes the macOS quarantine attribute after install so Droid can launch.
    Managed or corporate Macs may still block unsigned apps.
  EOS
end
EOF

cat > "$TAP_DIR/README.md" <<EOF
# homebrew-droid
Homebrew tap for Droid

## Install

\`\`\`bash
brew tap dishant0406/droid
brew install --cask droidkit
\`\`\`

## Launch

\`\`\`bash
open /Applications/Droid.app
\`\`\`
EOF

cd "$TAP_DIR"
ruby -c Casks/droidkit.rb >/dev/null
git add README.md Casks/droidkit.rb
if ! git diff --cached --quiet; then
    GIT_AUTHOR_EMAIL="$TAP_EMAIL" GIT_COMMITTER_EMAIL="$TAP_EMAIL" git commit -m "Update DroidKit to $VERSION"
fi
git filter-repo --force --email-callback "return b'$TAP_EMAIL'" >/dev/null
git remote add origin "git@$SSH_HOST:$TAP_REPO.git" 2>/dev/null || git remote set-url origin "git@$SSH_HOST:$TAP_REPO.git"
git push --force origin main

brew update || true
brew info --cask droidkit

if [[ "$TEST_INSTALL" == true ]]; then
    APPDIR="$(mktemp -d)"
    brew uninstall --cask droidkit --force >/dev/null 2>&1 || true
    brew install --cask droidkit --appdir="$APPDIR" --force
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPDIR/Droid.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APPDIR/Droid.app/Contents/Info.plist"
    brew uninstall --cask droidkit --force
    rm -rf "$APPDIR"
fi

echo "Version: $VERSION"
echo "Build: $BUILD_NUMBER"
echo "DMG: $DMG_PATH"
echo "SHA256: $SHA256"
echo "Install: brew tap dishant0406/droid && brew install --cask droidkit"
