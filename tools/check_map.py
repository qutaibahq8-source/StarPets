#!/usr/bin/env python3
"""Build the map for real and measure what came out.

The map has failed silently before. One bad call part-way through and
everything after it simply never appears, with no error anywhere a player can
see — "did you change anything? it looks the same" is what that looks like from
the outside.

This runs the actual server build and counts where things landed.

  1. NO WORLD IS EMPTY       every world gets a comparable share of props
  2. NOTHING FLOATS          props belong on the ground, where the player is
  3. NO PILES                features several parts wide must not overlap
  4. NEON IS A SIGNAL        a budget, so it means "use this" and not "decor"
  5. EVERY WORLD DIFFERS     from the one before it, in hue or in brightness
"""
import colorsys
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402
import check_boot  # noqa: E402


def build():
    """Boot the real server and hand back its workspace."""
    import io
    import contextlib
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    lua.execute("math.clamp=function(x,l,h) return math.max(l,math.min(h,x)) end;"
                "math.round=function(x) return math.floor(x+0.5) end")
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Vector3", "CFrame", "Color3", "Enum", "Instance", "game", "workspace", "typeof",
              "Random", "UDim", "UDim2", "Vector2", "NumberRange", "NumberSequence",
              "ColorSequence", "NumberSequenceKeypoint", "ColorSequenceKeypoint",
              "TweenInfo", "Ray"):
        G[k] = mock[k]
    lua.execute("""
        __WARNINGS = {}
        warn = function(...) end
        task = { spawn=function() end, defer=function() end, delay=function() end,
                 wait=function() return .03 end }
        wait = function() return .03 end
        delay = function() end
        spawn = function() end
        print = function() end
    """)

    def load(path, name):
        return lua.eval("function(s,n) return assert(load(s,n)) end")(
            luau_to_lua(Path(path).read_text()), "@" + name)()

    rs = mock["ReplicatedStorage"]
    shared = mock["newInst"]("Folder"); shared.Name = "Shared"; shared.Parent = rs
    G["require"] = mock["robloxRequire"]
    cfg = None
    for f in sorted((ROOT / "src/Shared").glob("*.lua")):
        m = mock["newInst"]("ModuleScript"); m.Name = f.stem; m.Parent = shared
        G["script"] = m
        mock["MODULES"][m] = load(f, f.stem)
        if f.stem == "GameConfig":
            cfg = mock["MODULES"][m]

    sss = mock["ServerScriptService"]
    holder = mock["newInst"]("Folder"); holder.Name = "Server"; holder.Parent = sss
    markers = {}
    for f in sorted((ROOT / "src/Server").glob("*.lua")):
        if f.name.endswith(".server.lua"):
            continue
        m = mock["newInst"]("ModuleScript"); m.Name = f.stem; m.Parent = holder
        markers[f.stem] = (m, f)
    # Several passes: a module that requires a sibling needs that sibling
    # already present, and the alphabetical order does not respect that.
    for _ in range(4):
        for name, (m, f) in markers.items():
            if mock["MODULES"][m] is not None:
                continue
            G["script"] = m
            try:
                mock["MODULES"][m] = load(f, name)
            except Exception:
                pass
    unloaded = [n for n, (m, _) in markers.items() if mock["MODULES"][m] is None]
    if unloaded:
        raise SystemExit("modules failed to load: " + ", ".join(unloaded))

    gs = mock["newInst"]("Script"); gs.Name = "GameServer"; gs.Parent = holder
    G["script"] = gs
    src = luau_to_lua((ROOT / "src/Server/GameServer.server.lua").read_text())
    fn = lua.eval("function(s,n) return assert(load(s,n)) end")(src, "@GameServer")
    with contextlib.redirect_stdout(io.StringIO()):
        fn()
    return lua, mock, cfg


def parts_of(mock):
    ws = mock["workspace"]
    out = []
    for inst in ws["GetDescendants"](ws).values():
        pr = inst._p
        if pr.ClassName != "Part":
            continue
        pos = inst["Position"]
        if pos is None or pr.Size is None:
            continue
        out.append(inst)
    return out


