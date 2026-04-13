#!/usr/bin/env python3
"""
Write Finder layout into the DS_Store of the mounted DMG volume.
Called after hdiutil attach so the correct /Volumes path is used.

  - Iloc  : icon positions (always works)
  - bwsp  : window size/position (attempted, skipped gracefully on failure)
  - icvp  : icon size and view options (attempted, skipped gracefully on failure)

Usage: python3 Distribution/set-dmg-layout.py <mount-point>
  e.g. python3 Distribution/set-dmg-layout.py /Volumes/FieldWhisperer
"""
import sys, os, subprocess, plistlib


def _install(pkg):
    for flags in [["--break-system-packages"], ["--user"], []]:
        try:
            subprocess.check_call(
                [sys.executable, "-m", "pip", "install", "--quiet", pkg, *flags],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except subprocess.CalledProcessError:
            continue
    return False


try:
    from ds_store import DSStore
except ImportError:
    print("  pip install ds-store…", flush=True)
    if not _install("ds-store"):
        print("  Warning: icon positioning skipped (ds-store unavailable)",
              file=sys.stderr)
        sys.exit(0)
    from ds_store import DSStore


mount = sys.argv[1] if len(sys.argv) > 1 else "."
ds_path = os.path.join(mount, ".DS_Store")

if os.path.exists(ds_path):
    os.remove(ds_path)

with DSStore.open(ds_path, "w+") as d:

    # ── Icon positions ────────────────────────────────────────────────────────
    # Tuned for a 600×360 window with 96 px icons.
    d["FieldWhisperer.app"]["Iloc"] = (150, 175)
    d["Applications"]["Iloc"]       = (450, 175)

    # ── Window size ───────────────────────────────────────────────────────────
    # bwsp WindowBounds: "{{left, top}, {right, bottom}}" on screen.
    # 600 wide × 360 tall, centred-ish at (100, 100).
    try:
        d["."]["bwsp"] = plistlib.dumps(
            {"ShowSidebar": False, "WindowBounds": "{{100, 100}, {700, 460}}"},
            fmt=plistlib.FMT_BINARY,
        )
        print("  Window size set (600×360).")
    except Exception as e:
        print(f"  Note: window size skipped ({e})", file=sys.stderr)

    # ── Icon size and view options ────────────────────────────────────────────
    try:
        d["."]["icvp"] = plistlib.dumps(
            {
                "viewOptionsVersion": 1,
                "backgroundType":     0,      # 0 = default white
                "iconSize":           96.0,   # px (default is 64)
                "gridSpacing":        120.0,
                "arrangeBy":          "none",
                "showItemInfo":       False,
                "labelOnBottom":      True,
                "showIconPreview":    True,
                "flowedIcon":         False,
                "gridOffsetX":        0.0,
                "gridOffsetY":        0.0,
            },
            fmt=plistlib.FMT_BINARY,
        )
        print("  Icon size set (96 px).")
    except Exception as e:
        print(f"  Note: icon size skipped ({e})", file=sys.stderr)

print(f"  .DS_Store written → {ds_path}")
