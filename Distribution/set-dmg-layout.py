#!/usr/bin/env python3
"""
Write icon positions into a DS_Store in the DMG staging folder.
Called BEFORE hdiutil creates the DMG so there's no mount/detach needed.

Only writes Iloc records (icon positions) — these don't use aliases and
work correctly even when the staging path differs from the final mount path.

Usage: python3 Distribution/set-dmg-layout.py <staging-folder>
"""
import sys, os, subprocess


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

print(f"  .DS_Store written → {ds_path}")
