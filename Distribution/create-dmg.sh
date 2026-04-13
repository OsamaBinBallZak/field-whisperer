#!/bin/bash
# Creates a drag-to-Applications DMG for FieldWhisperer.
# Run from the project root: bash Distribution/create-dmg.sh
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FieldWhisperer"
DERIVED_DATA="/tmp/FW-build"
BUILD_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
DMG_DIR="/tmp/FW-dmg"
OUT_DMG=~/Desktop/"${APP_NAME}.dmg"

# ── 1. Build ──────────────────────────────────────────────────────────────────
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

# ── 2. Sign ───────────────────────────────────────────────────────────────────
echo "▶ Ad-hoc signing for distribution..."
codesign --force --deep --sign - "${BUILD_APP}"

# ── 3. Stage DMG contents ─────────────────────────────────────────────────────
echo "▶ Staging DMG contents..."
rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"
cp -R "${BUILD_APP}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

# ── 4. Write icon positions into staging DS_Store ─────────────────────────────
python3 "${PROJECT_ROOT}/Distribution/set-dmg-layout.py" "${DMG_DIR}"

# ── 5. Create compressed DMG in one shot ──────────────────────────────────────
# Single hdiutil create call — no intermediate UDRW, no attach, no convert.
# Avoids the hdiutil convert EAGAIN issue on macOS 26 Tahoe.
echo "▶ Creating DMG..."
rm -f "${OUT_DMG}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_DIR}" \
  -format UDZO \
  "${OUT_DMG}"

echo "✅ Done: ${OUT_DMG}"
echo ""
echo "Share this DMG with your friends."
echo "They open it, drag FieldWhisperer to Applications, then right-click → Open on first launch."
