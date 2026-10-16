#!/bin/zsh
# Builds ClaudeUsage.app (menu bar app) from the Swift package.
# With --install it also replaces /Applications/ClaudeUsage.app and relaunches it.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/ClaudeUsage.app"
ICON="$ROOT/.build/AppIcon.icns"
INSTALLED="/Applications/ClaudeUsage.app"

cd "$ROOT"
swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/ClaudeUsage" "$APP/Contents/MacOS/ClaudeUsage"

# The icon is drawn by a script; only redraw it when the script changes.
if [[ ! -f "$ICON" || "$ROOT/scripts/make-icon.swift" -nt "$ICON" ]]; then
    swift "$ROOT/scripts/make-icon.swift" "$ROOT/.build/AppIcon.iconset"
    iconutil -c icns "$ROOT/.build/AppIcon.iconset" -o "$ICON"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Usage</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleIdentifier</key><string>com.saidilhalim.claudeusage</string>
    <key>CFBundleExecutable</key><string>ClaudeUsage</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Used to bring the terminal tab running a Claude session to the front.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    # Quit the running copy, swap in the new build, and start it again.
    pkill -x ClaudeUsage 2>/dev/null || true
    for _ in {1..50}; do pgrep -x ClaudeUsage >/dev/null || break; sleep 0.1; done
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    touch "$INSTALLED" # so Finder picks up the icon
    open "$INSTALLED"
    echo "Installed and relaunched $INSTALLED"
else
    echo "Install and relaunch:  ./scripts/build-app.sh --install"
fi
