#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${1:-release}"
SIGNING_MODE="${SNAPMARK_SIGNING_MODE:-stable}"
UNIVERSAL_BUILD="${SNAPMARK_UNIVERSAL:-0}"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/SnapMark.zip"
CHECKSUM_PATH="$DIST_DIR/SnapMark.zip.sha256"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SnapMarkPackage.XXXXXX")"
APP_DIR="$STAGING_DIR/SnapMark.app"
CONTENTS_DIR="$APP_DIR/Contents"
TEMP_ARCHIVE="$DIST_DIR/.SnapMark.$$.zip"
TEMP_CHECKSUM="$DIST_DIR/.SnapMark.$$.sha256"
LEGACY_APP="$DIST_DIR/SnapMark.app"

cleanup() {
    /bin/rm -rf -- "$STAGING_DIR"
    /bin/rm -f -- "$TEMP_ARCHIVE" "$TEMP_CHECKSUM"
}
trap cleanup EXIT

cd "$PROJECT_DIR"

mkdir -p "$DIST_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    ARM_SCRATCH="$STAGING_DIR/build-arm64"
    INTEL_SCRATCH="$STAGING_DIR/build-x86_64"
    swift build -c "$CONFIGURATION" \
        --triple arm64-apple-macosx14.0 \
        --scratch-path "$ARM_SCRATCH" \
        -Xswiftc -warnings-as-errors
    ARM_BIN_DIR="$(swift build -c "$CONFIGURATION" \
        --triple arm64-apple-macosx14.0 \
        --scratch-path "$ARM_SCRATCH" \
        --show-bin-path)"

    swift build -c "$CONFIGURATION" \
        --triple x86_64-apple-macosx14.0 \
        --scratch-path "$INTEL_SCRATCH" \
        -Xswiftc -warnings-as-errors
    INTEL_BIN_DIR="$(swift build -c "$CONFIGURATION" \
        --triple x86_64-apple-macosx14.0 \
        --scratch-path "$INTEL_SCRATCH" \
        --show-bin-path)"

    /usr/bin/lipo -create \
        "$ARM_BIN_DIR/SnapMark" \
        "$INTEL_BIN_DIR/SnapMark" \
        -output "$CONTENTS_DIR/MacOS/SnapMark"
    /usr/bin/lipo "$CONTENTS_DIR/MacOS/SnapMark" -verify_arch arm64 x86_64
    chmod 755 "$CONTENTS_DIR/MacOS/SnapMark"
else
    swift build -c "$CONFIGURATION" -Xswiftc -warnings-as-errors
    BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
    install -m 755 "$BIN_DIR/SnapMark" "$CONTENTS_DIR/MacOS/SnapMark"
fi

install -m 644 "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$PROJECT_DIR/Assets/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
install -m 644 "$PROJECT_DIR/Packaging/PrivacyInfo.xcprivacy" "$CONTENTS_DIR/Resources/PrivacyInfo.xcprivacy"

/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist" "$CONTENTS_DIR/Resources/PrivacyInfo.xcprivacy"

# Screen Recording grants are attached to an app's designated code requirement.
# Ad-hoc signatures use the executable hash as that requirement, so every rebuild
# looks like a different recorder. Prefer an explicitly supplied Apple identity;
# otherwise use SnapMark's persistent local certificate. Never silently fall back
# to ad-hoc signing, because that would invalidate an existing permission grant.
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    codesign --force --deep --options runtime --sign - "$APP_DIR"
elif [[ "$SIGNING_MODE" != "stable" ]]; then
    print -u2 "Unknown SNAPMARK_SIGNING_MODE: $SIGNING_MODE. Use stable or adhoc."
    exit 1
elif [[ -n "${SNAPMARK_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SNAPMARK_SIGNING_IDENTITY" "$APP_DIR"
else
    USER_HOME_DIR="${HOME:?HOME is required to locate SnapMark's local signing files}"
    LOCAL_SUPPORT_DIR="$USER_HOME_DIR/Library/Application Support/SnapMark"
    LOCAL_SIGNER="$LOCAL_SUPPORT_DIR/Tools/rcodesign"
    LOCAL_SIGNING_DIR="$LOCAL_SUPPORT_DIR/Signing"
    LOCAL_P12="$LOCAL_SIGNING_DIR/SnapMarkLocal.p12"
    LOCAL_PASSWORD="$LOCAL_SIGNING_DIR/p12-password"
    LOCAL_REQUIREMENT="$LOCAL_SIGNING_DIR/SnapMarkRequirement.bin"

    if [[ ! -x "$LOCAL_SIGNER" || ! -r "$LOCAL_P12" || ! -r "$LOCAL_PASSWORD" || ! -r "$LOCAL_REQUIREMENT" ]]; then
        print -u2 "Stable SnapMark signing files are missing. Refusing an ad-hoc build that would invalidate Screen Recording access."
        print -u2 "Restore $LOCAL_SIGNING_DIR or set SNAPMARK_SIGNING_IDENTITY to a persistent Apple code-signing identity."
        exit 1
    fi

    "$LOCAL_SIGNER" sign \
        --p12-file "$LOCAL_P12" \
        --p12-password-file "$LOCAL_PASSWORD" \
        --code-requirements-file "$LOCAL_REQUIREMENT" \
        --code-signature-flags runtime \
        --timestamp-url none \
        "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
SIGNATURE_DETAILS="$(codesign -dvvv "$APP_DIR" 2>&1)"
if [[ "$SIGNING_MODE" != "adhoc" && "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]]; then
    print -u2 "SnapMark was signed ad-hoc; refusing to package a build that would invalidate Screen Recording access."
    exit 1
fi
if [[ "$SIGNATURE_DETAILS" != *"runtime)"* ]]; then
    print -u2 "SnapMark is missing the hardened runtime signature flag."
    exit 1
fi

# A build artifact with the production bundle identifier can be auto-registered by
# Launch Services when inspected or launched during QA. Keep only the installed copy
# discoverable so Spotlight/Finder never presents a second SnapMark application.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
    if [[ -d "$LEGACY_APP" ]]; then
        "$LSREGISTER" -u "$LEGACY_APP" >/dev/null 2>&1 || true
    fi
fi

# Archive the app so the source tree contains no second discoverable .app bundle.
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_DIR" "$TEMP_ARCHIVE"
/bin/mv -f -- "$TEMP_ARCHIVE" "$ARCHIVE_PATH"
(cd "$DIST_DIR" && /usr/bin/shasum -a 256 "$(basename "$ARCHIVE_PATH")") > "$TEMP_CHECKSUM"
/bin/mv -f -- "$TEMP_CHECKSUM" "$CHECKSUM_PATH"
/usr/bin/unzip -tq "$ARCHIVE_PATH"

# Remove the obsolete uncompressed build artifact created by releases before 1.0.5.
if [[ -d "$LEGACY_APP" ]]; then
    /bin/mv -- "$LEGACY_APP" "$STAGING_DIR/Legacy-SnapMark-Bundle"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CONTENTS_DIR/Info.plist")"
ARCHITECTURES="$(/usr/bin/lipo -archs "$CONTENTS_DIR/MacOS/SnapMark")"
print "Built SnapMark $VERSION for $ARCHITECTURES at $ARCHIVE_PATH"
print "Checksum: $CHECKSUM_PATH"
