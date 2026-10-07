#!/bin/bash
# Run the tests. With Xcode selected `swift test` is enough; the Command Line Tools
# ship the Testing framework too, but outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")"

DEVELOPER="$(xcode-select -p)/Library/Developer"
if [ -d "$DEVELOPER/Frameworks/Testing.framework" ]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$DEVELOPER/Frameworks" \
        -Xlinker -F -Xlinker "$DEVELOPER/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEVELOPER/Frameworks" \
        -Xlinker -rpath -Xlinker "$DEVELOPER/usr/lib" "$@"
fi
exec swift test "$@"
