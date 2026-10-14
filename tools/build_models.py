#!/usr/bin/env python3
"""Export the code as drag-in model files, not a whole place.

WHY THIS EXISTS

The one-file .rbxlx is only useful to somebody who has no place of their own.
Opening it REPLACES whatever you had open, so for a developer with their own
Studio place — their own map edits, their own assets, their own settings —
opening it throws their work away. Handing that to somebody and saying "open
this" asks them to choose between the update and everything they have built.

A .rbxmx is the opposite: you drag it into a place that already exists and it
adds its contents to the one folder it belongs in. Nothing else in the place is
touched.

So this writes one model per service, each containing that service's scripts:

  StarPets_ServerScriptService.rbxmx  ->  right-click ServerScriptService, Insert from File
  StarPets_ReplicatedStorage.rbxmx    ->  right-click ReplicatedStorage,   Insert from File
  StarPets_StarterPlayer.rbxmx        ->  right-click StarterPlayerScripts, Insert from File

The existing "Server" / "Shared" / "Client" folder should be DELETED first,
because Insert from File adds rather than replaces — two copies of GameServer
both run, both build a map, and the result looks like nothing changed. That
failure has a way of being blamed on the update rather than on the install, so
it is worth being loud about.
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"

# Which top-level service each model covers, and what the folder inside it is
# called. Read from default.project.json so this cannot drift from the place.
SERVICES = {
    "ServerScriptService": "StarPets_ServerScriptService.rbxmx",
    "ReplicatedStorage": "StarPets_ReplicatedStorage.rbxmx",
    "StarterPlayer": "StarPets_StarterPlayer.rbxmx",
}


def class_for(path: str) -> str:
    if path.endswith(".server.lua"):
        return "Script"
    if path.endswith(".client.lua"):
        return "LocalScript"
    return "ModuleScript"


def esc(s: str) -> str:
    s = "".join(ch for ch in s if ch in "\t\n" or ord(ch) >= 32)
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


class Model:
    def __init__(self):
        self.out = []
        self.ref = 0
        self.scripts = 0

    def nref(self):
        self.ref += 1
        return "RBX%08X" % self.ref

    def script(self, name, src_path, indent):
        p = ROOT / src_path
        if not p.exists():
            raise SystemExit("manifest points at a missing file: %s" % src_path)
        pad = "  " * indent
        self.scripts += 1
        self.out.append(
            '%s<Item class="%s" referent="%s">\n'
            '%s  <Properties>\n'
            '%s    <string name="Name">%s</string>\n'
            '%s    <ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>\n'
            '%s  </Properties>\n'
            '%s</Item>\n'
            % (pad, class_for(src_path), self.nref(), pad, pad, esc(name), pad,
               p.read_text().replace("]]>", "]] >"), pad, pad))

    def folder(self, name, cls, children, indent):
        pad = "  " * indent
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
                self.script(key, val["$path"], indent)
            elif isinstance(val, dict):
                self.folder(key, val.get("$className", "Folder"), val, indent)


def main():
    tree = json.loads((ROOT / "default.project.json").read_text())["tree"]
    OUT.mkdir(exist_ok=True)
    total = 0
    rc = 0

    for service, filename in SERVICES.items():
        node = tree.get(service)
        if not isinstance(node, dict):
            continue
        m = Model()
        m.out.append('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
                     'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                     'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
                     'version="4">\n')
        # StarterPlayer nests the scripts one level deeper; export the inner
        # folders so the model drops straight into StarterPlayerScripts.
        source = node
        if service == "StarterPlayer":
            source = node.get("StarterPlayerScripts", node)
        m.walk(source, 1)
        m.out.append("</roblox>\n")

        dest = OUT / filename
        dest.write_text("".join(m.out))

        # Parse it back. A model Studio refuses to open looks exactly like a
        # model that was never sent.
        try:
            ET.parse(dest)
        except ET.ParseError as e:
            print("   x %s is not well-formed XML: %s" % (filename, e))
            rc = 1
            continue
        total += m.scripts
        print("  %-38s %2d scripts, %3d KB"
              % (filename, m.scripts, dest.stat().st_size // 1024))

    src_count = len(list(ROOT.glob("src/**/*.lua")))
    print("exported %d of %d source files as drag-in models" % (total, src_count))
    if total != src_count:
        print("   x %d file(s) did not make it into any model" % (src_count - total))
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
