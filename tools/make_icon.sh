#!/bin/sh
# The app's icon is Bit, drawn by the app itself: the same sprite as everywhere else. Run this after
# changing how Bit looks, with a built app, and commit what it writes.
#   tools/make_icon.sh [path/to/ttycat.app]
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:-$ROOT/build/ttycat.app}
OUT="$ROOT/App/Assets.xcassets/AppIcon.appiconset"
WORK=$(mktemp -d)
"$APP/Contents/MacOS/ttycat" --iconset "$WORK/AppIcon.iconset"
cp "$WORK"/AppIcon.iconset/*.png "$OUT/"
rm -rf "$WORK"
echo "written: $OUT"
