#!/bin/bash
# ============================================================
# Build Testify.app - a signed .app bundle so that
# Accessibility / Screen Recording / Automation grants attach
# to THIS app, not to the terminal that launched it.
#
# Run the result with:  open dist/Testify.app   (or double-click)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

DIST="dist"                  # all built artifacts land here
BIN="Testify"
SRC="Testify.swift"
APP="$DIST/Testify.app"
BUNDLE_ID="biz.stack.testify"
IDENTITY="Testify Signing"   # self-signed cert in login keychain

# 1. Assemble the bundle skeleton and compile straight into it
#    (no loose binary left lying around in the source tree).
echo "Compiling..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/$BIN" "$SRC"

# 2. Write the bundle Info.plist.
echo "Bundling $APP..."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$BIN</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Testify</string>
    <key>CFBundleDisplayName</key>
    <string>Testify</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Shown in the Apple Events (Automation) consent prompts. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>Testify drives System Settings, Terminal, and Activity Monitor to capture security-control evidence.</string>
</dict>
</plist>
PLIST

# 3. Sign with the stable self-signed identity.
#    A stable identity + stable bundle id => stable TCC designated
#    requirement, so permissions survive rebuilds (grant once).
echo "Signing with \"$IDENTITY\"..."
codesign --force --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$APP"

# 4. Report.
echo
echo "Designated requirement (what TCC keys grants on):"
codesign -d --requirements - "$APP" 2>&1 | sed 's/^/  /'
echo
echo "Done. Launch with:  open $APP"
