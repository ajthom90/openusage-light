#!/usr/bin/env bash
set -euo pipefail

# Builds OpenUsage, stages a signed .app bundle under dist/, and launches it in place — no install
# to /Applications. The dev build:
#   - is signed with a stable Apple Development identity, so keychain/permission grants stick across
#     rebuilds (macOS keys those to the signing identity + bundle id, not the install location);
#   - uses its own bundle id (com.robinebers.openusage-light.dev), so it runs beside OpenUsage.
#
# Usage: script/build_and_run.sh [run|build|logs|verify]
# Env:   CODESIGN_IDENTITY  override signing identity (exact name or hash)
#        CONFIG             "release" (default) or "debug"
#        ICLOUD_SYNC=1      sign with an iCloud container so the app can sync to the iPhone and iPad apps. Reads the
#                           team, bundle prefix, and container from iOS/Config/Local.xcconfig (gitignored), uses the
#                           bundle id <prefix>.mac, and embeds the profile Xcode made for it (build it first with
#                           `cd iOS && xcodegen && xcodebuild -scheme OpenUsageMacSigning -allowProvisioningUpdates`).

MODE="${1:-run}"
CONFIG="${CONFIG:-release}"

TARGET_NAME="OpenUsage"                 # SwiftPM target / binary name
APP_DISPLAY="OpenUsage Light"           # user-facing app name
BUNDLE_ID="${BUNDLE_ID:-com.robinebers.openusage-light.dev}"
ICLOUD_PLIST_KEY=""
ICLOUD_PROFILE=""
if [ "${ICLOUD_SYNC:-}" = "1" ]; then
  LOCAL_XCCONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/iOS/Config/Local.xcconfig"
  [ -f "$LOCAL_XCCONFIG" ] || { echo "ICLOUD_SYNC=1 needs $LOCAL_XCCONFIG" >&2; exit 1; }
  xcconfig_value() { /usr/bin/sed -n "s/^$1 *= *//p" "$LOCAL_XCCONFIG" | /usr/bin/sed 's/[[:space:]]*$//'; }
  ICLOUD_CONTAINER="$(xcconfig_value ICLOUD_CONTAINER)"
  BUNDLE_ID="${BUNDLE_ID_OVERRIDE:-$(xcconfig_value BUNDLE_ID_PREFIX).mac}"
  PROFILE_NAME="Mac Team Provisioning Profile: $BUNDLE_ID"
  for profile in "$HOME"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.provisionprofile; do
    name="$(/usr/bin/security cms -D -i "$profile" 2>/dev/null | /usr/bin/plutil -extract Name raw -o - - 2>/dev/null || true)"
    [ "$name" = "$PROFILE_NAME" ] && ICLOUD_PROFILE="$profile"
  done
  [ -n "$ICLOUD_PROFILE" ] || { echo "no provisioning profile named '$PROFILE_NAME'; build the OpenUsageMacSigning scheme first" >&2; exit 1; }
  ICLOUD_PLIST_KEY="<key>ICloudContainer</key><string>$ICLOUD_CONTAINER</string>"
  echo "==> iCloud sync build ($BUNDLE_ID)"
fi
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="0.1.0"
APP_BUILD="0.1.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$TARGET_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="${TARGET_NAME}_${TARGET_NAME}.bundle"
SIGN_ENTITLEMENTS="$ROOT_DIR/script/OpenUsage.local.entitlements.plist"

pkill -x "$TARGET_NAME" >/dev/null 2>&1 || true

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BUILD_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$TARGET_NAME"
CLI_NAME="openusage-cli"                # the `openusage` command; named apart because paths ignore case
BUILD_CLI="$BUILD_DIR/$CLI_NAME"

if [ ! -x "$BUILD_BINARY" ]; then
  echo "missing built binary: $BUILD_BINARY" >&2
  exit 1
fi
if [ ! -x "$BUILD_CLI" ]; then
  echo "missing built command: $BUILD_CLI" >&2
  exit 1
fi
echo "==> staging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_CLI" "$APP_MACOS/$CLI_NAME"
chmod +x "$APP_MACOS/$CLI_NAME"

