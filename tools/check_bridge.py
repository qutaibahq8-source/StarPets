#!/usr/bin/env python3
"""Run the sync plugin against a simulated Studio, with a simulated GitHub.

The plugin is the only thing standing between a push and the game, so a bug in
it means the same failure as before: a change that never arrives. And it cannot
be tested by reading it — the interesting parts are what it does when a fetch
fails half way, and whether the folders land in the right place.

Checked here:
  1. FILES LAND RIGHT     Server, Shared and Client in their services, with
                          the UI subfolder intact and the right class per file
  2. REPLACES, NOT ADDS   an existing install is swapped, never duplicated
  3. ALL OR NOTHING       a fetch that fails part way leaves the place untouched
  4. NOT DURING PLAY      Studio discards Play-mode changes, so a sync then
                          would appear to work and vanish on Stop
  5. NOTHING ELSE MOVES   the map and anything hand-built are never touched
"""
import json
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402


def studio(fail_on=None, playing=False):
    """A Studio-shaped world with a fake GitHub behind HttpService."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Instance", "game", "workspace", "typeof", "Color3", "Vector3", "Enum",
              "UDim", "UDim2", "TweenInfo", "DockWidgetPluginGuiInfo"):
        G[k] = mock[k]
    lua.execute("""
        OUT, WARN = {}, {}
        print = function(...) local p={} for i=1,select('#',...) do p[i]=tostring((select(i,...))) end
            OUT[#OUT+1]=table.concat(p,' ') end
        warn = function(...) local p={} for i=1,select('#',...) do p[i]=tostring((select(i,...))) end
            WARN[#WARN+1]=table.concat(p,' ') end
        task = { spawn=function() end, wait=function() return 0 end,
                 delay=function() end, defer=function() end }
        -- A Roblox plugin runs with script-injection permission, so loadstring
        -- IS available to it. Lua 5.5 dropped the name, so it is restored here
        -- — without it the plugin's primary path is unreachable and the test
        -- would only ever exercise the fallback.
        loadstring = function(src, name) return load(src, name) end
    """)

    gm = mock["game"]
    rsv = gm["GetService"](gm, "RunService")
    lua.eval("function(rs, v) rawget(rs,'_p').IsRunning = function() return v end end")(
        rsv, playing)
    sps = mock["newInst"]("StarterPlayerScripts"); sps.Name = "StarterPlayerScripts"
    sps.Parent = gm["GetService"](gm, "StarterPlayer")

    # The fake GitHub: serve the real manifest and the real files off disk.
    manifest = (ROOT / "bridge/manifest.json").read_text()
    files = {}
    for e in json.loads(manifest)["files"]:
        files[e["path"]] = (ROOT / e["path"]).read_text()
    G["FAKE_MANIFEST"] = manifest
    G["FAKE_COMMANDS"] = (ROOT / "bridge/commands.json").read_text()
    G["FAKE_FILES"] = lua.table_from(files)
    G["FAIL_ON"] = fail_on or ""
    lua.execute("""
        FETCHES = 0
        -- HttpService in the mock is a plain table, not an Instance, so its
        -- methods are assigned directly rather than through the _p property
        -- bag that real instances use.
        local hs = game:GetService("HttpService")
        hs.GetAsync = function(_, url)
            FETCHES = FETCHES + 1
            local clean = url:gsub("%?.*$", "")
            local path = clean:match("refs/heads/[^/]+/[^/]+/(.+)$")
                       or clean:match("refs/heads/.-/(.+)$")
            if clean:find("manifest.json") then return FAKE_MANIFEST end
            if clean:find("commands.json") then return FAKE_COMMANDS end
            for p, src in pairs(FAKE_FILES) do
                if clean:sub(-#p) == p then
                    if FAIL_ON ~= "" and p:find(FAIL_ON, 1, true) then
                        error("HTTP 404 (simulated)", 0)
                    end
                    return src
                end
            end
            error("unknown url " .. clean, 0)
        end
        hs.JSONDecode = function(_, s)
            if s == FAKE_COMMANDS then return DECODED_CMDS end
            return DECODED
        end
    """)
    # Decode the manifest in Python and hand it over; the mock has no JSON.
    G["DECODED"] = lua.table_from(json.loads(manifest), recursive=True)
    G["DECODED_CMDS"] = lua.table_from(
        json.loads((ROOT / "bridge/commands.json").read_text()), recursive=True)

    # A minimal `plugin` object.
    lua.execute("""
        SETTINGS = {}
        local function button(n)
            return { Click = { Connect = function() end },
                     SetActive = function() end }
        end
        plugin = {
            CreateToolbar = function() return { CreateButton = function() return button() end } end,
            GetSetting = function(_, k) return SETTINGS[k] end,
            SetSetting = function(_, k, v) SETTINGS[k] = v end,
            CreateDockWidgetPluginGui = function()
                local w = Instance.new("DockWidgetPluginGui")
                w.Enabled = false
                return w
            end,
        }
    """)
    # The fallback path requires a freshly-built ModuleScript, which needs the
    # Roblox-shaped require.
    G["require"] = mock["robloxRequire"]
    return lua, mock, G


def load_plugin(lua):
    src = luau_to_lua((ROOT / "src/Plugin/StarPetsSync.server.lua").read_text())
    lua.eval("function(s,n) return assert(load(s,n)) end")(src, "@StarPetsSync")()


def find(mock, service, name):
    gm = mock["game"]
    svc = gm["GetService"](gm, service)
    if service == "StarterPlayer":
        svc = svc["FindFirstChild"](svc, "StarterPlayerScripts")
    return svc["FindFirstChild"](svc, name) if svc is not None else None


def count_scripts(folder):
    if folder is None:
        return 0
    n = 0
    for d in folder["GetDescendants"](folder).values():
        if str(d._p.ClassName) in ("Script", "LocalScript", "ModuleScript"):
            n += 1
    return n


def main():
    fails = []

    # ---- 1. FILES LAND IN THE RIGHT PLACE ---------------------------------
    # sync() is a local inside the plugin, reachable only from a toolbar button
    # that cannot be clicked from here. Rather than fake the click, the one
    # declaration is rewritten to a global so the REAL function runs — the body
    # under test is untouched.
    src = luau_to_lua((ROOT / "src/Plugin/StarPetsSync.server.lua").read_text())
    src = src.replace("local function sync(quiet)", "function SYNC(quiet)")
    src = src.replace("sync(false)", "SYNC(false)").replace("sync(true)", "SYNC(true)")
    src = src.replace("pcall(sync, true)", "pcall(SYNC, true)")
    lua2, mock2, G2 = studio()
    lua2.eval("function(s,n) return assert(load(s,n)) end")(src, "@StarPetsSync")()
    ok = lua2.globals().SYNC(False)

    server = find(mock2, "ServerScriptService", "Server")
    shared = find(mock2, "ReplicatedStorage", "Shared")
    client = find(mock2, "StarterPlayer", "Client")
    print("synced: Server=%d  Shared=%d  Client=%d scripts"
          % (count_scripts(server), count_scripts(shared), count_scripts(client)))
    total = count_scripts(server) + count_scripts(shared) + count_scripts(client)
    want = len(json.loads((ROOT / "bridge/manifest.json").read_text())["files"])
    if total != want:
        fails.append("%d of %d files arrived" % (total, want))
    else:
        print("  ok  all %d files arrived" % want)

    ui = client["FindFirstChild"](client, "UI") if client is not None else None
    if ui is None or count_scripts(ui) < 15:
        fails.append("the UI subfolder is missing or nearly empty — the client "
                     "requires its panels from there and would error on join")
    else:
        print("  ok  Client/UI has %d panels" % count_scripts(ui))

    gs = server["FindFirstChild"](server, "GameServer") if server is not None else None
    if gs is None or str(gs._p.ClassName) != "Script":
        fails.append("GameServer is not a Script — it would never run")
    else:
        print("  ok  GameServer is a Script (runs on its own)")
    gcl = client["FindFirstChild"](client, "GameClient") if client is not None else None
    if gcl is None or str(gcl._p.ClassName) != "LocalScript":
        fails.append("GameClient is not a LocalScript — the player gets no UI")
    else:
        print("  ok  GameClient is a LocalScript")

    # ---- 2. A SECOND SYNC REPLACES, NEVER DUPLICATES ----------------------
    lua2.globals().SYNC(False)
    sss = mock2["game"]["GetService"](mock2["game"], "ServerScriptService")
    dupes = sum(1 for c in sss["GetChildren"](sss).values()
                if str(c._p.Name) == "Server")
    if dupes != 1:
        fails.append("after a second sync there are %d Server folders — two "
                     "copies of the game would run at once" % dupes)
    else:
        print("  ok  syncing twice replaces, it does not duplicate")

    # ---- 3. A PARTIAL FETCH MUST CHANGE NOTHING ---------------------------
    lua3, mock3, G3 = studio(fail_on="PetService.lua")
    lua3.eval("function(s,n) return assert(load(s,n)) end")(src, "@StarPetsSync")()
    # Seed an existing good install so we can prove it survives.
    sss3 = mock3["game"]["GetService"](mock3["game"], "ServerScriptService")
    old = mock3["newInst"]("Folder"); old.Name = "Server"; old.Parent = sss3
    keep = mock3["newInst"]("Script"); keep.Name = "PreviousInstall"; keep.Parent = old
    lua3.globals().SYNC(False)
    still = find(mock3, "ServerScriptService", "Server")
    survived = still is not None and still["FindFirstChild"](still, "PreviousInstall")
    if not survived:
        fails.append("a sync that failed part way through still destroyed the "
                     "existing install — the place is left with half a game")
    else:
        print("  ok  a failed fetch aborts and leaves the place untouched")

    # ---- 4. NOT DURING PLAY -----------------------------------------------
    lua4, mock4, G4 = studio(playing=True)
    lua4.eval("function(s,n) return assert(load(s,n)) end")(src, "@StarPetsSync")()
    lua4.globals().SYNC(False)
    if find(mock4, "ServerScriptService", "Server") is not None:
        fails.append("it synced during PLAY mode — Studio discards that on "
                     "Stop, so it would appear to work and then vanish")
    else:
        warned = any("PLAY" in str(G4.WARN[i] or "") for i in range(1, 6))
        print("  ok  refuses to sync during Play%s"
              % ("" if warned else " (but says nothing — it should)"))

    # ---- 5. NOTHING ELSE IS TOUCHED ---------------------------------------
    ws = mock2["workspace"]
    mine = mock2["newInst"]("Part"); mine.Name = "MyHandBuiltThing"; mine.Parent = ws
    lua2.globals().SYNC(False)
    if ws["FindFirstChild"](ws, "MyHandBuiltThing") is None:
        fails.append("syncing destroyed something in Workspace — it must only "
                     "ever touch the three code folders")
    else:
        print("  ok  Workspace and anything hand-built are left alone")

    # ---- 6. COMMANDS ARE OPT-IN AND RUN EXACTLY ONCE ----------------------
    # This channel lets a remote author run Luau in someone's Studio. It must
    # be off until switched on, and a command must never run twice — a rebuild
    # applied twice is two maps on top of each other.
    src_cmd = src.replace("local function runCommands()", "function RUNCMDS()")
    src_cmd = src_cmd.replace("pcall(runCommands)", "pcall(RUNCMDS)")
    lua5, mock5, G5 = studio()
    lua5.eval("function(s,n) return assert(load(s,n)) end")(src_cmd, "@StarPetsSync")()

    before = [str(G5.OUT[i]) for i in range(1, 40) if G5.OUT[i] is not None]
    if any("Claude is connected" in x for x in before):
        fails.append("a command ran WITHOUT the permission button being on")
    else:
        print("  ok  no command runs until permission is switched on")

    lua5.globals().RUNCMDS()
    after = [str(G5.OUT[i]) for i in range(1, 80) if G5.OUT[i] is not None]
    ran = [x for x in after if "Claude is connected" in x]
    if not ran:
        fails.append("the command did not execute at all — the Luau channel "
                     "does not work, so nothing can be driven from outside")
    else:
        print("  ok  a pushed command actually executes in the place")

    lua5.globals().RUNCMDS()
    again = [x for x in
             [str(G5.OUT[i]) for i in range(1, 160) if G5.OUT[i] is not None]
             if "Claude is connected" in x]
    if len(again) != len(ran):
        fails.append("the same command ran a second time — a rebuild applied "
                     "twice is two maps on top of each other")
    else:
        print("  ok  a command runs once and is never repeated")

    # ---- 6a. THE PURGE COMMAND REMOVES THE RIGHT THINGS AND ONLY THOSE ----
    # A command that deletes parts out of someone's place has to be exact. Too
    # little and the thing they asked to be rid of is still standing; too much
    # and it has eaten work that cannot be got back.
    lua6a, mock6a, G6a = studio()
    lua6a.eval("function(s,n) return assert(load(s,n)) end")(src_cmd, "@StarPetsSync")()
    lua6a.execute("""
        local map = Instance.new("Folder"); map.Name = "StarPetsMap"; map.Parent = workspace
        -- what must go
        for _, n in ipairs({"LBBase","LBBack","LBFrame","LBTitle","ShopFloor",
                            "ShopWallF","ShopRoof","ShopRoofNeon","ShopSign",
                            "LampPost","LampHead","UpgPad_1","UpgIcon_1"}) do
            local p = Instance.new("Part"); p.Name = n; p.Parent = map
        end
        local orb = Instance.new("Part"); orb.Name = "RMOrb"; orb.Parent = map
        local lamp = Instance.new("PointLight"); lamp.Name = "Glow"; lamp.Parent = orb
        -- what must stay: the rest of the rebirth machine, the map, and
        -- anything hand-built
        for _, n in ipairs({"RMBase","RMCore","RMPillar","TreeTrunk"}) do
            local p = Instance.new("Part"); p.Name = n; p.Parent = map
        end
        local mine = Instance.new("Part"); mine.Name = "MyOwnBuild"; mine.Parent = workspace
    """)
    lua6a.globals().RUNCMDS()

    def present(name):
        ws = mock6a["workspace"]
        return ws["FindFirstChild"](ws, name, True) is not None

    gone = [n for n in ("LBBase", "LBFrame", "ShopFloor", "ShopWallF",
                        "ShopRoofNeon", "ShopSign", "LampPost", "UpgPad_1",
                        "UpgIcon_1") if present(n)]
    if gone:
        fails.append("the purge left %d of the parts it exists to remove: %s"
                     % (len(gone), ", ".join(gone)))
    else:
        print("  ok  purge removes the board, the shop, the pads and the lamps")

    kept = [n for n in ("RMBase", "RMCore", "RMPillar", "RMOrb", "TreeTrunk",
                        "MyOwnBuild") if not present(n)]
    if kept:
        fails.append("the purge destroyed things it must not touch: %s"
                     % ", ".join(kept))
    else:
        print("  ok  and leaves the rebirth machine and hand-built parts alone")

    if present("Glow"):
        fails.append("the PointLight survived — 'the glow' is what the owner "
                     "pointed at")
    else:
        print("  ok  and every light source is gone")

    # ---- 6a2. THE GLOW STRIPPER ------------------------------------------
    # A baked place keeps its own older map, so a glowing rebirth pad from a
    # previous build survives every code sync. The stripper turns that off —
    # and must leave the lava and the crater, which are the only neon the
    # current map is supposed to have.
    lua6b, mock6b, G6b = studio()
    lua6b.eval("function(s,n) return assert(load(s,n)) end")(src_cmd, "@StarPetsSync")()
    lua6b.execute("""
        local map = Instance.new("Folder"); map.Name = "StarPetsMap"; map.Parent = workspace
        -- The magenta pad at the rebirth machine, 0.3 studs high. That height
        -- is why this is seeded rather than assumed: string.format("%d", 0.3)
        -- raises "number has no integer representation", and the command died
        -- half way through, after printing its header and before changing
        -- anything.
        PAD = Instance.new("Part"); PAD.Name = "RMRing"
        PAD.Material = Enum.Material.Neon
        PAD.Position = Vector3.new(-55, 0, 0)
        PAD.Size = Vector3.new(15, 0.3, 15)
        PAD.Parent = map
        -- Lava, out where neon belongs.
        LAVA = Instance.new("Part"); LAVA.Name = "LavaPool"
        LAVA.Material = Enum.Material.Neon
        LAVA.Position = Vector3.new(380, 1, -27)
        LAVA.Size = Vector3.new(10, 1, 10)
        LAVA.Parent = map
    """)
    lua6b.globals().RUNCMDS()

    warned = [str(G6b.WARN[i]) for i in range(1, 20) if G6b.WARN[i] is not None]
    if any("failed" in w for w in warned):
        fails.append("a pushed command threw in the place: %s" % warned[0][:120])
    elif "SmoothPlastic" not in str(lua6b.globals().PAD._p.Material):
        fails.append("the glowing pad is still Neon after the strip")
    elif "Neon" not in str(lua6b.globals().LAVA._p.Material):
        fails.append("the strip turned the volcano's lava off too — that neon "
                     "is the map's only intended glow")
    else:
        print("  ok  glow stripper kills stray neon and spares the lava")

    # ---- 6b. A SYNC NEVER DESTROYS WHAT WAS THERE -------------------------
    # A sync replaces the three code folders wholesale, so anything edited by
    # hand in Studio goes with them. That is "everything I customised went back
    # to normal", and by the time it is noticed the work is already gone. The
    # replaced copy has to survive somewhere, and the overwrite has to be said
    # out loud.
    lua7, mock7, G7 = studio()
    lua7.eval("function(s,n) return assert(load(s,n)) end")(src, "@StarPetsSync")()
    lua7.globals().SYNC(False)
    lua7.execute("""
        local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
        MINE = server:FindFirstChild("PetService")
        MINE.Source = "-- my own change that must not vanish\\n" .. MINE.Source
    """)
    lua7.globals().SYNC(False)

    ss = mock7["game"]["GetService"](mock7["game"], "ServerStorage")
    shelf = ss["FindFirstChild"](ss, "StarPetsBackup")
    if shelf is None:
        fails.append("a sync destroyed the previous code with no copy kept — a "
                     "hand edit in Studio is gone the moment anyone syncs")
    else:
        kept = None
        for slot in shelf["GetChildren"](shelf).values():
            folder = slot["FindFirstChild"](slot, "Server")
            if folder is not None:
                found = folder["FindFirstChild"](folder, "PetService")
                if found is not None and "must not vanish" in str(found._p.Source):
                    kept = found
        if kept is None:
            fails.append("the backup exists but does not contain the edited file")
        else:
            print("  ok  a hand-edited script survives a sync, in ServerStorage")
        said = any("ServerStorage" in str(G7.OUT[i] or "") for i in range(1, 60))
        if not said:
            fails.append("nothing told the developer their files were replaced "
                         "or where the old ones went")
        else:
            print("  ok  and the overwrite is announced, with where to find it")

        # An unbounded shelf grows the place file by the whole codebase per sync.
        for _ in range(5):
            lua7.globals().SYNC(False)
        slots = len(list(shelf["GetChildren"](shelf).values()))
        if slots > 3:
            fails.append("%d backups kept — the shelf grows without limit" % slots)
        else:
            print("  ok  keeps the last %d backups and prunes the rest" % slots)

    # ---- 7. THE SNAPSHOT DESCRIBES THIS PLACE, NOT A GENERIC ONE ----------
    # The return leg. Its whole value is that someone outside Studio can read
    # it and know what is wrong, so a report that omits the failure, or invents
    # one, is worse than no report: it sends the next hour of work in the wrong
    # direction.
    src_rep = src.replace("local function buildReport()", "function BUILDREPORT()")
    src_rep = src_rep.replace("pcall(buildReport)", "pcall(BUILDREPORT)")
    lua6, mock6, G6 = studio()
    lua6.eval("function(s,n) return assert(load(s,n)) end")(src_rep, "@StarPetsSync")()
    lua6.globals().SYNC(False)

    # A place with a map in it, and a neon part, and one world.
    lua6.execute("""
        local map = Instance.new("Folder"); map.Name = "StarPetsMap"
        map:SetAttribute("StarPetsBaked", true)
        map.Parent = workspace
        local meadow = Instance.new("Folder"); meadow.Name = "Meadow"; meadow.Parent = map
        for i = 1, 7 do
            local p = Instance.new("Part"); p.Name = "Prop" .. i
            p.Material = Enum.Material.Plastic
            p.Parent = meadow
        end
        local lava = Instance.new("Part"); lava.Name = "Lava"
        lava.Material = Enum.Material.Neon; lava.Parent = meadow
    """)
    # A key-shaped string in this plugin's settings. Studio keeps settings per
    # plugin so the AI panel's key is out of reach anyway, but a report that
    # dumped settings would still be a leak waiting to happen.
    lua6.execute('SETTINGS["StarPetsAIKey"] = "sk-ant-api03-NOT-A-REAL-KEY"')

    def report():
        r = lua6.globals().BUILDREPORT()
        return str(r[0] if isinstance(r, tuple) else r)

    rep = report()
    want = ["StarPetsMap", "Meadow", "neon: 1", "Server", "Client", "WARNINGS"]
    absent = [w for w in want if w not in rep]
    if absent:
        fails.append("the snapshot never mentions %s, so it does not actually "
                     "describe this place" % ", ".join(absent))
    else:
        print("  ok  the snapshot describes the real place (%d lines)"
              % len(rep.splitlines()))

    if "sk-ant" in rep:
        fails.append("the snapshot printed a key-shaped setting value")
    else:
        print("  ok  the snapshot carries no credential")

    # The folders the client blocks on are read out of the client's own source,
    # so this check is only meaningful if it found some.
    if "FOLDERS THE CLIENT WAITS FOR" not in rep:
        fails.append("the snapshot found no workspace:WaitForChild in the "
                     "client — that scan is the thing that catches a joining "
                     "player frozen forever, and it is reading nothing")
    else:
        waited = [ln.split()[0] for ln in rep.splitlines()
                  if ln.startswith("  ") and ln.strip().endswith("MISSING")]
        if not waited:
            fails.append("every folder the client waits for was reported ok in "
                         "a place where none of them exist")
        else:
            name = waited[0]
            if ("workspace.%s" % name) not in rep:
                fails.append("a missing folder was listed but no warning "
                             "explains what it breaks")
            else:
                print("  ok  names the %d folder(s) a joining player would hang on"
                      % len(waited))
            lua6.execute('local f = Instance.new("Folder") f.Name = "%s" '
                         'f.Parent = workspace' % name)
            if ("%s" % name) in [ln.split()[0] for ln in report().splitlines()
                                 if ln.strip().endswith("MISSING")]:
                fails.append("a folder that now exists is still reported missing")
            else:
                print("  ok  and stops reporting it once it exists")

    # Behind-the-remote is the single most common state, and the one the owner
    # cannot see from inside Studio at all.
    lua6.execute('SETTINGS["StarPetsVersion"] = "0000000000deadbeef"')
    rep_behind = report()
    if "Sync now" not in rep_behind:
        fails.append("a place running older code than the remote is not told to "
                     "sync — this is exactly the 'I pushed and nothing changed' "
                     "case the snapshot exists for")
    else:
        print("  ok  says plainly when the place is behind the remote")

    lua6.execute("""
        local dupe = Instance.new("Folder"); dupe.Name = "Server"
        dupe.Parent = game:GetService("ServerScriptService")
    """)
    if "2 copies of Server" not in report():
        fails.append("two Server folders were not reported — two copies of the "
                     "game running at once looks exactly like nothing changed")
    else:
        print("  ok  catches a duplicate install")

    # ---- 8. THE PLACE CAN SEND ITSELF BACK --------------------------------
    # The point of this one: seeing the game must not depend on the owner
    # taking a screenshot. The plugin describes the open place and posts it,
    # and what arrives has to be enough to DRAW — not a summary, geometry.
    import json as _json
    src_send = src.replace("local function sendToClaude()", "function SENDTOCLAUDE()")
    src_send = src_send.replace("local function buildReport()", "function BUILDREPORT()")
    src_send = src_send.replace("pcall(buildReport)", "pcall(BUILDREPORT)")
    src_send = src_send.replace("local report = select(1, buildReport())",
                                "local report = select(1, BUILDREPORT())")
    lua8, mock8, G8 = studio()

    posted = {}

    def _from_lua(o):
        if lupa.lua_type(o) == "table":
            ks = list(o.keys())
            if ks and all(isinstance(k, int) for k in ks) and \
                    sorted(ks) == list(range(1, len(ks) + 1)):
                return [_from_lua(o[i]) for i in range(1, len(ks) + 1)]
            return {str(k): _from_lua(o[k]) for k in ks}
        return o

    G8["PY_POST"] = lambda url, body: posted.update(url=url, body=body)
    G8["PY_ENCODE"] = lambda t: _json.dumps(_from_lua(t))
    endpoint_raw = (ROOT / "bridge/endpoint.json").read_text()
    G8["ENDPOINT_JSON"] = endpoint_raw
    G8["DECODED_ENDPOINT"] = lua8.table_from(_json.loads(endpoint_raw))
    lua8.execute("""
        local hs = game:GetService("HttpService")
        hs.PostAsync = function(_, url, body) PY_POST(url, body) end
        hs.JSONEncode = function(_, t) return PY_ENCODE(t) end
        local realGet, realDecode = hs.GetAsync, hs.JSONDecode
        hs.GetAsync = function(self, url)
            if url:find("endpoint.json") then return ENDPOINT_JSON end
            return realGet(self, url)
        end
        hs.JSONDecode = function(self, s)
            if s == ENDPOINT_JSON then return DECODED_ENDPOINT end
            return realDecode(self, s)
        end
    """)
    lua8.eval("function(s,n) return assert(load(s,n)) end")(src_send, "@StarPetsSync")()
    lua8.execute("""
        local map = Instance.new("Folder"); map.Name = "StarPetsMap"; map.Parent = workspace
        local g = Instance.new("Part"); g.Name = "Ground"
        g.Position = Vector3.new(0, -1, 0); g.Size = Vector3.new(200, 2, 160)
        g.Color = Color3.fromRGB(94, 168, 74); g.Parent = map
        local b = Instance.new("Part"); b.Name = "Biome_Meadow"
        b.Position = Vector3.new(0, 0, 0); b.Size = Vector3.new(4, 1, 4)
        b.Color = Color3.fromRGB(94, 168, 74); b.Parent = map
        local ball = Instance.new("Part"); ball.Name = "TreeLeaf1"
        ball.Shape = Enum.PartType.Ball
        ball.Position = Vector3.new(20, 8, 10); ball.Size = Vector3.new(8, 7, 8)
        ball.Color = Color3.fromRGB(58, 130, 58); ball.Parent = map
    """)
    sent = lua8.globals().SENDTOCLAUDE()

    if not sent or "body" not in posted:
        fails.append("the place could not send itself — seeing the game still "
                     "depends on someone taking a screenshot")
    else:
        doc = _json.loads(posted["body"])
        if "webhook-triggers" not in posted["url"]:
            fails.append("posted somewhere unexpected: %s" % posted["url"][:60])
        elif not doc.get("parts"):
            fails.append("the payload carried no geometry, so nothing can be drawn")
        elif len(doc["parts"][0]) != 12:
            fails.append("a part row has %d fields, not the 12 the renderer "
                         "reads" % len(doc["parts"][0]))
        elif not doc.get("text"):
            fails.append("the payload carried no snapshot text")
        else:
            # And it has to actually DRAW. A payload that parses but renders
            # nothing is the same as no payload.
            sys.path.insert(0, str(ROOT / "tools"))
            import render_place  # noqa: E402
            boxes = render_place.boxes_from(doc)
            shapes = {s for *_, s in [(b[-1],) for b in boxes]} if boxes else set()
            if len(boxes) < 3:
                fails.append("only %d of %d parts survived into the renderer"
                             % (len(boxes), len(doc["parts"])))
            elif "ball" not in {b[7] for b in boxes}:
                fails.append("round parts came through as boxes — every tree "
                             "crown in the place would render square")
            else:
                _ = shapes
                print("  ok  the place sends itself: %d parts, %d KB, and it draws"
                      % (len(doc["parts"]), len(posted["body"]) // 1024))

    # No endpoint published must fall back, not fail silently.
    lua8.execute('ENDPOINT_JSON = "{}"')
    lua8.execute("DECODED_ENDPOINT = {}")
    posted.clear()
    fell_back = lua8.globals().SENDTOCLAUDE()
    if fell_back or posted:
        fails.append("with no endpoint published it still claimed to send")
    else:
        print("  ok  and falls back to copy-and-paste when there is nowhere "
              "to send")

    if fails:
        print("\nbridge: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\nbridge: a push reaches the place, safely, without anyone installing "
          "a file")
    return 0


if __name__ == "__main__":
    sys.exit(main())
