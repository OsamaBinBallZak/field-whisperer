#!/usr/bin/env python3
"""
Write Finder layout into a DS_Store in the DMG staging folder.
Called BEFORE hdiutil creates the DMG so there's no mount/detach needed.

Iloc records (icon positions) work regardless of mount path.
icvp/bwsp records (background colour, window size) are attempted but
skipped gracefully if the ds-store library version doesn't support them.

Usage: python3 Distribution/set-dmg-layout.py <staging-folder>
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


staging = sys.argv[1] if len(sys.argv) > 1 else "."
ds_path = os.path.join(staging, ".DS_Store")

if os.path.exists(ds_path):
    os.remove(ds_path)

with DSStore.open(ds_path, "w+") as d:
    # Icon positions (x, y from top-left of window content area)
    d["FieldWhisperer.app"]["Iloc"] = (150, 200)
    d["Applications"]["Iloc"]       = (450, 200)

    # Window size and background colour — wrapped so an older ds-store
    # library version that can't handle blob records fails gracefully.
    try:
        bwsp = plistlib.dumps(
            {"ShowSidebar": False, "WindowBounds": "{{200, 150}, {600, 420}}"},
            fmt=plistlib.FMT_BINARY,
        )
        icvp = plistlib.dumps(
            {
                "viewOptionsVersion": 1,
                "backgroundType": 1,          # 1 = solid colour
                "backgroundColorRed":   0.918, # #EAE6FF lavender
                "backgroundColorGreen": 0.902,
                "backgroundColorBlue":  1.0,
                "iconSize": 80.0,
                "gridSpacing": 100.0,
                "arrangeBy": "none",
                "showItemInfo": False,
                "labelOnBottom": True,
                "showIconPreview": True,
                "flowedIcon": False,
                "gridOffsetX": 0.0,
                "gridOffsetY": 0.0,
            },
            fmt=plistlib.FMT_BINARY,
        )
        d["."]["bwsp"] = bwsp
        d["."]["icvp"] = icvp
        print("  Background colour and window size set.")
    except Exception as e:
        print(f"  Note: background colour skipped ({e})", file=sys.stderr)

print(f"  .DS_Store written → {ds_path}")
