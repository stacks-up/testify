#!/bin/bash
# ============================================================
# Create the self-signed code-signing identity used to sign
# Testify.app. Run ONCE per machine.
#
# A stable signing identity gives the app a stable TCC
# "designated requirement", so Accessibility / Screen Recording /
# Automation grants persist across rebuilds (grant once).
#
# To remove later:  delete "Testify Signing" from
# Keychain Access (login keychain), then re-run this script.
# ============================================================
set -euo pipefail

CN="Testify Signing"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CN"; then
    echo "Identity \"$CN\" already exists. Nothing to do."
    exit 0
fi

# OpenSSL 3 is required: step 2 uses `pkcs12 -legacy`. The openssl that ships
# with macOS is LibreSSL, which lacks that option and would fail partway through.
#
# Prints the major version of the OpenSSL binary $1, or nothing if it is
# missing or isn't OpenSSL (e.g. LibreSSL).
openssl_major() {
    { "$1" version 2>/dev/null || true; } | sed -nE 's/^OpenSSL ([0-9]+)\..*/\1/p'
}
OPENSSL_VERSION="$(openssl version 2>/dev/null || echo "not found")"
OPENSSL_MAJOR="$(openssl_major openssl)"
if [[ -z "$OPENSSL_MAJOR" || "$OPENSSL_MAJOR" -lt 3 ]]; then
    echo "This script needs OpenSSL 3 or later, but \`openssl\` on your PATH is: $OPENSSL_VERSION" >&2
    echo "(macOS ships LibreSSL, which lacks the \`pkcs12 -legacy\` option used here.)" >&2
    echo >&2
    # If Homebrew's OpenSSL is installed but not first on PATH, say exactly how to use it.
    for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl; do
        if [[ -x "$candidate" && "$(openssl_major "$candidate")" -ge 3 ]]; then
            echo "Homebrew's OpenSSL 3 is installed but isn't first on your PATH. Run:" >&2
            echo "  PATH=\"$(dirname "$candidate"):\$PATH\" $0" >&2
            exit 1
        fi
    done
    echo "Install it with Homebrew, then re-run this script:" >&2
    echo "  brew install openssl@3" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Self-signed cert with a code-signing extended key usage.
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$CN" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature"

# 2. Bundle into PKCS#12. -legacy is required so macOS's `security`
#    can read the MAC (OpenSSL 3.x defaults to an algorithm it rejects).
openssl pkcs12 -export -legacy -out "$TMP/cert.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:testify -name "$CN"

# 3. Import key+cert, letting only codesign use the private key without a
#    prompt. Deliberately no -A: that would let ANY app silently use or export
#    the key, and anything signed with it would inherit Testify's TCC grants
#    (Accessibility, Screen Recording), since they're keyed to this cert.
#    The -P password only protects the temporary .p12, deleted on exit.
security import "$TMP/cert.p12" -k "$KC" -P "testify" -T /usr/bin/codesign

# 4. Trust it for code signing in the user domain (no sudo).
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"

echo
security find-identity -v -p codesigning | grep "$CN"
echo "Created. Now run ./package.sh"
