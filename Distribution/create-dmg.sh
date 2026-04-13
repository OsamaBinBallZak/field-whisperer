#!/bin/bash
# Creates a drag-to-Applications DMG for FieldWhisperer.
# Run from the project root: bash Distribution/create-dmg.sh
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FieldWhisperer"
DERIVED_DATA="/tmp/FW-build"
BUILD_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
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

# ── 3. Ensure dmgbuild is available ──────────────────────────────────────────
if ! python3 -c "import dmgbuild" 2>/dev/null; then
  echo "▶ Installing dmgbuild (one-time)..."
  python3 -m pip install --quiet --break-system-packages dmgbuild 2>/dev/null \
    || python3 -m pip install --quiet --user dmgbuild
fi

# ── 4. Generate background ────────────────────────────────────────────────────
echo "▶ Generating background image..."
python3 "${PROJECT_ROOT}/Distribution/generate-background.py"

# ── 5. Eject any stale FieldWhisperer volume from a previous run ──────────────
for vol in "/Volumes/${APP_NAME}" "/Volumes/${APP_NAME} 1" "/Volumes/${APP_NAME} 2"; do
  [ -d "$vol" ] && hdiutil detach "$vol" -force 2>/dev/null || true
done
# Clean up any leftover temp UDRW from a previous crash
rm -f /tmp/dmgbuild-*.dmg /tmp/FW-*.dmg

# ── 6. Build DMG ─────────────────────────────────────────────────────────────
echo "▶ Building DMG..."
rm -f "${OUT_DMG}"
python3 -m dmgbuild \
  -s "${PROJECT_ROOT}/Distribution/dmgbuild-settings.py" \
  -D "app=${BUILD_APP}" \
  -D "background=${PROJECT_ROOT}/Distribution/dmg-background.png" \
  "${APP_NAME}" \
  "${OUT_DMG}"

echo "✅ Done: ${OUT_DMG}"
echo ""
echo "Share this DMG with your friends."
echo "They open it, drag FieldWhisperer to Applications, then right-click → Open on first launch."
