#!/usr/bin/env python3
"""One model, one Command Bar line, installed.

Installing by hand is six steps across three services, and one of them is a
DELETE that is easy to skip. Skipping it is not harmless: Insert from File ADDS
rather than replaces, so an old Server folder beside a new one means two
GameServer scripts, both running, both building a map on top of each other. The
result looks exactly like the update did nothing.

This packs all three service folders plus the installer module into a single
model that goes into Workspace. The Command Bar line then moves each folder to
where it belongs, deleting any older copy on the way, and prints what it did.

    right-click Workspace -> Insert from File -> StarPets_Install.rbxmx
    Command Bar:  require(workspace.StarPetsInstall.Install)()
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"

COMMAND = "require(workspace.StarPetsInstall.Install)()"


def class_for(path: str) -> str:
    if path.endswith(".server.lua"):
        return "Script"
    if path.endswith(".client.lua"):
        return "LocalScript"
    return "ModuleScript"


def esc(s: str) -> str:
    s = "".join(ch for ch in s if ch in "\t\n" or ord(ch) >= 32)
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Builder:
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
            raise SystemExit("missing source file: %s" % src_path)
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
    b = Builder()
    b.out.append('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
                 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                 'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
                 'version="4">\n')
    # One wrapper folder, holding Server / Shared / Client side by side plus the
    # installer module that knows where each of them belongs.
    b.out.append('  <Item class="Folder" referent="%s">\n'
                 '    <Properties>\n'
                 '      <string name="Name">StarPetsInstall</string>\n'
                 '    </Properties>\n' % b.nref())

    sources = {
        "Server": tree.get("ServerScriptService", {}).get("Server"),
        "Shared": tree.get("ReplicatedStorage", {}).get("Shared"),
        "Client": (tree.get("StarterPlayer", {})
                   .get("StarterPlayerScripts", {})
                   .get("Client")),
    }
    for name, node in sources.items():
        if not isinstance(node, dict):
            raise SystemExit("default.project.json has no %s folder" % name)
        b.folder(name, node.get("$className", "Folder"), node, 2)

    b.script("Install", "src/Install/Install.lua", 2)
    b.out.append("  </Item>\n</roblox>\n")

    OUT.mkdir(exist_ok=True)
    dest = OUT / "StarPets_Install.rbxmx"
    dest.write_text("".join(b.out))

    try:
        root = ET.parse(dest).getroot()
    except ET.ParseError as e:
        print("   x not well-formed XML: %s" % e)
        return 1

    # Verify the shape, because "it wrote a file" is not the same as "the file
    # contains what the installer will look for".
    wrapper = root.find("Item")
    top = [i.find("Properties/string[@name='Name']").text
           for i in wrapper.findall("Item")]
    want = ["Server", "Shared", "Client", "Install"]
    missing = [w for w in want if w not in top]
    if missing:
        print("   x the model is missing: %s" % ", ".join(missing))
        return 1

    src_count = len(list(ROOT.glob("src/**/*.lua"))) - 1   # minus Install.lua
    shipped = b.scripts - 1
    print("wrote %s (%d KB)" % (dest.relative_to(ROOT), dest.stat().st_size // 1024))
    print("  contains: %s" % ", ".join(top))
    print("  %d game scripts + the installer" % shipped)
    if shipped != src_count:
        print("   x %d source file(s) did not make it in" % (src_count - shipped))
        return 1
    print("\ninstall:  Workspace -> Insert from File -> StarPets_Install.rbxmx")
    print("          Command Bar:  %s" % COMMAND)
    return 0


if __name__ == "__main__":
    sys.exit(main())
