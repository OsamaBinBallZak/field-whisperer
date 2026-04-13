#!/bin/bash
# Creates a drag-to-Applications DMG for FieldWhisperer.
# Run from the project root: bash Distribution/create-dmg.sh
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FieldWhisperer"
DMG_NAME="${APP_NAME}.dmg"
DERIVED_DATA="/tmp/FW-build"
BUILD_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
DMG_DIR="/tmp/FW-dmg"
RW_DMG="/tmp/${APP_NAME}-rw.dmg"
OUT_DMG=~/Desktop/"${DMG_NAME}"

echo "▶ Building Release..."
xcodebuild \
  -project "${PROJECT_ROOT}/FieldWhisperer.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  build 2>&1 | grep -E "(error:|warning:|Build succeeded|Build FAILED)"

if [ ! -d "${BUILD_APP}" ]; then
  echo "❌ Build failed — ${BUILD_APP} not found."
  exit 1
fi

echo "▶ Ad-hoc signing for distribution..."
codesign --force --deep --sign - "${BUILD_APP}"

echo "▶ Staging DMG contents..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${BUILD_APP}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

# Optional custom background (place Distribution/dmg-background.png in the repo)
if [ -f "${PROJECT_ROOT}/Distribution/dmg-background.png" ]; then
  mkdir -p "${DMG_DIR}/.background"
  cp "${PROJECT_ROOT}/Distribution/dmg-background.png" "${DMG_DIR}/.background/background.png"
  HAS_BACKGROUND=1
else
  HAS_BACKGROUND=0
fi

echo "▶ Creating read-write DMG..."
hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${DMG_DIR}" \
  -ov -format UDRW \
  "${RW_DMG}" > /dev/null

echo "▶ Mounting and configuring Finder layout..."
MOUNT_DIR=$(hdiutil attach "${RW_DMG}" | grep "Volumes" | awk '{print $NF}')

if [ "${HAS_BACKGROUND}" -eq 1 ]; then
  BG_SCRIPT='set background picture of viewOptions to file ".background:background.png"'
else
  BG_SCRIPT=''
fi

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${APP_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 700, 500}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    ${BG_SCRIPT}
    set position of item "${APP_NAME}.app" of container window to {160, 230}
    set position of item "Applications" of container window to {460, 230}
    close
    open
    update without registering applications
    close
  end tell
end tell
APPLESCRIPT

sleep 2
hdiutil detach "${MOUNT_DIR}" > /dev/null

echo "▶ Converting to compressed read-only DMG..."
hdiutil convert "${RW_DMG}" -format UDZO -o "${OUT_DMG}" > /dev/null
rm "${RW_DMG}"

echo "✅ Done: ${OUT_DMG}"
echo ""
echo "Share this DMG with your friends."
echo "They open it, drag FieldWhisperer to Applications, then right-click → Open on first launch."
