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
    for k in ("Instance", "game", "workspace", "Color3", "Vector3", "Enum",
              "UDim2", "TweenInfo"):
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
