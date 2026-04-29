#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST="$PROJECT_ROOT/Droid/Info.plist"

VERSION=""
MESSAGE=""
ARCH="arm64"
STAGE_ALL=false
PUSH_REMOTE="origin"

usage() {
    cat <<EOF
Usage: $0 --message "Commit message" [options]

Options:
  --version X.Y.Z   Use an explicit version. Defaults to a patch bump from Droid/Info.plist.
  --message TEXT    Commit message to use for the release commit.
  --arch ARCH       DMG architecture. Defaults to arm64.
  --all             Stage all tracked and untracked changes before committing.
  --remote NAME     Git remote to push to. Defaults to origin.
  --help            Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --message)
            MESSAGE="${2:-}"
            shift 2
            ;;
        --arch)
            ARCH="${2:-}"
            shift 2
            ;;
        --all)
            STAGE_ALL=true
            shift
            ;;
        --remote)
            PUSH_REMOTE="${2:-}"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$MESSAGE" ]]; then
    echo "Error: --message is required" >&2
    usage
    exit 1
fi

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "Error: --arch must be arm64 or x86_64" >&2
    exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "Error: Info.plist not found at $INFO_PLIST" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
    echo "Error: resolve merge conflicts before releasing" >&2
    exit 1
fi

current_branch="$(git branch --show-current)"
if [[ -z "$current_branch" ]]; then
    echo "Error: detached HEAD is not supported" >&2
    exit 1
fi

current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"

bump_patch_version() {
    local version="$1"
    IFS='.' read -r major minor patch <<<"$version"
    echo "${major}.${minor}.$((patch + 1))"
}

if [[ -z "$VERSION" ]]; then
    VERSION="$(bump_patch_version "$current_version")"
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be in X.Y.Z format" >&2
    exit 1
fi

if [[ "$STAGE_ALL" == true ]]; then
    git add -A
fi

if git diff --cached --quiet; then
    echo "Error: no staged changes to release. Stage changes first or use --all." >&2
    exit 1
fi

next_build_number="$(( $(git rev-list --count HEAD) + 1 ))"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_build_number" "$INFO_PLIST"
git add "$INFO_PLIST"

git commit -m "$MESSAGE"
git push "$PUSH_REMOTE" "$current_branch"

"$SCRIPT_DIR/build-release.sh" --arch "$ARCH" --version "$VERSION"

DMG_PATH="$PROJECT_ROOT/build/Droid-${VERSION}-${ARCH}.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: expected DMG not found at $DMG_PATH" >&2
    exit 1
fi

hdiutil verify "$DMG_PATH" >/dev/null
checksum="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

echo "Version: $VERSION"
echo "Build: $next_build_number"
echo "Branch: $current_branch"
echo "DMG: $DMG_PATH"
echo "SHA256: $checksum"