# SwiftPM stamps LC_BUILD_VERSION's `sdk` field with the deployment target (macOS 15), not the real
# SDK it compiled against. macOS gates the modern Liquid Glass control appearance (pop-up buttons,
# pickers, etc.) on the linked SDK — a "15.0" stamp makes AppKit fall back to legacy Aqua controls.
# Restamp the sdk to 26.0 (Tahoe, where Liquid Glass landed) while keeping minos at MIN_SYSTEM_VERSION
# so the app still runs on macOS 15 but gets the modern controls. Re-signed below.
echo "==> stamping linked SDK 26.0 for Liquid Glass controls (minos stays $MIN_SYSTEM_VERSION)"
vtool -set-build-version macos "$MIN_SYSTEM_VERSION" 26.0 -replace -output "$APP_BINARY.tmp" "$APP_BINARY"
mv "$APP_BINARY.tmp" "$APP_BINARY"
chmod +x "$APP_BINARY"
# Stage every SwiftPM resource bundle produced by the build (the app's own
# OpenUsage_OpenUsage.bundle, which carries the provider SVGs + model manifest)
# into Contents/Resources, the standard app layout. Bundle.openUsageResources
# (see Support/ResourceBundle.swift) loads it from there.
shopt -s nullglob
for bundle in "$BUILD_DIR"/*.bundle; do
  cp -R "$bundle" "$APP_RESOURCES/$(basename "$bundle")"
done
shopt -u nullglob

# Compile the Icon Composer source (assets/AppIcon.icon) into Assets.car so
# Tahoe renders the real Liquid Glass icon. CFBundleIconName below must match
# the .icon file stem ("AppIcon"). The app floor is macOS 15, so a classic .icns
# fallback is relevant there (the release build supplies one); this dev build only
# stages the Assets.car and runs on the maintainer's current OS.
echo "==> compiling app icon (actool)"
PREBUILT_ICON_DIR="$ROOT_DIR/assets/AppIcon.prebuilt"
if xcrun actool "$ROOT_DIR/assets/AppIcon.icon" --compile "$APP_RESOURCES" \
  --app-icon AppIcon \
  --enable-on-demand-resources NO \
  --development-region en \
  --target-device mac \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --output-partial-info-plist /dev/null \
  --output-format human-readable-text --errors --warnings; then
  : # compiled the icon fresh
elif [ -f "$PREBUILT_ICON_DIR/Assets.car" ]; then
  # actool is broken on some toolchains; commit 08863d7 ships a prebuilt icon so release CI bypasses
  # it. Reuse the same prebuilt here, so a failed actool doesn't abort the dev build under set -e and
  # the app still gets its real icon.
  echo "==> actool failed; using prebuilt icon (assets/AppIcon.prebuilt)"
  cp "$PREBUILT_ICON_DIR/Assets.car" "$APP_RESOURCES/Assets.car"
  [ -f "$PREBUILT_ICON_DIR/AppIcon.icns" ] && cp "$PREBUILT_ICON_DIR/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
else
  echo "WARNING: actool failed and no prebuilt icon found; continuing without an icon" >&2
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$TARGET_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION-dev</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  $ICLOUD_PLIST_KEY
</dict>
</plist>
PLIST

# Pick a stable Apple Development identity so ad-hoc cdhash churn doesn't re-trigger
# permission prompts on every rebuild. Fall back to ad-hoc only if none is found.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$CODESIGN_IDENTITY" ]; then
  CODESIGN_IDENTITY=$(/usr/bin/security find-identity -p codesigning -v 2>/dev/null \
    | /usr/bin/awk -F\" '/Apple Development:/ { print $2; exit }')
fi

if [ -n "$ICLOUD_PROFILE" ]; then
  # The signed entitlements must be the ones the profile grants: take them from it, as Xcode does.
  /bin/cp "$ICLOUD_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
  SIGN_ENTITLEMENTS="$(/usr/bin/mktemp -t openusage-entitlements).plist"
  /usr/bin/security cms -D -i "$ICLOUD_PROFILE" | /usr/bin/plutil -extract Entitlements xml1 -o "$SIGN_ENTITLEMENTS" -
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
  # The command reads the app's own Keychain items, which trust the app's code identity. Signing it
  # with the app's identifier and certificate gives it that identity, so it reads them without a prompt.
  /usr/bin/codesign --force --options runtime --identifier "$BUNDLE_ID" \
    --sign "$CODESIGN_IDENTITY" "$APP_MACOS/$CLI_NAME" >/dev/null
  /usr/bin/codesign --force --options runtime \
    --sign "$CODESIGN_IDENTITY" \
    --entitlements "$SIGN_ENTITLEMENTS" \
    "$APP_BUNDLE" >/dev/null
  echo "==> signed with: $CODESIGN_IDENTITY"
else
  /usr/bin/codesign --force --sign - --entitlements "$SIGN_ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
  echo "WARNING: no Apple Development identity found; ad-hoc signed." >&2
fi

launch_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    launch_app
    echo "==> launched $APP_DISPLAY (dist/$APP_DISPLAY.app)"
    ;;
  build)
    : # build + stage + sign only
    ;;
  logs)
    launch_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$TARGET_NAME\""
    ;;
  verify)
    launch_app
    sleep 1
    pgrep -x "$TARGET_NAME" >/dev/null && echo "==> running"
    ;;
  *)
    echo "usage: $0 [run|build|logs|verify]" >&2
    exit 2
    ;;
esac
