#!/usr/bin/env python3
"""Play a whole session and come back: join, change everything, leave, rejoin.

Every other data check here proves one failure mode in isolation. This one
walks the path a real player walks, because that is where state gets dropped —
not in a function, but in the handover between joining, changing, saving and
loading again.

  1. JOIN            the real PlayerAdded handler, not a hand-made table
  2. CHANGE          coins, gems, pets, equipped, worlds, upgrades, quests
  3. LEAVE           the real PlayerRemoving handler: save, despawn, evict
  4. REJOIN          every value must come back exactly as it was
  5. TWO PLAYERS     at once, with no leakage between them
  6. NOTHING LEFT    a server that has cycled many players must not still be
                     doing work for any of them

Point 6 is a bug this found: DespawnAllPets set ActiveModels[userId] to an
empty table instead of removing it, so every player who ever joined stayed in
the table the follow loop walks sixty times a second — a server that gets
slower the longer it runs, with nothing in Output to say why.
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


def check(label, fn):
    try:
        print("   ok  %-36s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-36s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-36s crashed: %r" % (label, e))
        FAILURES.append(label)


class Server:
    def __init__(self):
        self.lua, self.mock, self.cfg = check_map.build()
        # Spawned threads run inline so a save started in one is finished by
        # the time we look; a stub that drops them would report a clean save
        # that never happened.
        self.lua.execute("""
            task = task or {}
            task.spawn = function(f, ...) if f then pcall(f, ...) end end
            task.defer = task.spawn
            task.delay = function(_, f, ...) end
            task.wait  = function() return 0 end
        """)
        sss = self.mock["ServerScriptService"]
        self.holder = sss["FindFirstChild"](sss, "Server", True)
        self.count = self.lua.eval(
            "function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end")
        self.seat = 0

    def mod(self, name):
        inst = self.holder["FindFirstChild"](self.holder, name)
        return self.mock["MODULES"][inst] if inst is not None else None

    def join(self, uid, name):
        p = self.mock["newInst"]("Player")
        p.Name = name
        p.UserId = uid
        char = self.mock["newInst"]("Model")
        char.Name = name
        root = self.mock["newInst"]("Part")
        root.Name = "HumanoidRootPart"
        root.Parent = char
        hum = self.mock["newInst"]("Humanoid")
        hum.Name = "Humanoid"
        hum.Parent = char
        p.Character = char
        self.seat += 1
        self.mock["PlayerList"][self.seat] = p
        # The real join path.
        self.mock["Players"].PlayerAdded.Fire(None, p)
        return p, self.mod("DataManager").GetData(p)

    def leave(self, p):
        self.mock["Players"].PlayerRemoving.Fire(None, p)
        for i in range(1, self.seat + 1):
            if self.mock["PlayerList"][i] is p:
                self.mock["PlayerList"][i] = None


def snapshot(srv, data):
    def num(v):
        try:
            return round(float(v or 0), 4)
        except (TypeError, ValueError):
            return 0.0
    pets = []
    i = 1
    while data.Pets[i] is not None:
        pet = data.Pets[i]
        pets.append((str(pet.name), str(pet.rarity), str(pet.uniqueId),
                     str(pet.mutation or ""), num(pet.fuseMult)))
        i += 1
    return {
        "Coins": num(data.Coins),
        "Gems": num(data.Gems),
        "EggsHatched": num(data.EggsHatched),
        "Rebirths": num(data.Rebirths),
        "pets": sorted(pets),
        "equipped": srv.count(data.EquippedPets),
        "areas": srv.count(data.UnlockedAreas),
        "upgrades": srv.count(data.Upgrades),
        "discovered": srv.count(data.Discovered),
    }


def main():
    srv = Server()
    PS, DM = srv.mod("PetService"), srv.mod("DataManager")
    print("one player, a full session:")

    alice, data = srv.join(7001, "Alice")
    assert data is not None, "the join handler produced no data"

    # ---- 2. change everything ------------------------------------------
    data.Coins = 1234567
    data.Gems = 8910
    data.EggsHatched = 42
    for i in range(6):
        PS.GrantPet(alice, srv.lua.eval(
            '{name="Bunny", rarity="Common", uniqueId="alice-%d", '
            'mutation="Golden", fuseMult=3.5}' % i))
    srv.mod("PetService").EquipPet(alice, "alice-0")
    srv.mod("PetService").EquipPet(alice, "alice-1")
    data.UnlockedAreas[2] = "Forest"
    data.Upgrades["CoinBonus"] = 2
    data.Upgrades["LuckyCharm"] = 1

    before = snapshot(srv, data)

    def t_join_gave_real_data():
        assert before["pets"], "GrantPet put nothing in the inventory"
        return "%d pets, %d coins, %d areas" % (
            len(before["pets"]), before["Coins"], before["areas"])

    def t_leave_and_rejoin():
        srv.leave(alice)
        assert DM.GetData(alice) is None, \
            "the player's data was still cached after they left"
        alice2, data2 = srv.join(7001, "Alice")
        assert data2 is not None, "rejoining produced no data"
        after = snapshot(srv, data2)
        diffs = {k: (before[k], after[k]) for k in before if before[k] != after[k]}
        assert not diffs, "these values did not survive the round trip: %s" % diffs
        return "every value identical after leave and rejoin"

    def t_mutations_survive():
        _, data2 = srv.join(7001, "Alice")
        pet = data2.Pets[1]
        assert str(pet.mutation) == "Golden", \
            "the mutation was lost in the save (%s)" % pet.mutation
        assert float(pet.fuseMult) == 3.5, \
            "fuseMult was lost in the save (%s) — that is most of a pet's value" \
            % pet.fuseMult
        return "mutation and fuseMult both came back"

    check("join produces real data", t_join_gave_real_data)
    check("leave then rejoin loses nothing", t_leave_and_rejoin)
    check("mutation and fuseMult survive", t_mutations_survive)

    # ---- 5. two players at once ----------------------------------------
    print("\ntwo players at once:")
    srv2 = Server()
    PS2 = srv2.mod("PetService")
    bob, bdata = srv2.join(8001, "Bob")
    carol, cdata = srv2.join(8002, "Carol")
    bdata.Coins = 500
    cdata.Coins = 999999
    PS2.GrantPet(bob, srv2.lua.eval('{name="Bunny", rarity="Common", uniqueId="bob-1"}'))
    PS2.GrantPet(carol, srv2.lua.eval('{name="Dragon", rarity="Legendary", uniqueId="carol-1"}'))

    def t_no_cross_contamination():
        assert float(bdata.Coins) == 500, "Bob's coins changed to %s" % bdata.Coins
        assert srv2.count(bdata.Pets) == 1, "Bob has %d pets" % srv2.count(bdata.Pets)
        assert str(bdata.Pets[1].uniqueId) == "bob-1", \
            "Bob is holding %s" % bdata.Pets[1].uniqueId
        assert str(cdata.Pets[1].uniqueId) == "carol-1", \
            "Carol is holding %s" % cdata.Pets[1].uniqueId
        return "separate inventories and balances"

    def t_one_leaving_does_not_disturb_the_other():
        srv2.leave(bob)
        assert srv2.mod("DataManager").GetData(carol) is not None, \
            "Carol's data was evicted when Bob left"
        assert float(cdata.Coins) == 999999, "Carol's coins changed to %s" % cdata.Coins
        assert srv2.count(cdata.Pets) == 1, "Carol's inventory changed when Bob left"
        return "Carol untouched by Bob leaving"

    check("no cross-player contamination", t_no_cross_contamination)
    check("one leaving does not touch the other", t_one_leaving_does_not_disturb_the_other)

    # ---- 6. nothing left behind ----------------------------------------
    print("\nafter many sessions:")

    def t_no_residue():
        srv3 = Server()
        PS3 = srv3.mod("PetService")
        for n in range(60):
            p, d = srv3.join(9000 + n, "P%d" % n)
            PS3.GrantPet(p, srv3.lua.eval(
                '{name="Bunny", rarity="Common", uniqueId="p%d-1"}' % n))
            PS3.EquipPet(p, "p%d-1" % n)
            srv3.leave(p)
        players, models = PS3.ActiveCounts()
        assert int(players) == 0, (
            "%d departed player(s) are still in the follow loop's table — it "
            "walks them every Heartbeat forever" % players)
        assert int(models) == 0, "%d pet models were never despawned" % models
        return "60 players joined and left, 0 left in the follow loop"

    check("no residue from departed players", t_no_residue)

    # ---- 7. the leaderboard survives a rebirth --------------------------
    print("\nleaderboard:")

    def t_rank_survives_rebirth():
        srv4 = Server()
        p, d = srv4.join(9500, "Climber")
        d.TotalCoinsEarned = 5000000
        d.Coins = 5000000
        srv4.mod("QuestService").Sync(d)          # as a quest read would
        LB = srv4.mod("LeaderboardService")
        LB.UpdatePlayer(p)
        store = srv4.mock["STORE"]["ord:MysticPets_LB_Coins_v1"]
        keys = [k for k in (store.keys() if store else [])]
        posted_before = float(store["9500"]) if store and store["9500"] else 0.0
        assert posted_before >= 5000000, \
            "the board never received the score (%s, keys %s)" % (posted_before, keys)

        d.TotalCoinsEarned = 1e9
        srv4.mod("RebirthService").DoRebirth(p)
        assert float(d.TotalCoinsEarned) == 0, \
            "rebirth no longer zeroes TotalCoinsEarned; this check is vacuous"
        LB.UpdatePlayer(p)
        posted_after = float(store["9500"]) if store["9500"] else 0.0
        assert posted_after >= posted_before, (
            "rebirthing dropped this player's leaderboard score from %d to %d — "
            "the board ranks players by how little they have progressed"
            % (posted_before, posted_after))
        return "score held at %d through a rebirth" % posted_after

    check("rank survives a rebirth", t_rank_survives_rebirth)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nsession: a player can leave and come back whole, and the server "
          "forgets them properly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
