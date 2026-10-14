#!/usr/bin/env python3
"""Pets enter an inventory through one door, and the Index never forgets.

TWO FAULTS THIS LOCKS DOWN

1. THE INVENTORY CAP WAS ENFORCED IN ONE PATH OUT OF NINE.

   Eleven places did `table.insert(data.Pets, ...)` — eggs, fusion, codes,
   events, the merchant, quests, gamepasses, trading and two admin commands,
   across nine files. Only EggService checked MaxPetsInInventory. Every other
   route let a player walk straight past it, which is a balance number and also
   a performance one, because each equipped pet is a model the server
   replicates to everybody.

2. THE PET INDEX COUNTED WHAT YOU CURRENTLY HOLD.

   Fuse three pets and the species vanishes from your collection. Trade one
   away, same. Delete one, same. A collection record that forgets what you
   collected is not a collection record — and there was nowhere to write "seen
   it" even if you wanted to, because nothing sat between a pet and the
   inventory.

Both are now properties of a single function, so this checks that function and
then checks that nothing bypasses it.
"""
import re
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
        task = { spawn=function() end, wait=function() return .03 end,
                 delay=function() end, defer=function() end }
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
    bad = [n for n, v in mods.items() if v is None]
    if bad:
        raise SystemExit("modules failed to load: " + ", ".join(bad))
    return lua, mock, cfg, mods


