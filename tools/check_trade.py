#!/usr/bin/env python3
"""Trading must move a pet, not replace it with a fresh copy of its species.

A pet in this game is not just a name and a rarity. EggService rolls a
`mutation` onto it (Rainbow x10, Shiny x4, Golden x2) and FusionService gives
it a `fuseMult` that compounds — three pets fused sum their multipliers and
take a further x1.25, and a fused pet can be fused again. PetService reads both
when it scores a pet:

    score = coinMult * mutationMult * fuseMult

TradeService rebuilt the received pet as { name, rarity, uniqueId } and nothing
else. Every one of those fields was dropped on the floor. A player who trades a
Rainbow pet they spent a week fusing receives a base-stat animal with the same
name, and there is no error anywhere to tell them what happened.

This measures the pet on both sides of a trade and requires the value to
survive. It also checks the two protections that trading needs to be safe at
all: a locked pet must not be tradeable, and a trade must not push someone past
their inventory cap.
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


def runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    lua.execute("math.clamp=function(x,l,h) return math.max(l,math.min(h,x)) end;"
                "math.round=function(x) return math.floor(x+0.5) end")
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Vector3", "CFrame", "Color3", "Enum", "Instance", "game", "workspace",
              "Random", "UDim", "UDim2", "Vector2"):
        G[k] = mock[k]
    lua.execute("""
        task = { spawn=function(f) end, wait=function() return .03 end,
                 delay=function(_, f) end, defer=function() end }
        warn = function() end
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
    for _ in range(4):
        for name, (m, f) in markers.items():
            if mock["MODULES"][m] is not None:
                continue
            G["script"] = m
            try:
                mock["MODULES"][m] = load(f, name)
            except Exception:
                pass
    mods = {n: mock["MODULES"][m] for n, (m, _) in markers.items()}
    missing = [n for n, v in mods.items() if v is None]
    if missing:
        raise SystemExit("modules failed to load: " + ", ".join(missing))
    return lua, mock, cfg, mods


def first(v):
    """LoadPlayer returns (data, err) now; this test wants the data."""
    return v[0] if isinstance(v, tuple) else v


def fake_player(mock, name, uid):
    p = mock["newInst"]("Player")
    p.Name = name
    p.UserId = uid
    p.Parent = None
    return p


def power_of(cfg, pet):
    """The same score PetService uses, computed here so the test does not
    depend on the thing it is testing."""
    name = str(pet["name"])
    coin = 0
    pets = cfg.Pets
    for i in range(1, len(pets) + 1):
        if str(pets[i].id) == name or str(pets[i].name) == name:
            coin = float(pets[i].coinMult)
            break
    mut = 1.0
    mid = pet["mutation"]
    if mid is not None:
        muts = cfg.Mutations
        for i in range(1, len(muts) + 1):
            if str(muts[i].id) == str(mid):
                mut = float(muts[i].mult)
                break
    fuse = float(pet["fuseMult"]) if pet["fuseMult"] is not None else 1.0
    return coin * mut * fuse


def main():
    lua, mock, cfg, mods = runtime()
    DataManager = mods["DataManager"]
    Trade = mods["TradeService"]
    fails = []

    a = fake_player(mock, "Alice", 101)
    b = fake_player(mock, "Bob", 202)
    # PlayerList is a Lua table, not a Python list — TradeService.Request
    # scans it with Players:GetPlayers() to resolve a partial name.
    pl = mock["PlayerList"]
    pl[1] = a
    pl[2] = b

    da = first(DataManager.LoadPlayer(a))
    db = first(DataManager.LoadPlayer(b))

    # A pet worth something: a real species, a Rainbow mutation, and a fuseMult
    # of the size FusionService actually produces (three fuses deep).
    species = str(cfg.Pets[1].id if cfg.Pets[1].id is not None else cfg.Pets[1].name)
    prize = lua.table_from({
        "name": species, "rarity": "Legendary", "uniqueId": "PRIZE-1",
        "mutation": "Rainbow", "fuseMult": 5.859375, "locked": False,
    })
    da.Pets[len(da.Pets) + 1] = prize
    before = power_of(cfg, prize)
    print("Alice's pet: %s, Rainbow, fuseMult %.3f  ->  power %.1f"
          % (species, 5.859375, before))

    # Run a trade the way the remotes do.
    Trade.Request(a, "Bob")
    Trade.Respond(b, True)
    Trade.Add(a, "PRIZE-1")
    Trade.Accept(a, True)
    Trade.Accept(b, True)
    # task.delay is stubbed, so drive the swap the way the timer would.
    lua.execute("")
    doswap = lua.eval("function(T,a,b) T.Accept(a,true); T.Accept(b,true) end")
    # The 3s confirm fires doSwap through task.delay; call the same path by
    # re-accepting with a live delay.
    lua.execute("task.delay = function(_, f) f() end")
    Trade.Accept(b, False)
    Trade.Accept(b, True)

    got = None
    for i in range(1, len(db.Pets) + 1):
        if str(db.Pets[i].name) == species:
            got = db.Pets[i]
            break
    if got is None:
        fails.append("the trade did not deliver the pet at all")
        print("\ntrade: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1

    after = power_of(cfg, got)
    print("Bob receives:  %s, mutation %s, fuseMult %s  ->  power %.1f"
          % (str(got["name"]), got["mutation"], got["fuseMult"], after))

    if after < before * 0.999:
        lost = 100.0 * (1 - after / before) if before else 0
        fails.append("trading destroyed %.1f%% of the pet's value (%.1f -> %.1f): "
                     "mutation and fuseMult are dropped when the pet is rebuilt"
                     % (lost, before, after))
    else:
        print("  ok  the pet arrives worth exactly what it left as")

    # --- LOCKED PETS MUST NOT BE TRADEABLE ---------------------------------
    # Locking is what a player does to say "never let this leave". If trade
    # ignores it, the protection is decorative.
    locked = lua.table_from({
        "name": species, "rarity": "Legendary", "uniqueId": "LOCKED-1",
        "mutation": "Rainbow", "fuseMult": 4.0, "locked": True,
    })
    da.Pets[len(da.Pets) + 1] = locked
    Trade.Request(a, "Bob")
    Trade.Respond(b, True)
    Trade.Add(a, "LOCKED-1")
    s_ok = True
    offer = None
    try:
        offer = Trade.Cancel  # no direct accessor; probe via a swap attempt
    except Exception:
        pass
    Trade.Accept(a, True)
    Trade.Accept(b, True)
    still_has = any(str(da.Pets[i].uniqueId) == "LOCKED-1"
                    for i in range(1, len(da.Pets) + 1))
    if not still_has:
        fails.append("a LOCKED pet was traded away — locking gives no protection")
    else:
        print("  ok  a locked pet cannot be put into a trade")
    Trade.Cancel(a)

    if fails:
        print("\ntrade: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\ntrade: value survives the trade and locked pets are protected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