def main():
    lua, mock, cfg = build()
    ws = mock["workspace"]
    all_parts = parts_of(mock)
    print("map: %d parts built" % len(all_parts))
    bad = 0

    # Where each world sits. Meadow is the spawn plaza at x=0; the rest are the
    # biome slabs, read from the map itself rather than hardcoded, so adding a
    # world cannot leave this check measuring the wrong place.
    centres = {"Meadow": 0.0}
    for p in all_parts:
        n = str(p._p.Name)
        if n.startswith("Biome_"):
            centres[n[6:]] = float(p["Position"].X)
    order = ["Meadow"] + [k for k in centres if k != "Meadow"]
    order.sort(key=lambda k: centres[k])

    # --- 1. NO WORLD IS EMPTY ----------------------------------------------
    # decorateBiome ran for four worlds and skipped Meadow, because Meadow is
    # the spawn plaza rather than a biome slab. So the first thing every player
    # saw, and the place they spend longest, was the one world with nothing in
    # it. A count per world is what makes that something the build can fail on
    # rather than something you notice in a screenshot months later.
    per = {}
    for name, cx in centres.items():
        per[name] = sum(1 for p in all_parts
                        if abs(float(p["Position"].X) - cx) <= 65)
    counts = sorted(per.values())
    median = counts[len(counts) // 2]
    floor = int(median * 0.45)
    print("  parts per world (median %d, floor %d):" % (median, floor))
    for name in order:
        ok = per[name] >= floor
        bad += 0 if ok else 1
        print("      %s %-9s %4d %s" % ("ok " if ok else "x  ", name, per[name],
                                        "" if ok else "<- nearly empty"))

    # --- 2. PROPS MUST TOUCH THE GROUND ------------------------------------
    # Space's entire prop set was neon balls placed between five and twenty-six
    # studs in the air. The ground a player walks on had nothing on it at all —
    # invisible from a part count, obvious the moment you stand in the world.
    #
    # Two earlier versions of this check were wrong, in both directions. The
    # first flagged any world with many parts above 14 studs and immediately
    # failed Forest at 47%, because tree canopies are SUPPOSED to be up there.
    # The second measured ground contact across ALL parts and reported a
    # comfortable 59% for a deliberately restored floating-Space, because the
    # floor, the gate and the egg stands are grounded and drowned the signal.
    #
    # So it measures ONLY the parts the prop sets emit, read from the MapProps
    # source rather than listed here, and asks whether those touch the floor.
    import re as _re
    prop_src = (ROOT / "src/Server/MapProps.lua").read_text()
    prop_names = set(_re.findall(r'(?:box|ball|column|disc)\(ctx,\s*"(\w+)"',
                                 prop_src))
    # Things the sets deliberately put overhead.
    OVERHEAD = {"Asteroid"}
    for name in order:
        cx = centres[name]
        props = [p for p in all_parts
                 if abs(float(p["Position"].X) - cx) <= 65
                 and str(p._p.Name) in prop_names
                 and str(p._p.Name) not in OVERHEAD]
        if len(props) < 10:
            bad += 1
            print("  x   %s has almost no props at all (%d)" % (name, len(props)))
            continue
        grounded = sum(
            1 for p in props
            if float(p["Position"].Y) - float(p._p.Size.Y) * 0.5 <= 2.5)
        frac = grounded / len(props)
        if frac < 0.20:
            bad += 1
            print("  x   %s: only %.0f%% of its %d props touch the ground — the "
                  "surface a player walks on is bare"
                  % (name, frac * 100, len(props)))
        else:
            print("  ok  %-9s %.0f%% of %d props sit on the ground"
                  % (name, frac * 100, len(props)))

    # --- 3. NO PILES --------------------------------------------------------
    # Features several parts wide, dropped at random, land inside one another.
    worst = (0, "-")
    for name in order:
        cx = centres[name]
        pts = [(float(p["Position"].X), float(p["Position"].Z)) for p in all_parts
               if abs(float(p["Position"].X) - cx) <= 65
               and float(p["Position"].Y) < 40]
        peak = 0
        for px, pz in pts[::3]:
            n = sum(1 for qx, qz in pts if (qx - px) ** 2 + (qz - pz) ** 2 < 144)
            peak = max(peak, n)
        if peak > worst[0]:
            worst = (peak, name)
    if worst[0] > 75:
        bad += 1
        print("  x   %s has %d parts inside one 12-stud disc — props are being "
              "placed on top of each other" % (worst[1], worst[0]))
    else:
        print("  ok  worst pile is %d parts in 12 studs (%s)" % worst)

    # --- 4. NEON IS A SIGNAL ------------------------------------------------
    neon = sum(1 for p in all_parts
               if p._p.Material is not None
               and str(p._p.Material).endswith("Neon"))
    pct = 100.0 * neon / max(1, len(all_parts))
    if pct > 8.0:
        bad += 1
        print("  x   %d neon parts (%.0f%% of the map) — neon is meant to mark "
              "what you can use, not to decorate" % (neon, pct))
    else:
        print("  ok  neon is %.0f%% of the map (%d parts)" % (pct, neon))

    # --- 5. EVERY WORLD DIFFERS FROM THE ONE BEFORE -------------------------
    # Worlds that look alike make progression feel like it is not happening.
    # Measured on the floor colour, which is what fills the screen.
    floors = {}
    for p in all_parts:
        n = str(p._p.Name)
        if n.startswith("Biome_"):
            c = p._p.Color
            floors[n[6:]] = (float(c.R), float(c.G), float(c.B))
    gf = [p for p in all_parts if str(p._p.Name) == "GroundFloor"]
    if gf:
        c = gf[0]._p.Color
        floors["Meadow"] = (float(c.R), float(c.G), float(c.B))
    print("  world colour journey:")
    prev = None
    for name in order:
        if name not in floors:
            continue
        r, g, b = floors[name]
        h, _, v = colorsys.rgb_to_hsv(r, g, b)
        print("      %-9s hue %3d  brightness %.2f  %s"
              % (name, int(h * 360), v, "#" * int(v * 24)))
        if prev is not None:
            dh = abs(h - prev[0])
            dh = min(dh, 1 - dh) * 360
            dv = abs(v - prev[1])
            if dh < 22 and dv < 0.16:
                bad += 1
                print("      x   %s looks like the world before it (hue %+d, "
                      "brightness %+.2f)" % (name, int(dh), dv))
        prev = (h, v)
    if bad == 0:
        print("  ok  every world differs from the one before it")

    # --- THE CLIENT MUST LOOK WHERE THE SERVER PUTS THINGS ------------------
    # The client resolves world folders by name at Workspace level. When the
    # barriers moved inside StarPetsMap so the map would copy as one selection,
    # `workspace:WaitForChild("AreaBarriers", 30)` was left behind — it would
    # have timed out, returned nil, and every locked world would have stayed
    # sealed forever because nothing ever updated a barrier again.
    #
    # That is invisible in every other check here: the map builds correctly, the
    # server boots clean, and the game is broken.
    import re as _re
    client_src = "\n".join(f.read_text() for f in
                            sorted((ROOT / "src/Client").rglob("*.lua")))
    # ONLY the blocking form. workspace:WaitForChild yields until the thing
    # appears and then returns nil, so a missing folder costs 30 seconds and
    # then silently disables whatever needed it. FindFirstChild returning nil is
    # an explicit, handled case — PetMeshes is an optional developer-supplied
    # folder looked up that way with a fallback, and flagging it was this
    # check's first false positive.
    wanted = set(_re.findall(
        r'workspace:WaitForChild\(\s*"(\w+)"', client_src))
    root_f = ws["FindFirstChild"](ws, "StarPetsMap")
    for name in sorted(wanted):
        if name == "StarPetsMap":
            continue
        at_workspace = ws["FindFirstChild"](ws, name) is not None
        in_map = root_f is not None and root_f["FindFirstChild"](root_f, name) is not None
        if at_workspace:
            print("  ok  client finds %-16s at Workspace, where the server puts it"
                  % name)
        elif in_map:
            # Acceptable only if the client also knows to look inside the map.
            if ('FindFirstChild("StarPetsMap")' in client_src
                    and name in client_src):
                print("  ok  client finds %-16s inside StarPetsMap (has the fallback)"
                      % name)
            else:
                bad += 1
                print("  x   the client waits for workspace.%s but the server "
                      "builds it inside StarPetsMap — it will wait, time out, "
                      "and that feature silently stops working" % name)
        else:
            bad += 1
            print("  x   the client waits for workspace.%s and the server never "
                  "creates it anywhere" % name)

    # ---- THINGS THE OWNER ASKED NOT TO EXIST ------------------------------
    # Each of these was removed once already. Without a check they come back on
    # the next person who thinks the spawn looks empty, and the owner has to
    # notice and ask again.
    banned_names = {
        # the leaderboard board that stood at spawn
        "LBBase", "LBBack", "LBFrame", "LBTitle",
        # the shop building west of spawn, next to the rebirth machine
        "ShopFloor", "ShopWallF", "ShopWallB", "ShopWallL", "ShopWallR",
        "ShopRoof", "ShopRoofNeon", "ShopSign",
        # the lamp posts that lined the walking paths
        "LampPost", "LampArm", "LampHead",
    }
    banned_prefixes = ("UpgPad_", "UpgIcon_")

    found, lights = [], []
    stack = [mock["workspace"]]
    while stack:
        node = stack.pop()
        for c in node["GetChildren"](node).values():
            nm, cls = str(c._p.Name), str(c._p.ClassName)
            if nm in banned_names or nm.startswith(banned_prefixes):
                found.append(nm)
            if cls in ("PointLight", "SpotLight", "SurfaceLight"):
                lights.append("%s on %s" % (cls, str(node._p.Name)))
            stack.append(c)

    if found:
        bad += 1
        print("  x   the map builds %d part(s) the owner had removed: %s"
              % (len(found), ", ".join(sorted(set(found)))))
    else:
        print("  ok  no shop building, no leaderboard board, no path lamps")

    # "the glow" — the owner's words. One PointLight on the rebirth orb was the
    # last light source in the map, and it was on the one machine they pointed
    # at. Zero is the number.
    if lights:
        bad += 1
        print("  x   %d light source(s) in the map, which the owner asked not to "
              "have: %s" % (len(lights), ", ".join(sorted(set(lights)))))
    else:
        print("  ok  no light sources anywhere in the map")

    # ---- SIGNS MUST NOT PILE UP -------------------------------------------
    # A BillboardGui with no MaxDistance draws from anywhere on the map. With
    # four locked worlds that meant four unlock signs at 640x240, plus four
    # world names at 440x130, plus the rebirth sign, all rendered at once and
    # written across each other — the whole middle of the screen was overlapping
    # text and none of it was readable.
    #
    # Two rules, both measurable: every sign must stop drawing at some point,
    # and standing at spawn must not put many of them on screen together.
    signs = []
    stack = [mock["workspace"]]
    while stack:
        node = stack.pop()
        for c in node["GetChildren"](node).values():
            if str(c._p.ClassName) == "BillboardGui":
                sz = c._p.Size
                w = (sz["X"]["Offset"] or 0) if sz is not None else 0
                h = (sz["Y"]["Offset"] or 0) if sz is not None else 0
                pos = node["Position"]
                signs.append({
                    "name": str(node._p.Name),
                    "dist": float(c._p.MaxDistance or 0),
                    "area": w * h,
                    "x": float(pos.X) if pos is not None else 0.0,
                    "z": float(pos.Z) if pos is not None else 0.0,
                })
            stack.append(c)

    forever = [s for s in signs if s["dist"] <= 0]
    if forever:
        bad += 1
        print("  x   %d sign(s) draw from anywhere on the map: %s"
              % (len(forever), ", ".join(sorted({s["name"] for s in forever}))))
    else:
        print("  ok  all %d world signs stop drawing at a distance" % len(signs))

    # Standing at spawn (0,0), how many signs are in range at once?
    import math as _math
    at_spawn = [s for s in signs
                if _math.hypot(s["x"], s["z"]) <= s["dist"]]
    # Area is a decent proxy for "how much of the screen this eats".
    screen = sum(s["area"] for s in at_spawn)
    if len(at_spawn) > 4 or screen > 400000:
        bad += 1
        print("  x   standing at spawn puts %d sign(s) on screen at once "
              "(%d px of text) — they overlap into one unreadable pile"
              % (len(at_spawn), screen))
        for s in sorted(at_spawn, key=lambda v: -v["area"])[:6]:
            print("        %-16s %d px, visible from %d studs"
                  % (s["name"], s["area"], s["dist"]))
    else:
        print("  ok  spawn sees %d sign(s) at once, %d px of text"
              % (len(at_spawn), screen))

    print("\nmap: %d checks failed" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
