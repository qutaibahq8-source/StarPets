import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lupa
from check_syntax import luau_to_lua
ROOT = pathlib.Path(__file__).resolve().parent.parent

lua = lupa.LuaRuntime(unpack_returned_tuples=False); G = lua.globals()
mock = lua.execute((ROOT/"tools/roblox_mock.lua").read_text())
for k in ("Vector3","CFrame","Color3","Enum","Instance","game","workspace","Random","UDim","UDim2","Vector2"):
    G[k] = mock[k]
lua.execute("task={spawn=function() end,wait=function() return .03 end,delay=function() end}")
lua.execute('local rs2 = game:GetService("RunService"); rawget(rs2,"_p").IsRunning = function() return false end')
lua.execute("WARN={} ; warn=function(m) WARN[#WARN+1]=tostring(m) end")
lua.execute("OUT={} ; print=function(...) local p={} for i=1,select('#',...) do p[i]=tostring((select(i,...))) end OUT[#OUT+1]=table.concat(p,' ') end")

# A place that ALREADY has an old install — the case that breaks by hand.
ws = mock["workspace"]; gm = mock["game"]
sss = gm["GetService"](gm,"ServerScriptService")
rs  = gm["GetService"](gm,"ReplicatedStorage")
sp  = gm["GetService"](gm,"StarterPlayer")
sps = mock["newInst"]("StarterPlayerScripts"); sps.Name="StarterPlayerScripts"; sps.Parent=sp
for parent, fname, inner in ((sss,"Server","GameServer"), (rs,"Shared","GameConfig"), (sps,"Client","GameClient")):
    old = mock["newInst"]("Folder"); old.Name=fname; old.Parent=parent
    s = mock["newInst"]("Script" if inner=="GameServer" else "ModuleScript")
    s.Name=inner; s.Parent=old

# The model, as inserted into Workspace.
bundle = mock["newInst"]("Folder"); bundle.Name="StarPetsInstall"; bundle.Parent=ws
for fname, inner, cls in (("Server","GameServer","Script"),("Shared","GameConfig","ModuleScript"),("Client","GameClient","LocalScript")):
    f = mock["newInst"]("Folder"); f.Name=fname; f.Parent=bundle
    s = mock["newInst"](cls); s.Name=inner; s.Parent=f
inst = mock["newInst"]("ModuleScript"); inst.Name="Install"; inst.Parent=bundle

fn = lua.eval("function(s,n) return assert(load(s,n)) end")(
        luau_to_lua((ROOT/"src/Install/Install.lua").read_text()), "@Install")()
ok = fn()

print("installer returned:", ok)
for i in range(1, 40):
    v = G.OUT[i]
    if v is None: break
    print(v)
for i in range(1, 10):
    v = G.WARN[i]
    if v is None: break
    print("WARN:", v)

def count(svc, fname):
    n = 0
    for x in svc["GetChildren"](svc).values():
        if str(x._p.Name) == fname: n += 1
    return n
print("--- after install ---")
print("  ServerScriptService has %d 'Server' folder(s)" % count(sss,"Server"))
print("  ReplicatedStorage   has %d 'Shared' folder(s)" % count(rs,"Shared"))
print("  StarterPlayerScripts has %d 'Client' folder(s)" % count(sps,"Client"))
print("  Workspace leftover StarPetsInstall:", ws["FindFirstChild"](ws,"StarPetsInstall") is not None)


# --- THE SHIPPED FILE ITSELF -------------------------------------------
# The logic above runs against the source tree. The thing that actually
# reaches a person is the .rbxmx, and "it wrote a file" is not the same as
# "Roblox will open it and the code inside is what I wrote".
import xml.etree.ElementTree as ET, json
fails = []
model = ROOT / "build/StarPets_Install.rbxmx"
if not model.exists():
    print("  (no build/StarPets_Install.rbxmx yet — run tools/build_installer.py)")
else:
    try:
        xroot = ET.parse(model).getroot()
    except ET.ParseError as e:
        fails.append("the shipped model is not well-formed XML (%s) — Studio "
                     "would refuse to open it" % e)
        xroot = None
    if xroot is not None:
        VALID = {"Folder", "Script", "LocalScript", "ModuleScript", "Model"}
        classes = {i.get("class") for i in xroot.iter("Item")}
        unknown = classes - VALID
        if unknown:
            fails.append("the model uses class name(s) Roblox does not know: %s"
                         % ", ".join(sorted(unknown)))
        else:
            print("  ok  every class in the model is a real Roblox class")

        # Source must round-trip EXACTLY. The writer escapes the CDATA
        # terminator "]]>" as "]] >", which would silently CHANGE the Lua of
        # any file containing it — code that is subtly not what was tested.
        srcs = {}
        for i in xroot.iter("Item"):
            nm = i.find("Properties/string[@name='Name']")
            ps = i.find("Properties/ProtectedString[@name='Source']")
            if nm is not None and ps is not None:
                srcs[nm.text] = ps.text or ""
        name_for = {"Install": "src/Install/Install.lua"}
        def _walk(n):
            for k, v in n.items():
                if k.startswith("$"):
                    continue
                if isinstance(v, dict) and "$path" in v:
                    name_for[k] = v["$path"]
                elif isinstance(v, dict):
                    _walk(v)
        _walk(json.loads((ROOT / "default.project.json").read_text())["tree"])
        differ, checked = [], 0
        for nm, rel in name_for.items():
            if nm not in srcs:
                continue
            checked += 1
            if srcs[nm] != (ROOT / rel).read_text():
                differ.append(nm)
        if differ:
            fails.append("%d file(s) in the shipped model do not match the "
                         "source on disk: %s" % (len(differ), ", ".join(differ[:5])))
        else:
            print("  ok  all %d scripts in the model match the source exactly"
                  % checked)

if not ok:
    fails.append("the installer reported failure")
for svc, fname, label in ((sss, "Server", "ServerScriptService"),
                          (rs, "Shared", "ReplicatedStorage"),
                          (sps, "Client", "StarterPlayerScripts")):
    n = count(svc, fname)
    if n != 1:
        fails.append("%s ended with %d '%s' folder(s), expected exactly 1 — "
                     "two copies both run and the map builds twice"
                     % (label, n, fname))
if ws["FindFirstChild"](ws, "StarPetsInstall") is not None:
    fails.append("the installer left itself in Workspace; running the line "
                 "again would report every folder missing")
if fails:
    print("\ninstall: %d problems" % len(fails))
    for f in fails:
        print("   x " + f)
    sys.exit(1)
print("\ninstall: replaces an older copy cleanly and leaves nothing behind")
sys.exit(0)
