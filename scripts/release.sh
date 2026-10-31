#!/bin/zsh
# Builds noNotch and packages a drag-to-install DMG plus a ZIP.
#
#   scripts/release.sh
#
# Optional environment:
#   SIGN_IDENTITY   "Developer ID Application: …" (default: ad-hoc "-")
#   NOTARY_PROFILE  notarytool keychain profile; when set, the DMG is notarized and stapled
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"

APP_NAME=noNotch
DEFAULT_IDENTITY="-"
if security find-certificate -c "GeniusSoft Development" >/dev/null 2>&1; then
  DEFAULT_IDENTITY="GeniusSoft Development"
fi
SIGN_IDENTITY=${SIGN_IDENTITY:-$DEFAULT_IDENTITY}
DIST="$ROOT/dist"
STAGE="$DIST/stage"
VERSION=$(grep 'CFBundleShortVersionString' project.yml | sed -E 's/.*"(.*)".*/\1/')

echo "▸ Building $APP_NAME $VERSION"
xcodegen generate -q
xcodebuild -scheme "$APP_NAME" -configuration Release -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

rm -rf "$DIST"
mkdir -p "$STAGE"
ditto "build/Build/Products/Release/$APP_NAME.app" "$STAGE/$APP_NAME.app"

echo "▸ Signing ($SIGN_IDENTITY)"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == Developer\ ID* ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
else
  SIGN_ARGS+=(--timestamp=none)
fi
codesign "${SIGN_ARGS[@]}" "$STAGE/$APP_NAME.app/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign "${SIGN_ARGS[@]}" "$STAGE/$APP_NAME.app/Contents/Helpers/nonotch-mcp"
codesign "${SIGN_ARGS[@]}" --entitlements "$APP_NAME/$APP_NAME.entitlements" "$STAGE/$APP_NAME.app"
codesign --verify --deep --strict "$STAGE/$APP_NAME.app"

echo "▸ Creating DMG"
# A mounted older copy has the same volume name and would receive the Finder layout instead.
for vol in /Volumes/$APP_NAME*(N); do hdiutil detach -quiet -force "$vol" || true; done
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
swift scripts/make-dmg-background.swift "$DIST/bg@2x.png" "$VERSION"
# Multi-resolution TIFF: Finder picks 1x or 2x, so the art always fills the 920×420 window.
sips -z 420 920 "$DIST/bg@2x.png" --out "$DIST/bg.png" >/dev/null
tiffutil -cathidpicheck "$DIST/bg.png" "$DIST/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
rm -f "$DIST/bg.png" "$DIST/bg@2x.png"

# Disk icon: the app icon on the mounted volume.
ICONSET="$DIST/VolumeIcon.iconset"
mkdir -p "$ICONSET"
for f in "$APP_NAME"/Assets.xcassets/AppIcon.appiconset/icon_*.png; do
  cp "$f" "$ICONSET/$(basename "$f" | sed 's/@1x//')"
done
iconutil -c icns "$ICONSET" -o "$DIST/VolumeIcon.icns"
rm -rf "$ICONSET"

RW_DMG="$DIST/rw.dmg"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG"

# Lay out the Finder window (icon positions + background). Cosmetic: skipped if Finder automation is denied.
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
osascript <<APPLESCRIPT || echo "  (Finder layout skipped)"
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 1120, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {300, 236}
    set position of item "Applications" of container window to {620, 236}
    update without registering applications
    delay 1
    -- Re-apply the size after the view options; Finder can widen the window otherwise.
    set the bounds of container window to {200, 120, 1120, 568}
    delay 2
    close
  end tell
end tell
APPLESCRIPT
# hdiutil skips .VolumeIcon.icns from -srcfolder, so add it to the mounted volume.
cp "$DIST/VolumeIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
sync
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG" "$DIST/VolumeIcon.icns"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "▸ Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "▸ Creating ZIP"
ditto -c -k --keepParent "$STAGE/$APP_NAME.app" "$DIST/$APP_NAME-$VERSION.zip"
rm -rf "$STAGE"

( cd "$DIST" && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt )
echo "✓ $(ls -1 "$DIST" | tr '\n' ' ')"
echo "  in $DIST"

# Upload dist/$APP_NAME-$VERSION.dmg to a GitHub Release; the website links to releases/latest.
