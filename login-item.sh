#!/bin/bash
# Start SessionBar at login: ./login-item.sh install | remove
set -euo pipefail
cd "$(dirname "$0")"

LABEL=com.norough.session-bar
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$(pwd)/SessionBar.app"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
install)
    [ -d "$APP" ] || { echo "no $APP; run ./build.sh first" >&2; exit 1; }
    # `open` hands the launch to LaunchServices, so the job exits at once, Quit
    # stays quit, and a second copy is never started.
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "installed $PLIST"
    ;;
remove)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed $PLIST"
    ;;
*)
    echo "usage: $0 install|remove" >&2
    exit 1
    ;;
esac
