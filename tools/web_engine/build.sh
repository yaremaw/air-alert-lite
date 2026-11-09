#!/usr/bin/env bash
# Builds the cut-down web export template (see custom.py) and copies it to
# tools/web_engine/strike_alert_web.zip, which the Web export preset uses.
#
# Needs, all on D: (drive C: is nearly full):
#   D:/Toolchains/godot-4.7.2  git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git
#   D:/Toolchains/emsdk        git clone https://github.com/emscripten-core/emsdk.git
#                              then: emsdk install 4.0.11 && emsdk activate 4.0.11
#                              (the version Godot 4.7.2's own web builds use)
#   SCons                      python -m pip install --user scons
#
# Takes 30-90 minutes. Run from Git Bash: bash tools/web_engine/build.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="${GODOT_SRC:-/d/Toolchains/godot-4.7.2}"
emsdk="${EMSDK_DIR:-/d/Toolchains/emsdk}"

# Emscripten's environment (emcc on the PATH, EMSDK set).
export EMSDK_QUIET=1
source "$emsdk/emsdk_env.sh" > /dev/null

cd "$src"
# SCons runs on Windows Python, which cannot open a /d/... style path.
profile="$here/custom.py"
command -v cygpath > /dev/null && profile="$(cygpath -w "$profile")"
# target and optimize go on the command line: the web platform's own defaults
# (template_debug, size) override them in a profile file.
python -m SCons profile="$profile" target=template_release optimize=size -j"$(nproc)"
cp bin/godot.web.template_release.wasm32.nothreads.zip "$here/strike_alert_web.zip"
ls -la "$here/strike_alert_web.zip"
