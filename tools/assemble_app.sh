#!/bin/sh
# What every build of the app carries besides its code: the fonts, the licenses and the daemon.
# Xcode runs this as the app target's last build phase, so an app run from Xcode is a whole app.
# build.sh adds what only it knows: the firmware, Python, the version, and the signature.
#   tools/assemble_app.sh path/to/ttycat.app
set -eu

APP=$1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RES="$APP/Contents/Resources"

mkdir -p "$RES/daemon"
cp "$ROOT"/tools/fonts/*.ttf "$ROOT"/tools/fonts/OFL-*.txt "$RES/"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$ROOT/THIRD_PARTY.md" "$RES/"
[ -f "$ROOT/daemon/ttycatd.py" ] || { echo "error: no daemon: git submodule update --init" >&2; exit 1; }
cp "$ROOT"/daemon/*.py "$ROOT/daemon/agent_rules.json" "$ROOT/daemon/agent_rules.LICENSE" "$RES/daemon/"
