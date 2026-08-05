#!/bin/bash
# ============================================================
# Generate a macOS configuration profile mirroring the existing
# device password policy:
#   minLength 10, no expiry, no complexity, lock after 5 fails.
#
# NOTE: the passcode payload cannot express pwpolicy's
# minutesUntilFailedLoginReset (15) and treats maxFailedAttempts
# as a login-delay rather than an account lock. For a byte-exact
# match to the screenshot, use pwpolicy -setglobalpolicy instead.
#
# Output: dist/BYOD-PasswordPolicy.mobileconfig  (double-click to install)
#
# Evidence after install:
#   System Settings > General > Device Management
#     -> "BYOD Password Policy"
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

DIST="dist"
mkdir -p "$DIST"
OUT="$DIST/BYOD-PasswordPolicy.mobileconfig"
PROFILE_UUID="$(uuidgen)"
PAYLOAD_UUID="$(uuidgen)"

cat > "$OUT" <<PROFILE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.mobiledevice.passwordpolicy</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>biz.stack.byod.passwordpolicy</string>
            <key>PayloadUUID</key>
            <string>$PAYLOAD_UUID</string>
            <key>PayloadDisplayName</key>
            <string>Password Policy</string>
            <!-- minChars=10 -->
            <key>minLength</key>
            <integer>10</integer>
            <!-- requiresAlpha/Numeric/Symbol=0 : no complexity required -->
            <key>allowSimple</key>
            <true/>
            <key>requireAlphanumeric</key>
            <false/>
            <key>minComplexChars</key>
            <integer>0</integer>
            <!-- maxFailedLoginAttempts=5 (macOS: login delays, not account lock) -->
            <key>maxFailedAttempts</key>
            <integer>5</integer>
            <!-- maxMinutesUntilChangePassword=0 : no maxPINAgeInDays => never expires -->
        </dict>
    </array>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadIdentifier</key>
    <string>biz.stack.byod.passwordpolicy.profile</string>
    <key>PayloadUUID</key>
    <string>$PROFILE_UUID</string>
    <key>PayloadDisplayName</key>
    <string>BYOD Password Policy</string>
    <key>PayloadDescription</key>
    <string>Minimum 10-character login password, no expiry, no complexity requirement, lock delay after 5 failed attempts.</string>
    <key>PayloadOrganization</key>
    <string>Stack</string>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
</dict>
</plist>
PROFILE

echo "Wrote $OUT"
echo "Validating..."
plutil -lint "$OUT"
echo
echo "Install:  double-click $OUT, then approve in System Settings."
echo "Remove :  sudo profiles remove -identifier biz.stack.byod.passwordpolicy.profile"
