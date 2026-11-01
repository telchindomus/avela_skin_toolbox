#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# release.sh — GitFlow release of the Avela skin toolbox
#
# Usage:
#   cicd/release.sh <version>          e.g. cicd/release.sh 1.1.0
#   cicd/release.sh major|minor|patch  bumps the corresponding component
#
# Flow:
#   devel (X.Y.Z-dev) → release/X.Y.Z → main (tag vX.Y.Z) → devel (X.Y.(Z+1)-dev)
#
# The version is TOOLBOX_VERSION in CMakeLists.txt. The release commit is checked by cicd/test_unit.sh (a fresh clone
# of the release branch renders every official skin) before it is tagged. Pushes main, devel and the tag to origin at
# the end. Nothing is built: the release is the tag (render.sh runs from a checkout).
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMAKELISTS="$REPO_ROOT/CMakeLists.txt"
die() { echo "ERROR: $*" >&2; exit 1; }

# devel's version without "-dev": the release it leads to
current_version() { sed -n 's/^set(TOOLBOX_VERSION "\([0-9.]*\)\(-dev\)\{0,1\}")$/\1/p' "$CMAKELISTS"; }
set_version() { sed -i "s/^set(TOOLBOX_VERSION \".*\")$/set(TOOLBOX_VERSION \"$1\")/" "$CMAKELISTS"; }

bump() {
    local major minor patch
    IFS='.' read -r major minor patch <<< "$(current_version)"
    case "$1" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "$major.$((minor + 1)).0" ;;
        patch) echo "$major.$minor.$patch" ;;  # devel's X.Y.Z-dev already targets X.Y.Z
    esac
}

next_dev() {
    local major minor patch
    IFS='.' read -r major minor patch <<< "$1"
    echo "$major.$minor.$((patch + 1))"
}

[[ $# -eq 1 ]] || die "Usage: $0 <version|major|minor|patch>"
case "$1" in
    major|minor|patch) TARGET_VERSION="$(bump "$1")" ;;
    [0-9]*.[0-9]*.[0-9]*) TARGET_VERSION="$1" ;;
    *) die "Argument must be a version (X.Y.Z) or one of: major minor patch" ;;
esac
[[ "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be X.Y.Z"
DEVEL_VERSION="$(current_version)"
DEV_VERSION="$(next_dev "$TARGET_VERSION")"
RELEASE_BRANCH="release/$TARGET_VERSION"
TAG="v$TARGET_VERSION"

cd "$REPO_ROOT"
[[ -n "$DEVEL_VERSION" ]] || die "Could not read TOOLBOX_VERSION from CMakeLists.txt"
[[ -z "$(git status --porcelain)" ]] || die "Working tree is dirty. Commit or stash changes before releasing."
[[ "$(git rev-parse --abbrev-ref HEAD)" == "devel" ]] || die "Must be on 'devel' to start a release."
git config user.email > /dev/null || die "No git identity (git config user.name / user.email): commits would fail."
git fetch --quiet origin
[[ "$(git rev-parse devel)" == "$(git rev-parse origin/devel)" ]] ||
    die "Local 'devel' is not origin/devel. Pull or push first."
git tag | grep -qx "$TAG" && die "Tag $TAG already exists."
printf '%s\n' "$DEVEL_VERSION" "$TARGET_VERSION" | sort -V -C ||
    die "$TARGET_VERSION is older than devel's $DEVEL_VERSION."

echo "Releasing $TARGET_VERSION  (devel will become $DEV_VERSION-dev)"
git switch -c "$RELEASE_BRANCH"
set_version "$TARGET_VERSION"
git add "$CMAKELISTS"
git commit -m "chore: set version $TARGET_VERSION"
# the test on a fresh clone of the release commit, never on this working copy
if ! "$REPO_ROOT/cicd/test_unit.sh" --source "$REPO_ROOT" --tag "$RELEASE_BRANCH"; then
    git switch --quiet devel
    git branch -D "$RELEASE_BRANCH"
    die "The test failed on $TARGET_VERSION; nothing was released."
fi
git tag -a "$TAG" -m "$TAG"

git switch main
git pull --quiet origin main
git merge --no-ff "$RELEASE_BRANCH" -m "release: $TARGET_VERSION"

git switch devel
git merge --no-ff "$RELEASE_BRANCH" -m "release: merge $TARGET_VERSION back to devel"
set_version "$DEV_VERSION-dev"
git add "$CMAKELISTS"
git commit -m "chore: bump devel to $DEV_VERSION-dev"
git branch -d "$RELEASE_BRANCH"

git push origin main devel "$TAG"
echo "Done. Released $TAG. devel is now $DEV_VERSION-dev."
