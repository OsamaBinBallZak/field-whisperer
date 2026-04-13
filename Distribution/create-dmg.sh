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
  build 2>&1 | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" || true

if [ ! -d "${BUILD_APP}" ]; then
  echo "❌ Build failed — ${BUILD_APP} not found."
  exit 1
fi

echo "▶ Ad-hoc signing for distribution..."
codesign --force --deep --sign - "${BUILD_APP}"

echo "▶ Generating background image..."
python3 "${PROJECT_ROOT}/Distribution/generate-background.py"

echo "▶ Staging DMG contents..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${BUILD_APP}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

# Always include custom background
mkdir -p "${DMG_DIR}/.background"
cp "${PROJECT_ROOT}/Distribution/dmg-background.png" "${DMG_DIR}/.background/background.png"

echo "▶ Creating read-write DMG..."
hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${DMG_DIR}" \
  -ov -format UDRW \
  "${RW_DMG}" > /dev/null

echo "▶ Mounting and writing Finder layout..."
MOUNT_DIR=$(hdiutil attach "${RW_DMG}" | grep "Volumes" | awk '{print $NF}')

python3 "${PROJECT_ROOT}/Distribution/set-dmg-layout.py" "${MOUNT_DIR}"

sync
sleep 3
hdiutil detach "${MOUNT_DIR}" > /dev/null
sleep 2

echo "▶ Converting to compressed read-only DMG..."
# Retry once — the file handle can take a moment to release after detach
hdiutil convert "${RW_DMG}" -format UDZO -o "${OUT_DMG}" > /dev/null \
  || { sleep 3; hdiutil convert "${RW_DMG}" -format UDZO -o "${OUT_DMG}" > /dev/null; }
rm "${RW_DMG}"

echo "✅ Done: ${OUT_DMG}"
echo ""
echo "Share this DMG with your friends."
echo "They open it, drag FieldWhisperer to Applications, then right-click → Open on first launch."
