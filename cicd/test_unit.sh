#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test_unit.sh — renders every official Avela skin with the toolbox: the toolbox's own test, which fails when the
# toolbox falls behind the firmware's skin API (a scene doesn't build or doesn't render)
#
# Usage:
#   cicd/test_unit.sh                              test a fresh clone of origin's devel
#   cicd/test_unit.sh --tag v1.0.0                 test a fresh clone of that tag (or branch)
#   cicd/test_unit.sh --source <path> --tag <ref>  clone from another repository (release.sh: this one's release branch)
#   cicd/test_unit.sh --firmware-tag v1.0.0        against that firmware tag (default: FIRMWARE_TAG, else main)
#
# Always fresh clones (the toolbox and the firmware) in $CLONES_DIR/test-<time>, never the working copy; removed
# after a pass, kept after a failure, for a look. Needs what render.sh needs (cmake, a C++23 compiler, python3 with
# venv); the first render of a clone builds LovyanGFX, so a run takes a few minutes.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$REPO_ROOT/cicd/.env" ]] && { set -a; source "$REPO_ROOT/cicd/.env"; set +a; }
: "${BUILD_DIR:=$REPO_ROOT/build}"
: "${CLONES_DIR:=$BUILD_DIR/clones}"
: "${REPO_URL:=$(git -C "$REPO_ROOT" remote get-url origin 2> /dev/null || true)}"
: "${FIRMWARE_URL:=https://github.com/telchindomus/avela_firmware.git}"
: "${FIRMWARE_TAG:=main}"

SOURCE="$REPO_URL"
REF="devel"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) [[ $# -ge 2 ]] || die "--tag requires a value"; REF="$2"; shift 2 ;;
        --source) [[ $# -ge 2 ]] || die "--source requires a value"; SOURCE="$2"; shift 2 ;;
        --firmware-tag) [[ $# -ge 2 ]] || die "--firmware-tag requires a value"; FIRMWARE_TAG="$2"; shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[[ -n "$SOURCE" ]] || die "No REPO_URL (cicd/.env) and no origin remote"

mkdir -p "$CLONES_DIR"
CLONE_DIR="$CLONES_DIR/test-$(date +%Y%m%d-%H%M%S)"
PASSED=false
trap 'if $PASSED; then rm -rf "$CLONE_DIR"; else echo "The failed clone is kept: $CLONE_DIR" >&2; fi' EXIT
echo "Cloning $SOURCE ($REF) and $FIRMWARE_URL ($FIRMWARE_TAG) → $CLONE_DIR"
git clone --branch "$REF" --depth 1 --quiet "$SOURCE" "$CLONE_DIR/toolbox"
git clone --branch "$FIRMWARE_TAG" --depth 1 --quiet "$FIRMWARE_URL" "$CLONE_DIR/avela_firmware"

skins=("$CLONE_DIR"/avela_firmware/components/avela_skin_*/)
[[ -d "${skins[0]}" ]] || die "No official skin (components/avela_skin_*) in the firmware at $FIRMWARE_TAG"
for skin in "${skins[@]}"; do
    name="$(basename "$skin")"
    echo "Rendering $name"
    AVELA_FIRMWARE="$CLONE_DIR/avela_firmware" "$CLONE_DIR/toolbox/render.sh" --skin "$skin" \
        --out "$CLONE_DIR/renders/$name"
    count=$(find "$CLONE_DIR/renders/$name" -name '*.png' | wc -l)
    [[ "$count" -gt 0 ]] || die "$name: no scene rendered"
    echo "$name: $count scenes"
done
PASSED=true
echo "Every official skin of the firmware at $FIRMWARE_TAG renders with the toolbox at $REF"
