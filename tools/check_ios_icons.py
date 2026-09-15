"""Verify alternate icons in the built app, not just Xcode source settings."""
import plistlib
import sys
import zipfile
from pathlib import Path

def check(plist):
    expected = {"AppIcon-" + c for c in
                ("blue", "teal", "purple", "pink", "red", "orange", "yellow")}
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icons = plist.get(key, {})
        alternates = icons.get("CFBundleAlternateIcons", {})
        missing = expected - alternates.keys()
        if missing:
            raise ValueError(f"{key}: missing alternate icons: {sorted(missing)}")
        for name in expected:
            entry = alternates[name]
            # Asset-catalog icons may contain only CFBundleIconName. Xcode\n            # need not export loose PNGs / CFBundleIconFiles for these entries.\n            if entry.get("CFBundleIconName") != name:
                raise ValueError(f"{key}: invalid icon entry {name}: {entry}")
    print("All seven alternate icons are registered for iPhone and iPad.")

def main():
    path = Path(sys.argv[1])
    if path.suffix == ".ipa":
        with zipfile.ZipFile(path) as archive:
            names = [n for n in archive.namelist()
                     if n.startswith("Payload/") and n.count("/") == 2
                     and n.endswith(".app/Info.plist")]
            if len(names) != 1:
                raise ValueError("Expected one main app Info.plist")
            check(plistlib.loads(archive.read(names[0])))
    else:
        check(plistlib.loads(path.read_bytes()))

if __name__ == "__main__":
    main()
