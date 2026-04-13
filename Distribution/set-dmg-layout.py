#!/usr/bin/env python3
"""
Write .DS_Store into a mounted DMG for a polished Finder layout:
  - Icon view, 100pt icons, no auto-arrangement
  - Background image from .background/background.png
  - FieldWhisperer.app position  (150, 200)
  - Applications alias position  (450, 200)
  - Window bounds 600×400

Installs ds-store + mac-alias via pip on first run (both pure Python).
Usage: python3 Distribution/set-dmg-layout.py <mount-point>
"""
import sys, os, subprocess, plistlib


# ── dep bootstrap ──────────────────────────────────────────────────────────────
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


for _pkg, _mod in [("ds-store", "ds_store"), ("mac-alias", "mac_alias")]:
    try:
        __import__(_mod)
    except ImportError:
        print(f"  pip install {_pkg}…", flush=True)
        if not _install(_pkg):
            print(f"  Warning: could not install {_pkg}; Finder layout skipped.",
                  file=sys.stderr)
            sys.exit(0)

from ds_store  import DSStore           # noqa: E402
from mac_alias import Alias             # noqa: E402


# ── config ─────────────────────────────────────────────────────────────────────
mount   = sys.argv[1] if len(sys.argv) > 1 else "."
bg_file = os.path.join(mount, ".background", "background.png")
ds_path = os.path.join(mount, ".DS_Store")

if not os.path.exists(bg_file):
    print(f"  Warning: background not found at {bg_file}", file=sys.stderr)

if os.path.exists(ds_path):
    os.remove(ds_path)


# ── pre-encode blob records as binary plists ───────────────────────────────────
# ds_store expects 'blob' entries as raw bytes, not Python dicts.
bwsp_bytes = plistlib.dumps({
    "ShowStatusBar":         False,
    "WindowBounds":          "{{100, 100}, {700, 500}}",
    "ContainerShowSidebar":  False,
    "PreviewPaneVisibility": False,
}, fmt=plistlib.FMT_BINARY)

alias_bytes = Alias.for_file(bg_file).to_bytes()
icvp_bytes  = plistlib.dumps({
    "arrangeBy":            "none",
    "backgroundColorBlue":  1.0,
    "backgroundColorGreen": 1.0,
    "backgroundColorRed":   1.0,
    "backgroundType":       2,          # 2 = picture
    "backgroundImageAlias": alias_bytes,
    "gridOffsetX":          0.0,
    "gridOffsetY":          0.0,
    "gridSpacing":          100.0,
    "iconSize":             100.0,
    "labelOnBottom":        True,
    "scrollPositionX":      0.0,
    "scrollPositionY":      0.0,
    "showIconPreview":      True,
    "showItemInfo":         False,
    "textSize":             12.0,
    "viewOptionsVersion":   1,
}, fmt=plistlib.FMT_BINARY)


# ── write layout ───────────────────────────────────────────────────────────────
with DSStore.open(ds_path, "w+") as d:

    # Icon positions — always write these first (most important)
    d["FieldWhisperer.app"]["Iloc"] = (150, 200)
    d["Applications"]["Iloc"]       = (450, 200)

    # Window state, view style, icon view properties — best-effort
    try:
        d["."]["bwsp"] = bwsp_bytes
        d["."]["vstl"] = b"icnv"   # 4-byte type code for 'icon view'
        d["."]["icvp"] = icvp_bytes
    except Exception as e:
        print(f"  Note: window/background settings skipped ({e})", file=sys.stderr)

print(f"  .DS_Store written → {ds_path}")
