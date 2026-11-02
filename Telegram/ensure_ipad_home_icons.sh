#!/bin/bash
# Records the loose iPad home icons on CFBundleIcons~ipad and checks that every
# alternate icon listed there has a 152 and a 167 PNG in the bundle.
#
# rules_apple merges actool's plist before this runs. That plist already owns
# CFBundleIcons~ipad, so the icon names cannot be added from another fragment.
# Actool keeps the primary artwork in Assets.car; ITMS-90892 still wants the
# 76pt @2x and 83.5pt @2x files outside the catalog, named by this plist.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <unpacked-archive>" >&2
  exit 2
fi

PYTHON="/usr/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
  PYTHON="$(command -v python3)"
fi

exec "$PYTHON" - "$1" << 'PY'
import plistlib
import struct
import sys
from pathlib import Path

PRIMARY = ("TellomiHomeIpad76", "TellomiHomeIpad83")
NEED = ((152, 152), (167, 167))
SKIP = {"PlugIns", "Frameworks", "Watch"}


def fail(message):
    print("ensure_ipad_home_icons: " + message, file=sys.stderr)
    raise SystemExit(1)


def png_size(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        fail("{} is not a PNG".format(path.name))
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def icon_base(filename):
    # Same split as rules_apple alticonstool.iconname_from_filename.
    stem = filename.rsplit(".", 1)[0]
    return stem.split("@", 1)[0]


def find_app(root):
    found = []
    for plist in root.rglob("Info.plist"):
        app = plist.parent
        if app.suffix != ".app":
            continue
        if SKIP.intersection(plist.relative_to(root).parts):
            continue
        found.append(app)
    if len(found) != 1:
        fail("expected one app bundle under {}, found {}".format(root, found))
    return found[0]


def as_list(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return list(value)


def referenced(app, names):
    wanted = set(names)
    return [png for png in app.glob("*.png") if icon_base(png.name) in wanted]


def require_ipad_sizes(label, pngs):
    sizes = {}
    for png in pngs:
        sizes.setdefault(png_size(png), []).append(png.name)
    missing = [size for size in NEED if size not in sizes]
    if missing:
        have = sorted("{}x{}={}".format(w, h, names) for (w, h), names in sizes.items())
        fail("{} is missing {}; found {}".format(label, missing, have))
    bits = []
    for width, height in NEED:
        bits.append("{}x{}={}".format(width, height, ",".join(sorted(sizes[(width, height)]))))
    print("ensure_ipad_home_icons: {}: {}".format(label, "; ".join(bits)))


def main():
    root = Path(sys.argv[1])
    app = find_app(root)
    plist_path = app / "Info.plist"
    raw = plist_path.read_bytes()
    plist = plistlib.loads(raw)
    fmt = plistlib.FMT_BINARY if raw.startswith(b"bplist") else plistlib.FMT_XML

    icons = plist.setdefault("CFBundleIcons~ipad", {})
    primary = icons.setdefault("CFBundlePrimaryIcon", {})
    files = as_list(primary.get("CFBundleIconFiles"))
    for name in PRIMARY:
        if name not in files:
            files.append(name)
    primary["CFBundleIconFiles"] = files
    plistlib.dump(plist, plist_path.open("wb"), fmt=fmt)

    require_ipad_sizes("primary", referenced(app, files))

    alternates = icons.get("CFBundleAlternateIcons") or {}
    if not alternates:
        fail("CFBundleIcons~ipad has no CFBundleAlternateIcons")
    for icon_id, entry in sorted(alternates.items()):
        names = as_list(entry.get("CFBundleIconFiles"))
        if not names:
            fail("alternate icon {} has no CFBundleIconFiles".format(icon_id))
        require_ipad_sizes("alternate " + icon_id, referenced(app, names))


if __name__ == "__main__":
    main()
PY
