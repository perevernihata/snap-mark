#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
ARCHIVE_PATH="${1:-$PROJECT_DIR/dist/SnapMark.zip}"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SnapMarkVerify.XXXXXX")"

cleanup() {
    /bin/rm -rf -- "$VERIFY_DIR"
}
trap cleanup EXIT

[[ -f "$ARCHIVE_PATH" ]] || { print -u2 "Missing release archive: $ARCHIVE_PATH"; exit 1; }
[[ -f "$CHECKSUM_PATH" ]] || { print -u2 "Missing checksum: $CHECKSUM_PATH"; exit 1; }

(cd "${ARCHIVE_PATH:h}" && /usr/bin/shasum -a 256 -c "${CHECKSUM_PATH:t}")
/usr/bin/unzip -tq "$ARCHIVE_PATH"
/usr/bin/ditto -x -k "$ARCHIVE_PATH" "$VERIFY_DIR"

APP_DIR="$VERIFY_DIR/SnapMark.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/SnapMark"

[[ -x "$EXECUTABLE" ]] || { print -u2 "The archive does not contain SnapMark.app."; exit 1; }
/usr/bin/plutil -lint \
    "$APP_DIR/Contents/Info.plist" \
    "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"
/usr/bin/lipo "$EXECUTABLE" -verify_arch arm64 x86_64
"$EXECUTABLE" --self-test

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
ARCHITECTURES="$(/usr/bin/lipo -archs "$EXECUTABLE")"
print "Verified SnapMark $VERSION for $ARCHITECTURES."
