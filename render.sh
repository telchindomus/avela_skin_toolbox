#!/usr/bin/env bash
# Renders a skin's screens to PNG files, from the skin's sources alone.
#
#   ./render.sh [--skin <skin folder>] [--out <folder>]
#               [--components <components folder>] [--screen landscape_320x170] [--scale 3]
#               [--lovyangfx <LovyanGFX checkout>]
#
#   --skin        a skin component (avela_skin_<name>/: CMakeLists.txt, Kconfig, include/, src/, assets/), anywhere
#                 (default: $AVELA_SKIN)
#   --out         where the PNGs go, one per scene (default: $AVELA_OUT/<skin folder name>, AVELA_OUT defaulting
#                 to renders/ here)
#   --components  the folder holding the components the skin requires; only their headers and Kconfig are used
#                 (default: $AVELA_FIRMWARE/components)
#   --screen      the screen to render for (default: the board's, from avela_boards in the components)
#   --scale       each pixel as an n x n square (default 1: the screen's real pixels, nothing scaled)
#   --lovyangfx   a LovyanGFX checkout (default: $AVELA_FIRMWARE/managed_components/lovyan03__lovyangfx if there,
#                 else the firmware's pinned release is fetched)
#
# AVELA_FIRMWARE (a firmware checkout), AVELA_SKIN (the skin to render) and AVELA_OUT (where renders go): from the
# environment, or else from .env next to this script (KEY=value lines; a relative path is relative to this script's
# folder); without either, the defaults in .env.example: the firmware checkout next to this one, its official skin.
#
# Needs: cmake >= 3.24, a C++23 compiler (GCC >= 13 or clang >= 17), python3 with venv. The first run makes
# .venv/ (kconfiglib) and builds LovyanGFX; later runs rebuild only what changed. Builds live in build/<skin>-<hash>/.
set -euo pipefail

usage() {
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

skin="" components="" out="" screen="" scale=1 lovyangfx=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skin) skin=$2 ;;
        --components) components=$2 ;;
        --out) out=$2 ;;
        --screen) screen=$2 ;;
        --scale) scale=$2 ;;
        --lovyangfx) lovyangfx=$2 ;;
        *) usage ;;
    esac
    shift 2 || usage
done
toolbox=$(cd "$(dirname "$0")" && pwd)

# AVELA_FIRMWARE, AVELA_SKIN and AVELA_OUT from .env, each unless the environment has it (plain KEY=value lines,
# nothing is executed)
if [[ -f "$toolbox/.env" ]]; then
    while IFS='=' read -r key value; do
        case "$key" in
            AVELA_FIRMWARE) [[ -n "${AVELA_FIRMWARE:-}" ]] || AVELA_FIRMWARE=$value ;;
            AVELA_SKIN) [[ -n "${AVELA_SKIN:-}" ]] || AVELA_SKIN=$value ;;
            AVELA_OUT) [[ -n "${AVELA_OUT:-}" ]] || AVELA_OUT=$value ;;
        esac
    done < <(grep -E '^[A-Z_]+=' "$toolbox/.env")
fi
# without either: the firmware checkout next to this one and its official skin (as .env.example)
AVELA_FIRMWARE=${AVELA_FIRMWARE:-../avela_firmware}
AVELA_SKIN=${AVELA_SKIN:-$AVELA_FIRMWARE/components/avela_skin_piccolo}
if [[ -z "$skin" && -n "${AVELA_SKIN:-}" ]]; then
    skin=$AVELA_SKIN
    [[ "$skin" = /* ]] || skin="$toolbox/$skin"
fi
[[ -n "$skin" ]] || { echo "render.sh: give --skin or set AVELA_SKIN (.env)" >&2; exit 2; }
if [[ -z "$out" ]]; then
    out_parent=${AVELA_OUT:-renders}
    [[ "$out_parent" = /* ]] || out_parent="$toolbox/$out_parent"
    out="$out_parent/$(basename "$(realpath "$skin")")"
fi
if [[ -n "${AVELA_FIRMWARE:-}" ]]; then
    [[ "$AVELA_FIRMWARE" = /* ]] || AVELA_FIRMWARE="$toolbox/$AVELA_FIRMWARE"
    [[ -n "$components" ]] || components="$AVELA_FIRMWARE/components"
    if [[ -z "$lovyangfx" && -d "$AVELA_FIRMWARE/managed_components/lovyan03__lovyangfx" ]]; then
        lovyangfx="$AVELA_FIRMWARE/managed_components/lovyan03__lovyangfx"
    fi
fi
[[ -n "$components" ]] || { echo "render.sh: give --components or set AVELA_FIRMWARE (.env)" >&2; exit 2; }

skin=$(realpath "$skin")
components=$(realpath "$components")
out=$(realpath -m "$out")
[[ -z "$lovyangfx" ]] || lovyangfx=$(realpath "$lovyangfx")

# .venv with kconfiglib; made again whenever it can't import it (e.g. made on another machine, or half made)
venv="$toolbox/.venv"
if ! "$venv/bin/python" -c "import kconfiglib" 2> /dev/null; then
    rm -rf "$venv"
    python3 -m venv "$venv"
    "$venv/bin/python" -m pip install --quiet -r "$toolbox/requirements.txt"
    "$venv/bin/python" -c "import kconfiglib"
fi

build="$toolbox/build/$(basename "$skin")-$(printf '%s' "$skin" | sha1sum | cut -c1-8)"
screen_argument=()
[[ -n "$screen" ]] && screen_argument=(--screen "$screen")
"$venv/bin/python" "$toolbox/tools/configure_skin.py" --skin "$skin" --components "$components" \
    --out-dir "$build/config" "${screen_argument[@]}"

cmake -S "$toolbox" -B "$build" -DCMAKE_BUILD_TYPE=Release \
    -DSKIN_DIR="$skin" -DCOMPONENTS_DIR="$components" -DCONFIG_DIR="$build/config" -DLOVYANGFX_DIR="$lovyangfx"
cmake --build "$build" --parallel
"$build/avela_skin_render" --out "$out" --scale "$scale"
