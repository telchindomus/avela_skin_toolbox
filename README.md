# avela_skin_toolbox

Renders an Avela skin to PNG images on a PC, from the skin's sources alone: copy a skin anywhere, change it, render
it, look at every screen without a board.

It builds and runs on a Linux PC; the screenshots in the Avela firmware's user guide are made with it.

## Use

```
./render.sh [--skin <skin folder>] [--out <folder>]
            [--components <folder with the components the skin requires>] [--screen landscape_320x170] [--scale 3]
            [--lovyangfx <LovyanGFX checkout>]
```

Needs cmake >= 3.24, a C++23 compiler (GCC >= 13 or clang >= 17), python3 with venv, and the Linux headers
(`linux/fb.h`, for LovyanGFX's PC platform; Debian/Ubuntu: `build-essential cmake python3-venv`). The first run
makes `.venv/` (kconfiglib) and builds LovyanGFX; then only what changed is rebuilt. Builds live in
`build/<skin>-<hash>/`.

Defaults from the environment or from `.env` next to `render.sh` (`cp .env.example .env`): `AVELA_FIRMWARE`, the
firmware checkout the components and LovyanGFX come from (default `../avela_firmware`), `AVELA_SKIN`, the skin
rendered without `--skin` (default the firmware's `avela_skin_piccolo`), and `AVELA_OUT`, where renders go without
`--out` (`<AVELA_OUT>/<skin folder name>`, default `renders/` here). `--skin` / `--out` / `--components` /
`--lovyangfx` override them. `--scale` defaults to 1: the screen's real pixels, nothing scaled.

Example: play with a copy of the official skin.

```
cp -r ../avela_firmware/components/avela_skin_piccolo ~/play/my_piccolo
./render.sh --skin ~/play/my_piccolo --out ~/play/shots   # components + LovyanGFX from .env (AVELA_FIRMWARE)
```

Layout: `render.sh` (the command), `tools/configure_skin.py` (Kconfig -> sdkconfig.h / sdkconfig.cmake / skin.cmake),
`CMakeLists.txt` + `cmake/` (the stand-in idf_component_register, embedded assets, the skin API version check,
LovyanGFX for the PC), `src/` (the in-memory display, the scenes, `avela_skin_render`).

- `--skin`: a bare skin component (`avela_skin_<name>/`: CMakeLists.txt, Kconfig, include/, src/, assets/).
- `--components`: a folder holding the components the skin's `REQUIRES` names (e.g. the firmware's `components/`,
  or copies). Only their `include/` folders and `Kconfig` files are used; nothing of them is compiled. Later
  optional: the toolbox fetches them at the tag of the skin's API version.
- Output: one PNG per scene (player playing / paused, station list, info connected / not configured, Wi-Fi setup
  starting / up, tiles, header before / after the clock is set).

## How it works

1. The toolbox's CMake project runs the skin's own `CMakeLists.txt` with a stand-in `idf_component_register` that
   records its arguments (`SRCS`, `INCLUDE_DIRS`, `EMBED_FILES`, `REQUIRES`, `PRIV_REQUIRES`). ESP-IDF itself
   collects requirements this way in its early pass (`tools/cmake/scripts/component_get_requirements.cmake`), so
   the skin's `CMakeLists.txt` stays the single description of the skin.
2. It sets the `CONFIG_*` values a skin build reads (this skin chosen, the screen, every optional component on) and evaluates
   the skin's and the required components' `Kconfig` with ESP-IDF's Kconfig library (`esp-idf-kconfig`) to read
   the skin's `AVELA_SKIN_API_VERSION`, which must be one its scenes cover.
3. Include folders: `<components>/<name>/include` for every required component; LovyanGFX comes as a PC build.
4. Embedded assets become the same `_binary_<name>_start/_end` symbols the ESP-IDF linker makes.
5. The skin's sources compile with a host `sdkconfig.h`, an in-memory LovyanGFX display and avela_ui's band
   renderer; each scene builds a page skin on the surface, calls its setters with sample values, `draw()`, and writes a
   PNG.

The skin API headers (skin concepts, value types, avela_ui, avela_strings) are platform-free by the firmware's rule,
which is what makes this possible.

Scenes (src/scenes.cpp): player_playing, player_paused, player_clock_not_set, stations, info_connected,
info_not_configured, wifi_setup_starting, wifi_setup_up, tiles, and with the weather component weather_day,
weather_night (between them all eight conditions and the moon), weather_not_configured, weather_place_not_found. They cover the skin API versions in
`supported_skin_api_versions` (CMakeLists.txt, `>=0.1.0`); a new page skin in the firmware needs a new scene here.

A skin's CMakeLists.txt may use plain CMake and `idf_component_register` only (no other ESP-IDF functions), which is
what the official skin does.

## Releases and checks

Branches: `main` = released, `devel` = integration, work on `feature/<name>` off `devel`. The version is
`TOOLBOX_VERSION` in CMakeLists.txt. `cicd/` (settings in `cicd/.env` from `cicd/.env.example`) works in fresh clones
under `build/clones/`, never in the working copy:

- `cicd/test_unit.sh [--tag <ref>] [--source <path-or-URL>] [--firmware-tag <tag>]`: clones the toolbox (origin's
  `devel` by default) and the firmware (its `main` by default) and renders every official skin; it fails when a scene
  doesn't build or render, which is how the toolbox falling behind the firmware's skin API shows.
- `cicd/release.sh X.Y.Z | major | minor | patch`: `devel` → `release/X.Y.Z` → `main` + tag `vX.Y.Z` → back into
  `devel` as `X.Y.(Z+1)-dev`; runs the test on the release commit before tagging; pushes `main`, `devel` and the tag.
  A release is its tag: nothing is built.

## Ideas

- `--window`, an SDL simulator with keys for the knob and the back button.

## Licence

MIT, see `LICENSE`.
