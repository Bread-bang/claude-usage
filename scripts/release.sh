#!/usr/bin/env bash
# Builds, Developer ID-signs, notarizes, staples, and zips a distributable .app.
#
# Prerequisites (one-time):
#   1. Paid Apple Developer Program membership.
#   2. A "Developer ID Application" certificate installed in your login Keychain
#      (developer.apple.com → Certificates → "+" → Developer ID Application).
#   3. Stored notarytool credentials:
#        xcrun notarytool store-credentials ClaudeUsageMiniBar \
#          --apple-id "<your-apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
#      (App-specific password: appleid.apple.com → Sign-In and Security → App-Specific Passwords.)
#
# Usage:  ./scripts/release.sh
# Env overrides:
#   SIGN_ID         Developer ID Application identity (auto-detected if unset)
#   NOTARY_PROFILE  notarytool keychain profile name (default: ClaudeUsageMiniBar)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageMiniBar"
BUNDLE_NAME="Claude Usage.app"
VERSION="$(cat VERSION)"
DIST="dist"
APP_DIR="$DIST/$BUNDLE_NAME"
ZIP_PATH="$DIST/ClaudeUsage-$VERSION.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-ClaudeUsageMiniBar}"

# Resolve the Developer ID Application identity.
SIGN_ID="${SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
fi
if [[ -z "$SIGN_ID" ]]; then
    echo "ERROR: No 'Developer ID Application' identity found. See the prerequisites in this script." >&2
    exit 1
fi
echo "==> Signing identity: $SIGN_ID"

echo "==> Building release binary…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_DIR …"
rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Code signing (Developer ID + hardened runtime)…"
# Hardened runtime (--options runtime) and a secure timestamp are required for notarization.
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

echo "==> Zipping for notarization…"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the notarization ticket…"
xcrun stapler staple "$APP_DIR"
spctl --assess --type execute --verbose=4 "$APP_DIR" || true

echo "==> Re-zipping the stapled app for distribution…"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo
echo "✅ Done."
echo "   Artifact : $ZIP_PATH"
echo "   Version  : $VERSION"
echo "   sha256   : $SHA"
echo
echo "Next: attach $ZIP_PATH to a GitHub Release tagged v$VERSION, then update the"
echo "      sha256 and version in your tap's Casks/claude-usage.rb."
