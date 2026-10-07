#!/bin/bash
# Build SessionBar and put it in /Applications, or in ~/Applications when that folder
# can't be written to. Run it again to update.
set -euo pipefail
cd "$(dirname "$0")"

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
./build.sh "$BUILD"

# A running copy is replaced, wherever it was started from.
pkill -x SessionBar 2>/dev/null || true
rm -rf "$DEST/SessionBar.app"
ditto "$BUILD/SessionBar.app" "$DEST/SessionBar.app"
open "$DEST/SessionBar.app"
echo "Installed $DEST/SessionBar.app"
