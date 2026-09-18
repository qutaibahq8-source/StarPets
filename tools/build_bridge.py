#!/usr/bin/env python3
"""Write bridge/manifest.json and package the Studio sync plugin.

THE BRIDGE

Claude runs on a server. Roblox Studio runs on the developer's computer. There
is no route from one to the other, which is why every change had to be handed
over as a file to install by hand — and why, for a month, that step is where the
work stopped.

But both sides can reach GitHub. Claude pushes; a Studio plugin fetches. The
repository is the bridge.

This writes the manifest the plugin reads (which files exist, where each one
goes, and a version stamp so auto-sync can tell "nothing new" from "fetch
everything"), and packages the plugin itself as a .rbxmx for the Plugins folder.
"""
import hashlib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build"
BRIDGE = ROOT / "bridge"

# Which of the three managed folders each service's subtree becomes.
GROUP_OF = {
    "ServerScriptService": "Server",
    "ReplicatedStorage": "Shared",
    "StarterPlayer": "Client",
}


def manifest_entries():
    """Walk default.project.json so the manifest cannot drift from the place."""
    tree = json.loads((ROOT / "default.project.json").read_text())["tree"]
    entries = []

    def walk(node, service, folders):
        for key, val in node.items():
            if key.startswith("$"):
                continue
            if isinstance(val, dict) and "$path" in val:
                group = GROUP_OF.get(service)
                # Folders BELOW the managed folder, e.g. UI inside Client.
                #
                # Dropping a fixed number of levels is wrong: Server and Shared
                # sit one deep under their service, Client sits two
                # (StarterPlayer > StarterPlayerScripts > Client). Taking
                # folders[1:] put every client script inside a second "Client"
                # folder, so nothing would have loaded. Cut at the managed
                # folder's own name instead.
                below = folders
                if group in folders:
                    below = folders[folders.index(group) + 1:]
                entries.append({
                    "path": val["$path"],
                    "name": key,
                    "group": group,
                    "folders": below,
                })
            elif isinstance(val, dict):
                walk(val, service, folders + [key])

    for service, node in tree.items():
        if service.startswith("$") or not isinstance(node, dict):
            continue
        if service not in GROUP_OF:
            continue
        walk(node, service, [])
    return [e for e in entries if e["group"]]


def esc(s):
    s = "".join(ch for ch in s if ch in "\t\n" or ord(ch) >= 32)
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def build_plugin(name):
    src = (ROOT / ("src/Plugin/%s.server.lua" % name)).read_text()
    body = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
        'version="4">\n'
        '  <Item class="Script" referent="RBX00000001">\n'
        '    <Properties>\n'
        '      <string name="Name">%s</string>\n'
        '      <ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>\n'
        '    </Properties>\n'
        '  </Item>\n'
        '</roblox>\n' % (name, src.replace("]]>", "]] >"))
    )
    dest = OUT / ("%s.rbxmx" % name)
    OUT.mkdir(exist_ok=True)
    dest.write_text(body)
    try:
        ET.parse(dest)
    except ET.ParseError as e:
        print("   x the plugin file is not well-formed XML: %s" % e)
        return None
    if "]]>" in src:
        print("   x the plugin source contains ']]>' and would be altered")
        return None
    return dest


def main():
    entries = manifest_entries()

    # A version stamp the plugin compares against, so auto-sync can tell
    # "nothing new" from "fetch everything". Content-derived rather than a
    # commit sha: the sha is not known until AFTER this file is committed, so
    # using it would always be one commit stale.
    h = hashlib.sha256()
    for e in sorted(entries, key=lambda x: x["path"]):
        h.update(e["path"].encode())
        h.update((ROOT / e["path"]).read_bytes())
    version = h.hexdigest()

    BRIDGE.mkdir(exist_ok=True)
    (BRIDGE / "manifest.json").write_text(json.dumps({
        "version": version,
        "generated_from": "default.project.json",
        "files": entries,
    }, indent=2) + "\n")

    missing = [e["path"] for e in entries if not (ROOT / e["path"]).exists()]
    if missing:
        print("   x manifest references missing file(s): %s" % ", ".join(missing))
        return 1

    # Plugins and the installer live OUTSIDE the place: a plugin is installed
    # into Studio itself, and the installer runs once from the Command Bar.
    # Neither belongs in the manifest, and neither is a file that went missing.
    on_disk = {str(p.relative_to(ROOT)) for p in ROOT.glob("src/**/*.lua")}
    listed = {e["path"] for e in entries}
    outside = {str(p.relative_to(ROOT)) for p in ROOT.glob("src/Plugin/*.lua")}
    outside.add("src/Install/Install.lua")
    unlisted = sorted(on_disk - listed - outside)
    print("bridge/manifest.json: %d files, version %s" % (len(entries), version[:8]))
    for g in sorted({e["group"] for e in entries}):
        n = sum(1 for e in entries if e["group"] == g)
        print("   %-8s %d files" % (g, n))
    if unlisted:
        print("   x %d source file(s) are not in the manifest and would NOT "
              "sync: %s" % (len(unlisted), ", ".join(unlisted)))
        return 1

    for name, what in (("StarPetsSync", "pulls code from GitHub"),
                       ("StarPetsAI", "Claude, docked in Studio")):
        dest = build_plugin(name)
        if dest is None:
            return 1
        print("build/%s: %s (%d KB)"
              % (dest.name, what, dest.stat().st_size // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
