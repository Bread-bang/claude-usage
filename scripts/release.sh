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

# Swift Build (SwiftPM's default build system since Swift 6.4) records the deployment target
# (13.0) as the binary's SDK version. macOS 26 then runs the app in pre-26 compatibility mode
# and draws the MenuBarExtra panel's legacy square frame inside the Liquid Glass window — how
# 0.4.2 shipped. The binary *was* compiled against the current SDK, so write that version back,
# then refuse to continue if the stamp still disagrees.
SDK_VERSION="$(xcrun --show-sdk-version)"
APP_BIN="$APP_DIR/Contents/MacOS/$APP_NAME"
MIN_OS="$(vtool -show-build "$APP_BIN" | awk '$1 == "minos" { print $2; exit }')"
vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace -output "$APP_BIN.stamped" "$APP_BIN"
mv "$APP_BIN.stamped" "$APP_BIN"
STAMPED_SDK="$(vtool -show-build "$APP_BIN" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$STAMPED_SDK" != "$SDK_VERSION" ]]; then
    echo "ERROR: binary records SDK $STAMPED_SDK, expected $SDK_VERSION — not shipping it." >&2
    exit 1
fi
echo "==> Stamped SDK $SDK_VERSION (minos $MIN_OS) into $APP_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
# Stamp VERSION into the copied Info.plist so the app reports the release it ships as
# (the checked-in plist only holds placeholders; 0.3.0–0.4.2 all said "0.2.0").
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                        -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# SwiftPM emits a resource bundle for artwork (Clawd mascot, Claude spark). Copy it in
# before signing so the seal covers it. `Artwork` looks it up in Contents/Resources itself;
# SwiftPM's `Bundle.module` alone cannot find it there (see Artwork.swift).
RES_BUNDLE="$(swift build -c release --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
    echo "==> Bundled resources: $(basename "$RES_BUNDLE")"
fi

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

echo "==> Smoke test: launching the app as a user's machine would…"
# SwiftPM's `Bundle.module` falls back to this machine's absolute .build path, so a resource
# bundle the .app cannot find still loads here while every other Mac crashes at launch —
# exactly how 0.4.0 and 0.4.1 shipped broken. Hide that path for the duration of the launch.
if [ -d "$RES_BUNDLE" ]; then
    mv "$RES_BUNDLE" "$RES_BUNDLE.smoke-hidden"
    trap 'mv "$RES_BUNDLE.smoke-hidden" "$RES_BUNDLE"' EXIT
fi
"$APP_DIR/Contents/MacOS/$APP_NAME" >/dev/null 2>"$DIST/smoke.log" &
SMOKE_PID=$!
sleep 5
if ! kill -0 "$SMOKE_PID" 2>/dev/null; then
    echo "ERROR: the app exited during launch — not shipping it. Its stderr:" >&2
    cat "$DIST/smoke.log" >&2
    exit 1
fi
kill "$SMOKE_PID"
wait "$SMOKE_PID" 2>/dev/null || true
rm -f "$DIST/smoke.log"

echo "==> Re-zipping the stapled app for distribution…"
# --norsrc --noextattr strips macOS resource forks and extended attributes so the archive
# carries no AppleDouble (`._*`) sidecar files. Safe here because the notarization ticket
# lives in a real file (Contents/CodeResources), not an xattr — verified with
# `stapler validate` after a clean round-trip — so neither stapling nor the code signature
# depends on the xattrs we drop. (The notarization-submission zip above keeps Apple's
# default ditto invocation; it's discarded after upload.)
rm -f "$ZIP_PATH"
ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$ZIP_PATH"

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo
echo "✅ Done."
echo "   Artifact : $ZIP_PATH"
echo "   Version  : $VERSION"
echo "   sha256   : $SHA"
echo
echo "Next: attach $ZIP_PATH to a GitHub Release tagged v$VERSION, then update the"
echo "      sha256 and version in your tap's Casks/claude-usage.rb."
