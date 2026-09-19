#!/usr/bin/env python3
"""Run GameServer.server.lua from top to bottom and see whether it survives.

A server Script that throws part-way through does not report anything useful in
game: everything after the throwing line simply never runs, so there is no map,
no eggs and no remotes, and the game looks exactly like it did before — which
is indistinguishable from "your change did nothing".

Boots three ways:
  * as a live server
  * as Studio, which is the only place the "how to keep your map" notice runs,
    so a mistake in it breaks startup for the one person able to diagnose it
  * as Studio on a place with a BAKED map, where the builder must not run at
    all and the map must survive untouched
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "src/Server"
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402


def main(studio=False, baked=False):
    print("=== booting as %s%s ===" % (
        "STUDIO (developer)" if studio else "a live server",
        ", on a place with a BAKED map" if baked else ""))

    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    lua.execute("math.clamp=function(x,l,h) return math.max(l,math.min(h,x)) end;"
                "math.round=function(x) return math.floor(x+0.5) end")
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Vector3", "CFrame", "Color3", "Enum", "Instance", "game", "workspace",
              "Random", "UDim", "UDim2", "Vector2", "NumberRange", "NumberSequence",
              "ColorSequence", "NumberSequenceKeypoint", "ColorSequenceKeypoint",
              "TweenInfo", "Ray"):
        G[k] = mock[k]
    if studio:
        gm = mock["game"]
        gm["GetService"](gm, "RunService").__studio = True

    # Warnings are collected rather than swallowed: GameServer pcalls a lot of
    # its own startup, so a real failure often surfaces only as a warn().
    lua.execute("""
        __WARNINGS = {}
        warn = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
            __WARNINGS[#__WARNINGS+1] = table.concat(parts, ' ')
        end
        task = {
            spawn = function() end, defer = function() end, delay = function() end,
            wait = function() return 0.03 end,
        }
        wait = function() return 0.03 end
        delay = function() end
        spawn = function() end
        __PRINTS = {}
        local _print = print
        print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
            __PRINTS[#__PRINTS+1] = table.concat(parts, ' ')
        end
    """)

    def load(path, name):
        chunk = lua.eval("function(s, n) return assert(load(s, n)) end")(
            luau_to_lua(Path(path).read_text()), "@" + name)
        return chunk()

    # ---- Shared config, where every module expects to find it --------------
    rs = mock["ReplicatedStorage"]
    shared = mock["newInst"]("Folder"); shared.Name = "Shared"; shared.Parent = rs
    G["require"] = mock["robloxRequire"]

    failed_modules = []
    for f in sorted((ROOT / "src/Shared").glob("*.lua")):
        marker = mock["newInst"]("ModuleScript"); marker.Name = f.stem
        marker.Parent = shared
        try:
            # `script` inside a ModuleScript means that module's own instance.
            # Set per module: these resolve siblings through script.Parent at
            # LOAD time, so a single global set afterwards is far too late.
            G["script"] = marker
            mock["MODULES"][marker] = load(f, f.stem)
        except Exception as e:
            failed_modules.append((f.stem, str(e).splitlines()[0][:160]))

    # ---- Server modules, as siblings under script.Parent -------------------
    sss = mock["ServerScriptService"]
    holder = mock["newInst"]("Folder"); holder.Name = "Server"; holder.Parent = sss
    markers = {}
    for f in sorted(SERVER.glob("*.lua")):
        if f.name.endswith(".server.lua"):
            continue
        m = mock["newInst"]("ModuleScript"); m.Name = f.stem; m.Parent = holder
        markers[f.stem] = (m, f)

    # Two passes: a module that requires a sibling needs that sibling present.
    for _ in range(3):
        for name, (m, f) in markers.items():
            if mock["MODULES"][m] is not None:
                continue
            try:
                G["script"] = m
                mock["MODULES"][m] = load(f, name)
            except Exception as e:
                failed_modules.append((name, str(e).splitlines()[0][:160]))
    failed_modules = [(n, e) for n, e in failed_modules
                      if mock["MODULES"][markers[n][0]] is None] if markers else failed_modules

    if failed_modules:
        print("modules that failed to LOAD (the game cannot start):")
        seen = set()
        for nm, e in failed_modules:
            if nm in seen:
                continue
            seen.add(nm)
            print("   x %-18s %s" % (nm, e))
        return 1
    print("all %d server modules loaded" % len(markers))

    # A place somebody built and saved: StarPetsMap already in the Workspace,
    # flagged as theirs, with a hand-made part in it. The server must keep it
    # exactly as it is — no rebuild, nothing overwritten.
    if baked:
        ws0 = mock["workspace"]
        seeded = mock["newInst"]("Folder"); seeded.Name = "StarPetsMap"
        seeded.Parent = ws0
        seeded["SetAttribute"](seeded, "StarPetsBaked", True)
        keep = mock["newInst"]("Part"); keep.Name = "MyHandBuiltTower"; keep.Parent = seeded
        egg = mock["newInst"]("Part"); egg.Name = "Egg_StarterEgg"; egg.Parent = seeded
        cd = mock["newInst"]("ClickDetector")
        cd["SetAttribute"](cd, "SPAction", "HatchEgg")
        cd["SetAttribute"](cd, "SPArg", "StarterEgg")
        cd.Parent = egg

    gs_marker = mock["newInst"]("Script"); gs_marker.Name = "GameServer"
    gs_marker.Parent = holder
    G["script"] = gs_marker

    src = luau_to_lua((SERVER / "GameServer.server.lua").read_text())
    try:
        fn = lua.eval("function(s,n) return assert(load(s,n)) end")(src, "@GameServer")
    except Exception as e:
        print("   x GameServer did not COMPILE: %s" % str(e).splitlines()[0][:200])
        return 1
    try:
        fn()
    except Exception as e:
        print("\n   x GameServer THREW while starting up:")
        for line in str(e).splitlines()[:12]:
            print("       " + line[:150])
        print("\n   Everything after the throwing line never runs — no map, no")
        print("   eggs, no remotes. In game this looks like 'nothing changed'.")
        return 1

    ws = mock["workspace"]
    root = ws["FindFirstChild"](ws, "StarPetsMap")
    parts = eggs = 0
    if root is not None:
        for d in root["GetDescendants"](root).values():
            if d._p.ClassName == "Part":
                parts += 1
                if str(d._p.Name).startswith("Egg_"):
                    eggs += 1
    rem = rs["FindFirstChild"](rs, "Remotes") or rs["FindFirstChild"](rs, "StarPetsRemotes")
    remotes = sum(1 for _ in rem["GetChildren"](rem).values()) if rem is not None else 0

    warnings = G["__WARNINGS"]
    real = []
    i = 1
    while warnings[i] is not None:
        w = str(warnings[i])
        if ("error" in w.lower() or "attempt to" in w.lower() or "nil value" in w):
            real.append(w)
        i += 1

    print("GameServer ran to completion")
    bad = 0

    if baked:
        kept = root is not None and root["FindFirstChild"](root, "MyHandBuiltTower")
        print("   hand-built part : %s" % ("still there" if kept else "DESTROYED"))
        print("   map parts       : %d (a rebuild would be hundreds)" % parts)
        if not kept:
            print("\n   x the server destroyed a map the developer saved"); bad += 1
        if parts > 40:
            print("   x the map was REBUILT over a baked build — every edit lost"); bad += 1
        loose = sum(1 for d in ws["GetChildren"](ws).values()
                    if d._p.ClassName == "Part")
        if loose > 0:
            print("   x %d part(s) were built loose in Workspace anyway" % loose); bad += 1
    else:
        print("   map parts built : %d" % parts)
        print("   eggs built      : %d" % eggs)
        print("   remotes created : %d" % remotes)
        loose = sum(1 for d in ws["GetChildren"](ws).values()
                    if d._p.ClassName == "Part")
        print("   loose in Workspace: %d (must be 0 — the map has to copy as one folder)"
              % loose)
        if parts < 200:
            print("\n   x only %d map parts were built — the map did not finish" % parts)
            bad += 1
        if remotes < 15:
            print("   x only %d remotes created — the UI will hang on WaitForChild"
                  % remotes)
            bad += 1
        if loose > 0:
            print("   x %d part(s) sit loose in Workspace, so selecting StarPetsMap "
                  "and copying it would leave them behind" % loose)
            bad += 1

    if real:
        print("\n   %d warning(s) that look like real failures:" % len(real))
        for w in real[:8]:
            print("      ! " + w[:160])
        bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    rc = main(studio=False)
    print()
    rc = main(studio=True) or rc
    print()
    rc = main(studio=True, baked=True) or rc
    sys.exit(rc)
