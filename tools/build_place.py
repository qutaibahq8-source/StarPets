#!/usr/bin/env python3
"""Pack the whole project into one .rbxlx you can open in Studio.

Rojo is the proper way to sync this project, but a single file needs no
install, no plugin and no command line: File -> Open from File, press Play.
That matters when the person who has to look at the result is not the person
who wrote it.

Reads default.project.json so the file layout has exactly one source of truth.
A script in src/ that nobody added to the manifest will NOT appear in the
place, which is a real way to ship a game missing a module, so this counts both
and says so.
"""
import html
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"

# Which Roblox class each source file becomes. A file named *.server.lua is a
# Script (runs on the server); *.client.lua is a LocalScript; anything else is
# a ModuleScript, which only runs when something requires it.
def class_for(path: str) -> str:
    if path.endswith(".server.lua"):
        return "Script"
    if path.endswith(".client.lua"):
        return "LocalScript"
    return "ModuleScript"


def esc(s: str) -> str:
    # Roblox XML is strict about control characters; keep the printable ones
    # plus tab/newline and drop the rest rather than writing a file Studio
    # refuses to open.
    s = "".join(ch for ch in s if ch in "\t\n" or ord(ch) >= 32)
    return html.escape(s, quote=False)


class Builder:
    def __init__(self):
        self.out = []
        self.ref = 0
        self.scripts = 0
        self.items = 0

    def nref(self):
        self.ref += 1
        return "RBX%08X" % self.ref

    def emit_script(self, name, src_path, indent):
        p = ROOT / src_path
        if not p.exists():
            raise SystemExit("manifest points at a file that does not exist: %s"
                             % src_path)
        cls = class_for(src_path)
        pad = "  " * indent
        self.scripts += 1
        self.items += 1
        self.out.append(
            '%s<Item class="%s" referent="%s">\n'
            '%s  <Properties>\n'
            '%s    <string name="Name">%s</string>\n'
            '%s    <ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>\n'
            '%s  </Properties>\n'
            '%s</Item>\n'
            % (pad, cls, self.nref(), pad, pad, esc(name), pad,
               p.read_text().replace("]]>", "]] >"), pad, pad))

    def emit_folder(self, name, cls, children, indent):
        pad = "  " * indent
        self.items += 1
        self.out.append(
            '%s<Item class="%s" referent="%s">\n'
            '%s  <Properties>\n'
            '%s    <string name="Name">%s</string>\n'
            '%s  </Properties>\n'
            % (pad, cls, self.nref(), pad, pad, esc(name), pad))
        self.walk(children, indent + 1)
        self.out.append("%s</Item>\n" % pad)

    def walk(self, node, indent):
        for key, val in node.items():
            if key.startswith("$"):
                continue
            if isinstance(val, dict) and "$path" in val:
                self.emit_script(key, val["$path"], indent)
            elif isinstance(val, dict):
                self.emit_folder(key, val.get("$className", "Folder"), val, indent)


def main():
    manifest = json.loads((ROOT / "default.project.json").read_text())
    tree = manifest["tree"]

    b = Builder()
    b.out.append('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
                 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                 'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
                 'version="4">\n')
    for svc, node in tree.items():
        if svc.startswith("$") or not isinstance(node, dict):
            continue
        cls = node.get("$className", svc)
        pad = "  "
        b.items += 1
        b.out.append(
            '%s<Item class="%s" referent="%s">\n'
            '%s  <Properties>\n'
            '%s    <string name="Name">%s</string>\n'
            '%s  </Properties>\n'
            % (pad, cls, b.nref(), pad, pad, svc, pad))
        b.walk(node, 2)
        b.out.append("%s</Item>\n" % pad)
    b.out.append("</roblox>\n")

    OUT.mkdir(exist_ok=True)
    dest = OUT / "StarPets.rbxlx"
    dest.write_text("".join(b.out))

    # A script in src/ that the manifest never mentions does not ship. That is
    # a genuine way to send somebody a game with a module missing.
    on_disk = {p for p in ROOT.glob("src/**/*.lua")}
    in_manifest = set()

    def collect(node):
        for k, v in node.items():
            if k.startswith("$"):
                continue
            if isinstance(v, dict) and "$path" in v:
                in_manifest.add(ROOT / v["$path"])
            elif isinstance(v, dict):
                collect(v)
    collect(tree)
    missing = sorted(on_disk - in_manifest)

    # Parse what was just written. A place file Studio refuses to open is
    # worse than no file at all: it looks like the work is there and is not.
    import xml.etree.ElementTree as ET
    try:
        ET.parse(dest)
    except ET.ParseError as e:
        print("   x the place file is not well-formed XML: %s" % e)
        print("     Studio would refuse to open it.")
        return 1

    kb = dest.stat().st_size // 1024
    print("wrote %s (%d KB, %d items, %d scripts)"
          % (dest.relative_to(ROOT), kb, b.items, b.scripts))
    if missing:
        print("\n   x %d source file(s) are NOT in default.project.json, so they "
              "are missing from the place:" % len(missing))
        for m in missing:
            print("       " + str(m.relative_to(ROOT)))
        return 1
    print("place carries all %d source files" % len(on_disk))
    return 0


if __name__ == "__main__":
    sys.exit(main())
