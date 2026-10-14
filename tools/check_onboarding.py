#!/usr/bin/env python3
"""A brand-new player is shown what to do; nobody else is.

The join banner thanked the player and asked for a like. It said nothing about
how to play. And a freshly hatched pet was never equipped — PetService.EquipBest
existed and nothing called it — so the first pet a new player got earned
nothing until they found the Pets panel on their own.

  1. A NEW PLAYER IS POINTED AT THE EGG    step one, with an arrow over the
                                           Starter Egg that only they can see
  2. THE HINTS FOLLOW REAL PROGRESS        hatch -> collect -> keep going
  3. A RETURNING PLAYER SEES NOTHING       derived from progress, so no save
                                           needs a migration and it cannot
                                           show twice
  4. A HATCHED PET IS EQUIPPED             into a free slot, never pushing out
                                           a pet the player chose
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_client  # noqa: E402
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


def main():
    lua, mock, gui, _ = check_client.boot()
    print()
    ob = lua.globals()._G.StarPetsOnboarding
    if ob is None:
        print("   x the onboarding script never ran — it does not exist in game")
        return 1
    step = ob.stepFor
    apply = ob.apply
    data = lambda src: lua.eval("(%s)" % src)  # noqa: E731

    def t_new_player_step_one():
        s = step(data('{EggsHatched=0, Rebirths=0, UnlockedAreas={"Meadow"}, TotalCoinsEarned=0}'))
        assert s == 1, "a brand-new player is on step %s, not 1" % s
        apply(data('{EggsHatched=0, Rebirths=0, UnlockedAreas={"Meadow"}, TotalCoinsEarned=0}'))
        banner = gui["FindFirstChild"](gui, "OnboardingGui")
        assert banner is not None, "no banner was shown to a new player"
        texts = [str(d._p.Text) for d in banner["GetDescendants"](banner).values()
                 if str(d._p.ClassName) == "TextLabel"]
        assert any("egg" in t.lower() for t in texts), "step one does not mention the egg: %s" % texts
        ws = mock["workspace"]
        egg = ws["FindFirstChild"](ws, "Egg_StarterEgg", True)
        assert egg is not None, "there is no Starter Egg in the world to point at"
        arrow = egg["FindFirstChild"](egg, "OnboardingArrow")
        assert arrow is not None, "nothing points the new player at the Starter Egg"
        return "banner up, arrow over the Starter Egg"

    def t_progression():
        seen = []
        for src in ('{EggsHatched=0, UnlockedAreas={"Meadow"}, TotalCoinsEarned=0}',
                    '{EggsHatched=1, UnlockedAreas={"Meadow"}, TotalCoinsEarned=40}',
                    '{EggsHatched=2, UnlockedAreas={"Meadow"}, TotalCoinsEarned=900}',
                    '{EggsHatched=3, UnlockedAreas={"Meadow"}, TotalCoinsEarned=900}'):
            seen.append(step(data(src)))
        assert seen == [1, 2, 3, None], "steps went %s, not 1, 2, 3, done" % seen
        return "hatch -> collect -> keep going -> done"

    def t_arrow_goes_away():
        apply(data('{EggsHatched=1, UnlockedAreas={"Meadow"}, TotalCoinsEarned=0}'))
        ws = mock["workspace"]
        egg = ws["FindFirstChild"](ws, "Egg_StarterEgg", True)
        assert egg["FindFirstChild"](egg, "OnboardingArrow") is None, \
            "the START HERE arrow stayed up after the first hatch"
        return "arrow removed after the first hatch"

    def t_returning_players_see_nothing():
        cases = {
            "veteran": '{EggsHatched=480, Rebirths=0, UnlockedAreas={"Meadow","Forest"}, TotalCoinsEarned=9e6}',
            "rebirthed": '{EggsHatched=2, Rebirths=1, UnlockedAreas={"Meadow"}, TotalCoinsEarned=0}',
            "explorer": '{EggsHatched=0, Rebirths=0, UnlockedAreas={"Meadow","Forest"}, TotalCoinsEarned=0}',
        }
        for who, src in cases.items():
            s = step(data(src))
            assert s is None, "a %s player was shown onboarding step %s" % (who, s)
        apply(data(cases["veteran"]))
        assert gui["FindFirstChild"](gui, "OnboardingGui") is None, \
            "the banner stayed on screen for a returning player"
        return "veteran, rebirthed and explorer all see nothing"

    def t_old_save_without_the_field():
        # A save from before onboarding existed has no special field — and
        # needs none. Missing values must read as a returning player only if
        # their progress says so.
        s = step(data('{EggsHatched=12, UnlockedAreas={"Meadow"}}'))
        assert s is None, "an old save with 12 hatches was put back on step %s" % s
        return "an old save needs no migration"

    print("onboarding:")
    check("a new player is pointed at the egg", t_new_player_step_one)
    check("hints follow real progress", t_progression)
    check("the arrow goes after hatching", t_arrow_goes_away)
    check("returning players see nothing", t_returning_players_see_nothing)
    check("old saves need no migration", t_old_save_without_the_field)

    # ---- auto-equip, through the real hatch remote ------------------------
    print("\nauto-equip:")
    lua2, mock2, cfg2 = check_map.build()
    sss = mock2["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock2["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    RL = mock2["MODULES"][holder["FindFirstChild"](holder, "RateLimit")]
    cnt = lua2.eval("function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end")
    rs = mock2["ReplicatedStorage"]
    remotes = rs["FindFirstChild"](rs, "Remotes")
    hatch_ev = remotes["FindFirstChild"](remotes, "HatchEgg")
    fire = lua2.eval("function(sig, p, ...) sig:Fire(p, ...) end")

    def new_player(uid):
        p = mock2["newInst"]("Player")
        p.Name = "N%d" % uid
        p.UserId = uid
        mock2["PlayerList"][1] = p
        r = DM.LoadPlayer(p)
        return p, (r[0] if isinstance(r, tuple) else r)

    def t_first_pet_is_equipped():
        p, d = new_player(8801)
        RL.Reset(p)
        fire(hatch_ev.OnServerEvent, p, "StarterEgg", 1)
        assert cnt(d.Pets) == 1, "the free egg did not hatch (%d pets)" % cnt(d.Pets)
        assert cnt(d.EquippedPets) == 1, ("the first pet was hatched but not "
                                          "equipped, so it earns nothing")
        return "the free egg's pet is equipped on arrival"

    def t_never_pushes_a_chosen_pet_out():
        p, d = new_player(8802)
        d.Coins = 1e9
        slots = int(cfg2.Settings.DefaultPetSlots)
        for i in range(slots):
            RL.Reset(p)
            fire(hatch_ev.OnServerEvent, p, "CoolEgg", 1)
        chosen = [str(d.EquippedPets[i]) for i in range(1, slots + 1)]
        RL.Reset(p)
        fire(hatch_ev.OnServerEvent, p, "CoolEgg", 10)
        after = [str(d.EquippedPets[i]) for i in range(1, slots + 1)]
        assert after == chosen, ("a full set of equipped pets was changed by "
                                 "hatching more: %s -> %s" % (chosen, after))
        n = int(cnt(d.EquippedPets))
        assert n == slots, ("%d pet(s) equipped with %d slot(s) — %s"
                            % (n, slots, "over the limit" if n > slots
                               else "hatched pets are not filling free slots"))
        return "full slots stay as they were after a ten-hatch"

    check("the first pet is equipped", t_first_pet_is_equipped)
    check("never pushes out a chosen pet", t_never_pushes_a_chosen_pet_out)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nonboarding: a new player is shown the way, and their first pet works")
    return 0


if __name__ == "__main__":
    sys.exit(main())
