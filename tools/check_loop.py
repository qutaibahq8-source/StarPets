#!/usr/bin/env python3
"""Play the game: join, hatch, equip, earn, buy the next egg.

Every other check here proves a part in isolation. None of them proves the
GAME works — that a new player can actually get from nothing to earning, which
is the only path that matters, because if it is broken nothing downstream of it
is ever reached.

It has been broken before in ways no unit check would show. A hatched pet that
is never auto-equipped gives an income of zero, so the player can never afford
the second egg, so they never see anything past the first minute. The eggs
hatch, the pets are real, the money is correct, and the game is unplayable.

The loop, in order:
  1. a new player joins and gets their starting data
  2. they hatch the first egg
  3. the pet is really in their inventory, with a species the egg can give
  4. equipping it produces income above zero
  5. that income can actually reach the price of the next egg
  6. hatching repeatedly never produces a pet from the wrong pool
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_map  # noqa: E402


def num(v):
    """GetPlayerIncome returns more than one value; take the first."""
    if isinstance(v, tuple):
        v = v[0] if v else 0
    return float(v or 0)


def lua_list(t):
    out, i = [], 1
    while t[i] is not None:
        out.append(t[i]); i += 1
    return out


def main():
    lua, mock, cfg = check_map.build()
    G = lua.globals()
    fails = []

    # Reach the services the running server loaded, so this exercises exactly
    # what the game uses rather than a second copy loaded differently.
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    def mod(name):
        m = holder["FindFirstChild"](holder, name)
        return mock["MODULES"][m]
    DM, Eggs, Pets = mod("DataManager"), mod("EggService"), mod("PetService")

    p = mock["newInst"]("Player"); p.Name = "Newbie"; p.UserId = 12345
    mock["PlayerList"][1] = p
    res = DM.LoadPlayer(p)
    data = res[0] if isinstance(res, tuple) else res
    if data is None:
        print("   x a new player could not be loaded at all")
        return 1
    print("1. joined: %d coins, %d pets" % (int(data.Coins), len(data.Pets)))

    # --- 2/3. HATCH THE FIRST EGG ------------------------------------------
    eggs = lua_list(cfg.Eggs)
    first = eggs[0]
    egg_id = str(first.id)
    # The field is `cost`, not `price`. Reading the wrong name gave 0 for every
    # egg, so the affordability step below compared against nothing and passed
    # no matter what the real prices were.
    def cost_of(e):
        v = e.cost if e.cost is not None else e.price
        return int(v or 0)
    price = cost_of(first)
    # Enough to afford it outright, so this does not quietly depend on the
    # starter egg being free.
    data.Coins = max(price * 3, 1000)
    before = len(data.Pets)
    got, err = None, None
    r = Eggs.HatchEgg(p, egg_id)
    if isinstance(r, tuple):
        got, err = r[0], (r[1] if len(r) > 1 else None)
    else:
        got = r
    after = len(data.Pets)
    print("2. hatched %s: inventory %d -> %d%s"
          % (egg_id, before, after, ("  (%s)" % err) if err else ""))
    if after != before + 1:
        fails.append("hatching the first egg did not add a pet to the "
                     "inventory (%d -> %d, %s)" % (before, after, err))
        for f in fails:
            print("   x " + f)
        return 1

    pet = data.Pets[after]
    species = str(pet.name)
    pool = {str(x) for x in lua_list(first.pets)} if first.pets is not None else set()
    if pool and species not in pool:
        fails.append("the first egg produced %r, which is not in its own pet "
                     "pool — the hatch is reading the wrong table" % species)
    else:
        print("3. got %s (%s), in the egg's own pool" % (species, str(pet.rarity)))

    # --- 4. EQUIPPING MUST PRODUCE INCOME ----------------------------------
    # This is the step that has been silently broken: hatch works, the pet is
    # real, and income stays at zero because nothing equipped it.
    income_before = num(Pets.GetPlayerIncome(p))
    Pets.EquipPet(p, pet.uniqueId)
    income_after = num(Pets.GetPlayerIncome(p))
    print("4. income before equipping: %.2f/sec, after: %.2f/sec"
          % (income_before, income_after))
    if income_after <= 0:
        fails.append("a player with an equipped pet earns NOTHING per second — "
                     "they can never afford a second egg and the game stops "
                     "after the first minute")
    elif income_after <= income_before:
        fails.append("equipping a pet did not change income (%.2f -> %.2f)"
                     % (income_before, income_after))
    else:
        print("   ok  equipping a pet earns money")

    # --- 5. THE NEXT EGG MUST BE REACHABLE ---------------------------------
    if len(eggs) > 1 and income_after > 0:
        second = eggs[1]
        cost = cost_of(second)
        secs = cost / income_after
        print("5. next egg (%s) costs %d = %.0f seconds of income"
              % (str(second.id), cost, secs))
        if secs > 3600:
            fails.append("the second egg is %.0f MINUTES of income away with "
                         "one starting pet — that is not a difficulty curve, "
                         "it is a wall" % (secs / 60))
        else:
            print("   ok  the next step is reachable")

    # --- 6. REPEATED HATCHES STAY IN THEIR POOL ----------------------------
    # A pool that leaks gives away endgame pets from the starter egg, which
    # destroys progression quietly and permanently.
    strays = {}
    data.Coins = max(price * 400, 10 ** 9)
    for _ in range(120):
        n0 = len(data.Pets)
        Eggs.HatchEgg(p, egg_id)
        if len(data.Pets) > n0:
            nm = str(data.Pets[len(data.Pets)].name)
            if pool and nm not in pool:
                strays[nm] = strays.get(nm, 0) + 1
    if strays:
        fails.append("120 hatches of the starter egg produced %d pet(s) from "
                     "outside its pool: %s"
                     % (sum(strays.values()), ", ".join(sorted(strays))))
    else:
        print("6. 120 more hatches, every pet from the egg's own pool")

    if fails:
        print("\nloop: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\nloop: a new player can join, hatch, equip, earn and progress")
    return 0


if __name__ == "__main__":
    sys.exit(main())
