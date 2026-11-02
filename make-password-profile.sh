#!/bin/bash
# ============================================================
# Generate a macOS configuration profile that enforces your
# device password policy.
#
# The policy values come from password-policy.conf, which is
# git-ignored so your organisation's policy is never published.
# Start from the example:
#   cp password-policy.conf.example password-policy.conf
#
# NOTE: the passcode payload treats maxFailedAttempts as a
# login delay rather than an account lock, and cannot express
# pwpolicy's minutesUntilFailedLoginReset. For exact lockout
# behaviour, use pwpolicy -setglobalpolicy instead.
#
# Output: dist/BYOD-PasswordPolicy.mobileconfig  (double-click to install)
#
# Evidence after install:
#   System Settings > General > Device Management
#     -> "BYOD Password Policy"
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

CONF="password-policy.conf"
if [[ ! -f "$CONF" ]]; then
    echo "Missing $CONF. Create it from the example and set your policy:" >&2
    echo "  cp $CONF.example $CONF" >&2
    exit 1
fi
# shellcheck source=password-policy.conf.example
source "$CONF"

for var in ORGANISATION DESCRIPTION MIN_LENGTH REQUIRE_ALPHANUMERIC \
           MIN_COMPLEX_CHARS ALLOW_SIMPLE MAX_FAILED_ATTEMPTS MAX_PIN_AGE_DAYS; do
    if [[ -z "${!var:-}" ]]; then
        echo "$CONF: $var is not set (see $CONF.example)" >&2
        exit 1
    fi
done
for var in MIN_LENGTH MIN_COMPLEX_CHARS MAX_FAILED_ATTEMPTS MAX_PIN_AGE_DAYS; do
    [[ "${!var}" =~ ^[0-9]+$ ]] || { echo "$CONF: $var must be a whole number" >&2; exit 1; }
done
for var in REQUIRE_ALPHANUMERIC ALLOW_SIMPLE; do
    [[ "${!var}" == true || "${!var}" == false ]] \
        || { echo "$CONF: $var must be true or false" >&2; exit 1; }
done

# Free text goes into XML, so escape it.
xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
    printf '%s' "$s"
}

DIST="dist"
mkdir -p "$DIST"
OUT="$DIST/BYOD-PasswordPolicy.mobileconfig"
PROFILE_UUID="$(uuidgen)"
PAYLOAD_UUID="$(uuidgen)"

# Expiry is omitted entirely when MAX_PIN_AGE_DAYS is 0 (never expires).
PIN_AGE=""
if (( MAX_PIN_AGE_DAYS > 0 )); then
    PIN_AGE="
            <key>maxPINAgeInDays</key>
            <integer>$MAX_PIN_AGE_DAYS</integer>"
fi

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
            <key>minLength</key>
            <integer>$MIN_LENGTH</integer>
            <key>allowSimple</key>
            <$ALLOW_SIMPLE/>
            <key>requireAlphanumeric</key>
            <$REQUIRE_ALPHANUMERIC/>
            <key>minComplexChars</key>
            <integer>$MIN_COMPLEX_CHARS</integer>
            <!-- macOS: login delays after this many failures, not an account lock -->
            <key>maxFailedAttempts</key>
            <integer>$MAX_FAILED_ATTEMPTS</integer>$PIN_AGE
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
    <string>$(xml_escape "$DESCRIPTION")</string>
    <key>PayloadOrganization</key>
    <string>$(xml_escape "$ORGANISATION")</string>
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
