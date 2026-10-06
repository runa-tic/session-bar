#!/bin/bash
# Build SessionBar.app next to this script. Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=SessionBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SessionBar" "$APP/Contents/MacOS/SessionBar"
cp roster.sh "$APP/Contents/Resources/roster.sh"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SessionBar</string>
    <key>CFBundleIdentifier</key><string>local.session-bar</string>
    <key>CFBundleName</key><string>SessionBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
