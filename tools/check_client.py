#!/usr/bin/env python3
"""Run the client top to bottom against a real, booted server.

Everything else here tests the server. The client had never been EXECUTED —
only parsed — and parsing proves nothing about whether it runs. A LocalScript
that throws on line 90 leaves a player staring at the loading screen with no
HUD, no buttons and no panels, while the server is perfectly healthy and every
server check passes.

That failure looks, from the outside, exactly like "nothing changed".

The server is booted first so the client meets the real thing: the real
Remotes folder, the real map, the real GameConfig. A client that waits for a
remote the server no longer creates hangs here in the same way it would hang
in game.
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402
import check_map  # noqa: E402


def boot():
    """Boot server + client and hand back the running world.

    Split out from main() so other checks can drive the real, booted client
    instead of standing up a second, subtly different one. Returns
    (lua, mock, PlayerGui, problems); on a failure that makes the client
    unusable the first three are None.
    """
    # A fully built world, exactly as a joining player would find it.
    lua, mock, cfg = check_map.build()
    G = lua.globals()

    # The client half of the world: a LocalPlayer with a PlayerGui.
    player = mock["newInst"]("Player")
    player.Name = "Tester"
    player.UserId = 7777
    gui = mock["newInst"]("PlayerGui"); gui.Name = "PlayerGui"; gui.Parent = player
    char = mock["newInst"]("Model"); char.Name = "Tester"
    root = mock["newInst"]("Part"); root.Name = "HumanoidRootPart"; root.Parent = char
    hum = mock["newInst"]("Humanoid"); hum.Name = "Humanoid"; hum.Parent = char
    player.Character = char
    mock["PlayerList"][1] = player
    mock["Players"].LocalPlayer = player

    lua.execute("""
        __ERRORS = {}
        __WARNINGS = {}
        warn = function(...)
            local p = {}
            for i = 1, select('#', ...) do p[i] = tostring((select(i, ...))) end
            __WARNINGS[#__WARNINGS+1] = table.concat(p, ' ')
        end
        print = function() end
        -- task.spawn runs INLINE here on purpose. Most of the client's work
        -- happens inside spawned threads, and a stub that discards them would
        -- leave this check reporting a clean run of almost nothing.
        task = {
            spawn = function(f, ...)
                local ok, err = pcall(f, ...)
                if not ok then __ERRORS[#__ERRORS+1] = tostring(err) end
            end,
            defer = function(f, ...) if f then pcall(f, ...) end end,
            delay = function(_, f, ...) end,
            wait = function() return 0.03 end,
        }
        wait = task.wait
        spawn = task.spawn
        delay = function() end
    """)

    def load(path, name):
        return lua.eval("function(s,n) return assert(load(s,n)) end")(
            luau_to_lua(Path(path).read_text()), "@" + name)()

    # UI modules, as children of a Client/UI folder, the way Rojo lays them out.
    sps = mock["newInst"]("StarterPlayerScripts")
    sps.Name = "StarterPlayerScripts"
    sps.Parent = mock["game"]["GetService"](mock["game"], "StarterPlayer")
    client_folder = mock["newInst"]("Folder")
    client_folder.Name = "Client"; client_folder.Parent = sps
    ui = mock["newInst"]("Folder"); ui.Name = "UI"; ui.Parent = client_folder

    failed = []
    markers = {}
    localscripts = []
    for f in sorted((ROOT / "src/Client/UI").glob("*.lua")):
        # A *.client.lua under UI is a LocalScript: it RUNS on its own and is
        # never required. Treating one as a module is how BadgePopup came to be
        # shipped as a ModuleScript that nothing required, so it never executed
        # and badge popups never appeared.
        if f.name.endswith(".client.lua"):
            localscripts.append(f)
            continue
        name = "HatchPanel" if f.stem == "HatchUI" else f.stem
        m = mock["newInst"]("ModuleScript"); m.Name = name; m.Parent = ui
        markers[name] = (m, f)
    for _ in range(3):
        for name, (m, f) in markers.items():
            if mock["MODULES"][m] is not None:
                continue
            G["script"] = m
            try:
                mock["MODULES"][m] = load(f, name)
            except Exception as e:
                failed.append((name, str(e).splitlines()[0][:150]))
    unloaded = [n for n, (m, _) in markers.items() if mock["MODULES"][m] is None]
    if unloaded:
        print("UI modules that failed to LOAD: %s" % ", ".join(sorted(unloaded)))
        seen = set()
        for n, e in failed:
            if n in unloaded and n not in seen:
                seen.add(n)
                print("   x %-20s %s" % (n, e))
        if not seen:
            print("   (no exception raised — the module returned nil, which "
                  "means require() would hand back nothing)")
        return None, None, None, 1
    print("all %d UI modules loaded" % len(markers))

    # The UI LocalScripts, run the way Roblox runs them: on their own, with no
    # require anywhere.
    for f in localscripts:
        ls = mock["newInst"]("LocalScript"); ls.Name = f.name[:-11]; ls.Parent = ui
        G["script"] = ls
        try:
            load(f, ls.Name)
        except Exception as e:
            print("   x UI LocalScript %s THREW: %s"
                  % (f.name, str(e).splitlines()[0][:150]))
            return None, None, None, 1
        print("   ok  %-18s ran on its own (LocalScript)" % f.name[:-11])

    # The client script itself.
    gc = mock["newInst"]("LocalScript"); gc.Name = "GameClient"
    gc.Parent = client_folder
    G["script"] = gc
    src = luau_to_lua((ROOT / "src/Client/GameClient.client.lua").read_text())
    try:
        fn = lua.eval("function(s,n) return assert(load(s,n)) end")(src, "@GameClient")
    except Exception as e:
        print("   x GameClient did not COMPILE: %s" % str(e).splitlines()[0][:200])
        return None, None, None, 1
    try:
        fn()
    except Exception as e:
        print("\n   x GameClient THREW while starting up:")
        for line in str(e).splitlines()[:12]:
            print("       " + line[:150])
        print("\n   A player would sit on the loading screen with no HUD and no")
        print("   buttons, while every server check passes.")
        return None, None, None, 1

    guis = [g for g in gui["GetChildren"](gui).values()]
    names = sorted(str(g._p.Name) for g in guis)
    print("GameClient ran to completion")
    print("   ScreenGuis created: %d  (%s)" % (len(guis), ", ".join(names[:8])))

    bad = 0
    errs = []
    i = 1
    while G.__ERRORS[i] is not None:
        errs.append(str(G.__ERRORS[i])); i += 1
    if errs:
        print("\n   %d error(s) inside spawned client threads:" % len(errs))
        for e in errs[:8]:
            print("      ! " + e[:160])
        bad += 1

    # The HUD is the thing a player touches. No HUD means no game.
    if not any("HUD" in n or "Hud" in n for n in names):
        print("   x no HUD ScreenGui was created — a player has no buttons")
        bad += 1
    else:
        print("   ok  a HUD exists")

    # Every remote the client waits for must exist, or it hangs on join.
    rs = mock["ReplicatedStorage"]
    remotes = rs["FindFirstChild"](rs, "Remotes")
    if remotes is None:
        print("   x no Remotes folder — the client would hang on WaitForChild")
        return None, None, None, 1
    have = {str(c._p.Name) for c in remotes["GetChildren"](remotes).values()}
    import re as _re
    want = set(_re.findall(r'Remotes:WaitForChild\(\s*"(\w+)"',
                           (ROOT / "src/Client/GameClient.client.lua").read_text()))
    missing = sorted(want - have)
    if missing:
        print("   x the client waits for remote(s) the server never creates: %s"
              % ", ".join(missing))
        bad += 1
    else:
        print("   ok  all %d remotes the client waits for exist" % len(want))

    if bad:
        print("\nclient: %d problems" % bad)
    else:
        print("\nclient: starts up clean against a real server")
    # The world is handed back even when `bad` is set: a client that started
    # with complaints is still a client another check can drive, and pretending
    # otherwise would make those checks unrunnable exactly when they matter.
    return lua, mock, gui, bad


def main():
    return 1 if boot()[3] else 0


if __name__ == "__main__":
    sys.exit(main())
