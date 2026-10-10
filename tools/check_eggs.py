#!/usr/bin/env python3
"""Eggs: what they cost, what they give, and what they take when they fail.

Two bugs that shipped, and one gap in the game's design.

THE STARTER EGG TOOK 150 COINS FOR NOTHING. HatchEgg charged first and checked
for a full inventory after, then refunded eggConfig.cost — not what had been
charged. For the Starter Egg those differ (150 charged, cost field 0), so every
click with a full inventory took 150 coins and returned nothing.

A REFUSED PET WAS STILL "HATCHED". GrantPet's answer was ignored. When it
refused, the coins were already gone, EggsHatched still went up, and the pet
was handed to the client as if it existed — the player watched a reveal for a
pet that never reached their inventory.

THE LATE GAME HAD NOTHING TO BUY. The coin eggs stopped at 20,000 while the
worlds cost up to 200,000,000, and every egg drew from the same pool, so a new
world brought no new pets. Each world now has its own egg, priced on its own
economy, drawing only from its own animals, refused until the world is owned.
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

FAILURES = []
WORLD_ORDER = ["Forest", "Desert", "Volcano", "Space"]


def check(label, fn):
    try:
        print("   ok  %-36s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-36s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-36s crashed: %r" % (label, e))
        FAILURES.append(label)


def lst(t):
    out, i = [], 1
    while t is not None and t[i] is not None:
        out.append(t[i])
        i += 1
    return out


class Game:
    def __init__(self):
        self.lua, self.mock, self.cfg = check_map.build()
        sss = self.mock["ServerScriptService"]
        self.holder = sss["FindFirstChild"](sss, "Server", True)
        self.n = 0

    def mod(self, name):
        return self.mock["MODULES"][self.holder["FindFirstChild"](self.holder, name)]

    def player(self, coins=0, gems=0, areas=("Meadow",)):
        self.n += 1
        p = self.mock["newInst"]("Player")
        p.Name = "P%d" % self.n
        p.UserId = 6000 + self.n
        self.mock["PlayerList"][self.n] = p
        res = self.mod("DataManager").LoadPlayer(p)
        d = res[0] if isinstance(res, tuple) else res
        d.Coins = coins
        d.Gems = gems
        d.UnlockedAreas = self.lua.table_from(list(areas))
        return p, d

    def hatch(self, p, egg_id):
        r = self.mod("EggService").HatchEgg(p, egg_id)
        if isinstance(r, tuple):
            return r[0], (r[1] if len(r) > 1 else None)
        return r, None


def main():
    g = Game()
    eggs = {str(e.id): e for e in lst(g.cfg.Eggs)}
    species = {str(p.name): p for p in lst(g.cfg.Pets)}
    count = g.lua.eval("function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end")

    def t_weights_sum():
        bad = []
        for eid, e in eggs.items():
            w = e.rarityWeights
            total = sum(float(w[k] or 0) for k in
                        ("Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"))
            if abs(total - 10000) > 0.5:
                bad.append("%s=%d" % (eid, total))
        assert not bad, "rarity weights do not sum to 10000: %s" % bad
        return "all %d eggs sum to 10000" % len(eggs)

    def t_every_world_has_an_egg():
        have = {str(e.world) for e in eggs.values() if e.world is not None}
        missing = [w for w in WORLD_ORDER if w not in have]
        assert not missing, "no egg for %s" % missing
        return "Forest, Desert, Volcano and Space each have one"

    def t_prices_climb():
        prices = []
        for w in WORLD_ORDER:
            e = [x for x in eggs.values() if str(x.world) == w][0]
            prices.append((w, float(e.cost)))
        rising = all(prices[i][1] < prices[i + 1][1] for i in range(len(prices) - 1))
        assert rising, "world eggs do not get dearer world by world: %s" % prices
        best_coin = max(float(e.cost) for e in eggs.values()
                        if str(e.currency) == "Coins" and e.world is None)
        assert prices[0][1] > best_coin, (
            "the first world egg (%d) is no dearer than the spawn eggs (%d) — "
            "the late game still has nothing to buy" % (prices[0][1], best_coin))
        return " < ".join("%s %s" % (w, f"{int(c):,}") for w, c in prices)

    def t_pools_are_real():
        bad = []
        for eid, e in eggs.items():
            for name in lst(e.pool):
                if str(name) not in species:
                    bad.append("%s -> %s" % (eid, name))
        assert not bad, "pool entries that are not species: %s" % bad
        return "every pool entry is a real species"

    def t_world_eggs_stay_in_their_pool():
        """2,000 hatches per world egg; every one must come from its pool."""
        out = []
        for w in WORLD_ORDER:
            e = [x for x in eggs.values() if str(x.world) == w][0]
            pool = {str(n) for n in lst(e.pool)}
            p, d = g.player(coins=1e15, areas=["Meadow"] + WORLD_ORDER)
            got, strays = set(), set()
            for _ in range(2000):
                if count(d.Pets) >= 95:
                    d.Pets = g.lua.eval("{}")
                pet, err = g.hatch(p, str(e.id))
                assert pet is not None, "%s refused a hatch it should allow: %s" % (w, err)
                nm = str(pet.name)
                got.add(nm)
                if nm not in pool:
                    strays.add(nm)
            assert not strays, "%s egg gave animals from outside its pool: %s" % (
                w, sorted(strays))
            out.append("%s %d/%d" % (w, len(got), len(pool)))
        return "all from their own pools (" + ", ".join(out) + " species seen)"

    def t_locked_world_refused_and_free():
        p, d = g.player(coins=1e12)
        before = float(d.Coins)
        pet, err = g.hatch(p, "VolcanoEgg")
        assert pet is None, "a Volcano egg hatched for a player who does not own the Volcano"
        assert "Volcano" in str(err), err
        assert float(d.Coins) == before, "a refused locked egg still charged %d coins" % (
            before - float(d.Coins))
        return "refused, nothing charged"

    def t_full_inventory_costs_nothing():
        """The 150-coin bug."""
        p, d = g.player(coins=10000)
        d.HasClaimedFreeEgg = True
        cap = int(g.cfg.Settings.MaxPetsInInventory)
        d.Pets = g.lua.table_from([g.lua.table_from({"name": "cat", "rarity": "Common",
                                                     "uniqueId": "x%d" % i})
                                   for i in range(cap)])
        before = float(d.Coins)
        for _ in range(5):
            pet, _err = g.hatch(p, "StarterEgg")
            assert pet is None, "hatched past the inventory cap"
        lost = before - float(d.Coins)
        assert lost == 0, ("five clicks on the Starter Egg with a full inventory "
                           "cost %d coins and gave nothing" % lost)
        return "five refused clicks, 0 coins taken"

    def t_free_egg_survives_a_refusal():
        p, d = g.player(coins=0)
        cap = int(g.cfg.Settings.MaxPetsInInventory)
        d.Pets = g.lua.table_from([g.lua.table_from({"name": "cat", "rarity": "Common",
                                                     "uniqueId": "y%d" % i})
                                   for i in range(cap)])
        g.hatch(p, "StarterEgg")
        assert not d.HasClaimedFreeEgg, ("the one free egg per account was used up "
                                         "by a hatch that was refused")
        return "still unclaimed after a refusal"

    def t_refused_grant_is_not_a_hatch():
        """The ghost-pet bug: GrantPet refuses for a reason HatchEgg did not foresee."""
        PS = g.mod("PetService")
        real = PS.GrantPet
        PS.GrantPet = g.lua.eval('function() return nil, "refused for the test" end')
        try:
            p, d = g.player(coins=50000)
            before_coins, before_hatched = float(d.Coins), float(d.EggsHatched or 0)
            pet, err = g.hatch(p, "CoolEgg")
        finally:
            PS.GrantPet = real
        assert pet is None, ("a pet GrantPet refused was handed back as hatched — "
                             "the player sees a reveal for a pet they do not have")
        assert float(d.Coins) == before_coins, "charged %d for a pet that was refused" % (
            before_coins - float(d.Coins))
        assert float(d.EggsHatched or 0) == before_hatched, \
            "EggsHatched went up for a hatch that did not happen"
        return "no pet, no charge, no hatch counted"

    def t_normal_hatch_still_charges():
        p, d = g.player(coins=5000)
        pet, err = g.hatch(p, "CoolEgg")
        assert pet is not None, "an ordinary affordable hatch failed: %s" % err
        assert float(d.Coins) == 5000 - float(eggs["CoolEgg"].cost), \
            "charged %d, not the egg's %d" % (5000 - float(d.Coins), float(eggs["CoolEgg"].cost))
        return "charged exactly once, after the pet was in"

    def t_every_egg_has_a_stand():
        ws = g.mock["workspace"]
        names = {str(x._p.Name) for x in ws["GetDescendants"](ws).values()}
        missing = [eid for eid in eggs if ("Egg_" + eid) not in names]
        assert not missing, "no stand in the world for: %s" % missing
        return "all %d eggs stand somewhere a player can click" % len(eggs)

    print("eggs:")
    check("weights sum to 10000", t_weights_sum)
    check("every world has an egg", t_every_world_has_an_egg)
    check("world eggs get dearer", t_prices_climb)
    check("pools name real species", t_pools_are_real)
    check("world eggs stay in their pool", t_world_eggs_stay_in_their_pool)
    check("locked world: refused, not charged", t_locked_world_refused_and_free)
    check("full inventory costs nothing", t_full_inventory_costs_nothing)
    check("free egg survives a refusal", t_free_egg_survives_a_refusal)
    check("a refused pet is not a hatch", t_refused_grant_is_not_a_hatch)
    check("a normal hatch still charges", t_normal_hatch_still_charges)
    check("every egg has a stand", t_every_egg_has_a_stand)

    def t_ids_never_repeat():
        # Ids were a random six-digit number plus the clock's last four
        # digits, so pets hatched in the same second differed only by chance:
        # 3,000 of them would expect about five duplicates. Equip, delete and
        # trade all find a pet by id.
        p, d = g.player(coins=10 ** 12)
        seen, dupes = set(), 0
        for _ in range(30):
            for _ in range(100):
                pet, _err = g.hatch(p, "CoolEgg")
                if pet is None:
                    break
                uid = str(pet.uniqueId)
                dupes += uid in seen
                seen.add(uid)
            for k in list(d.Pets.keys()):
                d.Pets[k] = None
        assert len(seen) >= 2900, "only %d pets hatched" % len(seen)
        assert dupes == 0, "%d of %d hatched pets reused an id" % (dupes, len(seen) + dupes)
        return "%d hatches, every id different" % len(seen)

    check("pet ids never repeat", t_ids_never_repeat)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\neggs: every world has one, and a failed hatch costs nothing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