def main():
    lua, mock, cfg, mods = runtime()
    DM, Pets = mods["DataManager"], mods["PetService"]
    fails = []

    p = mock["newInst"]("Player"); p.Name = "Tester"; p.UserId = 555
    res = DM.LoadPlayer(p)
    data = res[0] if isinstance(res, tuple) else res
    cap = int(cfg.Settings.MaxPetsInInventory)

    # --- THE CAP ------------------------------------------------------------
    granted = 0
    for i in range(cap + 25):
        got = Pets.GrantPet(p, lua.table_from({"name": "ant", "rarity": "Common"}))
        got = got[0] if isinstance(got, tuple) else got
        if got is not None:
            granted += 1
    print("cap %d: %d of %d grants accepted, inventory holds %d"
          % (cap, granted, cap + 25, len(data.Pets)))
    if len(data.Pets) > cap:
        fails.append("the inventory cap was ignored: %d pets held, cap is %d"
                     % (len(data.Pets), cap))
    else:
        print("  ok  the cap holds")

    # force=true is for a pet already paid for or already owned; it must still
    # work, or a fusion would consume three pets and deliver nothing.
    forced = Pets.GrantPet(p, lua.table_from({"name": "bee", "rarity": "Rare"}), True)
    forced = forced[0] if isinstance(forced, tuple) else forced
    if forced is None:
        fails.append("force grants are refused at the cap — a fusion would eat "
                     "three pets and give nothing back")
    else:
        print("  ok  a forced grant still lands (fusions and paid items survive)")

    # --- THE INDEX REMEMBERS ------------------------------------------------
    before = int(Pets.DiscoveredCount(data))
    # Wipe the entire inventory, the way fusing and trading everything would.
    lua.execute("function WIPE(d) d.Pets = {} end")
    lua.globals().WIPE(data)
    after = int(Pets.DiscoveredCount(data))
    print("discovered %d species; after losing EVERY pet, still %d" % (before, after))
    if after < before:
        fails.append("the Pet Index forgot %d species when the pets left the "
                     "inventory — fusing or trading erases your collection"
                     % (before - after))
    else:
        print("  ok  the collection record survives losing the pets")

    # --- NOTHING BYPASSES THE DOOR -----------------------------------------
    # A static sweep, because this is a rule about the whole codebase and a
    # runtime test can only see the paths it happens to exercise.
    offenders = []
    for f in sorted(ROOT.glob("src/Server/*.lua")):
        if f.name == "PetService.lua":
            continue            # the door itself
        for n, line in enumerate(f.read_text().splitlines(), 1):
            if re.search(r"table\.insert\(\s*\w*\.?\w*Pets\s*,", line) \
                    and "EquippedPets" not in line:
                offenders.append("%s:%d" % (f.name, n))
    if offenders:
        fails.append("%d place(s) still insert into an inventory directly, "
                     "skipping the cap and the Index: %s"
                     % (len(offenders), ", ".join(offenders)))
    else:
        print("  ok  every grant in src/Server goes through PetService.GrantPet")

    # --- EVERY PET THE GAME NAMES IS A PET THE GAME HAS ----------------------
    # The merchant and both event shops sold pets that were not in the roster
    # — names from before it was replaced with the imported models — so a
    # player paid up to 12,000 gems for a pet with no model, no earnings and
    # no place in the Index. Every name anywhere in the config is checked
    # against the roster, with its stated rarity.
    roster = {str(x.name): str(x.rarity) for x in cfg.Pets.values()}
    named = []
    for it in cfg.MerchantPool.values():
        if str(it.kind) == "pet":
            named.append(("merchant", it.name, it.rarity))
    for eid, ev in cfg.Events.items():
        for it in ev.shop.values():
            if str(it.kind) == "pet":
                named.append(("event %s" % eid, it.name, it.rarity))
    for group in ("Quests", "DailyQuests"):
        for q in (cfg[group].values() if cfg[group] is not None else []):
            if q.reward is not None and q.reward.pet is not None:
                named.append(("quest %s" % q.id, q.reward.pet, q.reward.petRarity))
    for code, r in cfg.Codes.items():
        if r.pet is not None:
            named.append(("code %s" % code, r.pet, r.petRarity))
    gp_src = (ROOT / "src/Server/GamepassService.lua").read_text()
    for m in re.finditer(r'newPet\s*=\s*\{\s*name\s*=\s*"([^"]+)"\s*,\s*rarity\s*=\s*"([^"]+)"', gp_src):
        named.append(("VIP pass", m.group(1), m.group(2)))
    bad_names = ["%s sells %r, which is not a pet in the game" % (w, str(n))
                 for w, n, _ in named if str(n) not in roster]
    bad_rarity = ["%s calls %s %s, but it is %s" % (w, n, r, roster[str(n)])
                  for w, n, r in named
                  if str(n) in roster and r is not None and str(r) != roster[str(n)]]
    if bad_names or bad_rarity:
        fails.append("; ".join((bad_names + bad_rarity)[:6]))
    else:
        print("  ok  all %d pets named in shops, quests, codes and passes exist, "
              "at their real rarity" % len(named))

    # --- A SHOP NEVER CHARGES FOR A PET IT CANNOT GIVE -----------------------
    MS, ES = mods["MerchantService"], mods["EventService"]
    while len(data.Pets) < cap:                         # full, from here on
        Pets.GrantPet(p, lua.table_from({"name": "ant", "rarity": "Common"}))
    data.Gems = 10 ** 9
    data.EventTokens = 10 ** 6
    pet_slot = None
    for _ in range(80):
        MS.ForceSpawn()
        stock = MS.GetState().stock
        for i, it in stock.items():
            if str(it.kind) == "pet":
                pet_slot = (i, it)
                break
        if pet_slot:
            break

    def outcome(r):
        return (r[0], str(r[1])) if isinstance(r, tuple) else (r, "")

    if pet_slot is None:
        fails.append("the merchant never stocked a pet in 80 visits")
    else:
        i, it = pet_slot
        gems = int(data.Gems)
        ok, why = outcome(MS.Buy(p, i))
        if ok or int(data.Gems) != gems:
            fails.append("the merchant took %d gems for a %s with the inventory full"
                         % (gems - int(data.Gems), it.name))
        else:
            data.Pets[len(data.Pets)] = None              # make room
            ok, why = outcome(MS.Buy(p, i))
            got = data.Pets[len(data.Pets)]
            if not ok or str(got.name) != str(it.name) or str(got.rarity) != roster.get(str(it.name)):
                fails.append("with room, the merchant's %s arrived as %s (%s): %s"
                             % (it.name, got and got.name, got and got.rarity, why))
            elif gems - int(data.Gems) != int(it.cost):
                fails.append("the merchant charged %d for a %d-gem pet"
                             % (gems - int(data.Gems), int(it.cost)))
            else:
                print("  ok  merchant: full inventory refused, nothing taken; with "
                      "room, a %s %s for %d gems" % (got.rarity, got.name, int(it.cost)))

    ES.Start("summer")
    ev_pet = [(i, it) for i, it in cfg.Events["summer"].shop.items() if str(it.kind) == "pet"][0]
    i, it = ev_pet
    tokens = int(data.EventTokens)
    ok, why = outcome(ES.Buy(p, i))
    if ok or int(data.EventTokens) != tokens:
        fails.append("the event shop took %d tokens for a %s with the inventory full"
                     % (tokens - int(data.EventTokens), it.name))
    else:
        data.Pets[len(data.Pets)] = None
        ok, why = outcome(ES.Buy(p, i))
        got = data.Pets[len(data.Pets)]
        if not ok or str(got.name) != str(it.name):
            fails.append("with room, the event's %s did not arrive (%s)" % (it.name, why))
        else:
            print("  ok  event shop: full inventory refused, nothing taken; with "
                  "room, a %s %s" % (got.rarity, got.name))

    if fails:
        print("\npets: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\npets: one door in, and the Index never forgets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
