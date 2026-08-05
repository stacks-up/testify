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

# 3. Import key+cert and let codesign use the private key (-A).
security import "$TMP/cert.p12" -k "$KC" -P "testify" -T /usr/bin/codesign -A

# 4. Trust it for code signing in the user domain (no sudo).
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"

echo
security find-identity -v -p codesigning | grep "$CN"
echo "Created. Now run ./package.sh"
