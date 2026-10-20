#!/usr/bin/env bash
# Builds a release binary and assembles a menu-bar-only .app bundle in dist/.
#
# Usage:  ./scripts/bundle.sh            # build + bundle (ad-hoc signed)
#         ./scripts/bundle.sh --open     # also launch the app afterwards
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ClaudeUsageMiniBar"
BUNDLE_NAME="Claude Usage.app"
DIST="dist"
APP_DIR="$DIST/$BUNDLE_NAME"
VERSION="$(cat VERSION)"

echo "==> Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_DIR …"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

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

# SwiftPM emits a resource bundle for artwork (Clawd mascot, Claude spark). Copy it into
# Contents/Resources, where `Artwork` looks it up (SwiftPM's `Bundle.module` alone cannot find
# it there — see Artwork.swift).
RES_BUNDLE="$(swift build -c release --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
    echo "==> Bundled resources: $(basename "$RES_BUNDLE")"
fi

# Sign with a STABLE identity so the Keychain "Always Allow" grant survives rebuilds.
# Ad-hoc signatures change every build (CDHash-based), which invalidates the grant and
# re-triggers the Keychain password prompt each launch. A self-signed local identity keeps
# the designated requirement constant. Run scripts/create-signing-cert.sh once to create it.
SIGN_ID="${CLAUDE_USAGE_SIGN_ID:-ClaudeUsageMiniBar Local Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "==> Code signing with '$SIGN_ID'…"
    codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
    echo "==> Stable identity not found — falling back to ad-hoc (Keychain will re-prompt each build)."
    echo "    Run scripts/create-signing-cert.sh once to stop the repeated prompts."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Done: $APP_DIR"

if [[ "${1:-}" == "--open" ]]; then
    open "$APP_DIR"
fi
