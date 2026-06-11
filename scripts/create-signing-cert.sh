#!/usr/bin/env bash
# Creates a self-signed *local* code-signing identity in your login Keychain.
#
# Why: the app reads Claude Code's Keychain item. macOS ties the "Always Allow" grant to
# the app's code signature. Ad-hoc signatures change on every build, so the grant keeps
# resetting and the password prompt reappears. A stable self-signed identity fixes that —
# grant "Always Allow" once and it persists across all future rebuilds.
#
# This identity is for LOCAL use only. It is not trusted by Gatekeeper and is not for
# distribution (use a real Developer ID + notarization for that). Run this once.
set -euo pipefail

IDENTITY_NAME="${CLAUDE_USAGE_SIGN_ID:-ClaudeUsageMiniBar Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "Identity '$IDENTITY_NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12_PASS="temp-$$"

cat > "$TMP/cs.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> Generating key + self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/cs.key" -out "$TMP/cs.crt" -days 3650 -config "$TMP/cs.cnf" 2>/dev/null

echo "==> Packaging as PKCS#12 (legacy algorithms for macOS compatibility)…"
# OpenSSL 3 defaults to algorithms macOS cannot import; -legacy restores the old ones.
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/cs.key" -in "$TMP/cs.crt" \
    -out "$TMP/cs.p12" -passout "pass:$P12_PASS" -name "$IDENTITY_NAME"

echo "==> Importing into the login Keychain (allowing codesign to use it)…"
security import "$TMP/cs.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign

if security find-identity -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "✅ Done. '$IDENTITY_NAME' is ready. Re-run scripts/bundle.sh and grant"
    echo "   'Always Allow' once — it will now persist across rebuilds."
else
    echo "⚠️  Imported, but the identity did not appear. You may need to create it via"
    echo "    Keychain Access → Certificate Assistant → Create a Certificate"
    echo "    (Self-Signed Root, type: Code Signing)."
    exit 1
fi
