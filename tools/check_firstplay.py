#!/usr/bin/env python3
"""A new player's first minutes, through the real UI and the real server.

Every piece of this is tested somewhere on its own. This is the one place it
is tested JOINED UP, in the order a new player meets it — which is where a
pet simulator either hooks someone or loses them:

   1. the banner says hatch your free egg
   2. they click the green egg in the world   -> the hatch panel, on that egg
   3. they press Hatch                        -> free, a reveal, a pet
   4. the pet is equipped and follows them    -> no trip to the Pets panel
   5. the banner moves on                     -> "your pet earns coins"
   6. they press Hatch again, broke           -> told why, charged nothing
   7. they walk into coins                    -> coins go up
   8. they can afford an egg and hatch it     -> charged exactly its price

A break anywhere in that chain is a new player who quits in the first minute,
and no other check would notice.
"""
import sys
from pathlib import Path

try:
    import lupa  # noqa: F401
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_client  # noqa: E402
import check_map  # noqa: E402
from check_buttons import SCHEDULER  # noqa: E402

FAILURES = []


def check(label, fn):
    try:
        print("   ok  %-34s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-34s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-34s crashed: %r" % (label, e))
        FAILURES.append(label)


def main():
    lua, mock, gui, _ = check_client.boot(loopback=True)
    if lua is None:
        print("   x the client did not boot")
        return 1
    print()
    lua.execute(SCHEDULER)
    tick = lua.eval("__TICK")
    thread_errors = lua.eval(
        "function() local e = __THREAD_ERRORS; __THREAD_ERRORS = {}; return e end")

    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    me = mock["Players"].LocalPlayer
    data = DM.GetData(me)
    ws = mock["workspace"]

    told = lua.eval("{}")
    lua.eval("""function(told)
        local r = game.ReplicatedStorage.Remotes:FindFirstChild("Notification")
        r.OnClientEvent:Connect(function(kind, msg) table.insert(told, tostring(msg)) end)
    end""")(told)

    def count(t):
        return len(list(t.values())) if t is not None else 0

    def press(b):
        lua.eval("""function(b)
            b.MouseButton1Down:Fire(); b.MouseButton1Up:Fire(); b.MouseButton1Click:Fire()
        end""")(b)
        tick(3)

    def banner():
        s = gui["FindFirstChild"](gui, "OnboardingGui")
        if s is None:
            return ""
        return " ".join(str(d._p.Text) for d in s["GetDescendants"](s).values()
                        if str(d._p.ClassName) == "TextLabel")

    def hatch1():
        s = gui["FindFirstChild"](gui, "HatchPanel")
        assert s is not None, "the hatch panel is not open"
        card = [d for d in s["GetDescendants"](s).values()
                if str(d._p.Name) == "EggCard_StarterEgg"]
        assert card, "the hatch panel has no Starter Egg card"
        btns = [b for b in card[0]["GetChildren"](card[0]).values()
                if str(b._p.ClassName) == "TextButton" and str(b._p.Text).startswith("Hatch")]
        assert btns, "the Starter Egg card has no Hatch button"
        return btns[0]

    def no_errors():
        errs = [str(e) for e in thread_errors().values()]
        assert not errs, "something threw: %s" % errs[0].splitlines()[0][:160]

    # -------------------------------------------------------------------
    def t_banner_says_hatch():
        assert int(data.EggsHatched or 0) == 0 and int(data.Coins or 0) == 0, \
            "not a new player (%s eggs, %s coins)" % (data.EggsHatched, data.Coins)
        b = banner()
        assert "FREE" in b, "a brand-new player sees no hatch-your-free-egg banner (%r)" % b[:80]
        return "%r" % b[:50]

    def t_click_egg():
        egg = ws["FindFirstChild"](ws, "Egg_StarterEgg", True)
        assert egg is not None, "there is no Starter Egg in the world"
        cd = egg["FindFirstChildOfClass"](egg, "ClickDetector")
        assert cd is not None, "the Starter Egg cannot be clicked"
        lua.eval("function(cd, p) cd.MouseClick:Fire(p) end")(cd, me)
        tick(3)
        no_errors()
        text = str(hatch1()._p.Text).replace("\n", " ")
        assert "FREE" in text, "the first egg's button does not say it is free (%r)" % text
        return "panel open on the Starter Egg: %r" % text

    def t_hatch_free():
        before = count(data.Pets)
        press(hatch1())
        no_errors()
        assert count(data.Pets) == before + 1, "pressing Hatch gave %d pets" % (count(data.Pets) - before)
        assert int(data.Coins or 0) == 0, "the free egg cost %s coins" % data.Coins
        r = gui["FindFirstChild"](gui, "HatchResultGui")
        assert r is not None, "no reveal"
        cards = [c for c in r["GetChildren"](r).values() if str(c._p.Name) == "HatchCard"]
        assert len(cards) == 1, "the reveal shows %d cards" % len(cards)
        return "a %s, free, with a reveal" % data.Pets[1].name

    def t_equipped_and_following():
        eq = count(data.EquippedPets)
        assert eq == 1, "the hatched pet is not equipped (%d equipped)" % eq
        folder = ws["FindFirstChild"](ws, "Pets")
        mine = folder and folder["FindFirstChild"](folder, str(me.UserId))
        n = count(mine["GetChildren"](mine)) if mine is not None else 0
        assert n == 1, "%d pet model(s) in the world for this player" % n
        return "equipped, and its model is in the world"

    def t_banner_moves_on():
        b = banner()
        assert "earns coins" in b, "after the first hatch the banner says %r" % b[:80]
        return "%r" % b[:50]

    def t_continue_closes_reveal():
        r = gui["FindFirstChild"](gui, "HatchResultGui")
        btn = r and r["FindFirstChild"](r, "Continue", True)
        assert btn is not None, "the reveal has no Continue button"
        press(btn)
        assert gui["FindFirstChild"](gui, "HatchResultGui") is None, "Continue did not close the reveal"
        return "closed"

    def t_broke_is_told():
        for k in list(told.keys()):
            told[k] = None
        before = count(data.Pets)
        press(hatch1())
        no_errors()
        said = [str(v) for v in told.values()]
        assert count(data.Pets) == before, "a broke player got a pet"
        assert int(data.Coins or 0) == 0, "a broke player was charged"
        assert any("Coins" in m for m in said), "a broke player pressing Hatch was told nothing"
        return "told: %r" % said[0]

    def t_walk_into_coins():
        orbs = ws["FindFirstChild"](ws, "Orbs")
        assert orbs is not None, "no coins on the ground"
        root = me.Character["FindFirstChild"](me.Character, "HumanoidRootPart")
        touch = lua.eval("function(orb, part) orb.Touched:Fire(part) end")
        got = 0
        # Meadow's coins: a new player owns only the Meadow, and a coin in a
        # locked world rightly pays nothing.
        meadow = [o for o in orbs["GetDescendants"](orbs).values()
                  if str(o._p.ClassName) in ("Part", "MeshPart")
                  and abs(float(o._p.CFrame.Position.X)) < 70]
        assert len(meadow) >= 20, "only %d coins in the Meadow" % len(meadow)
        for orb in meadow[:40]:
            before = int(data.Coins or 0)
            root.CFrame = lua.eval("function(o) return CFrame.new(o.Position) end")(orb)
            touch(orb, root)
            tick(1)
            got += int(data.Coins or 0) - before
        no_errors()
        assert got > 0, "walked into 40 coins and earned nothing"
        return "+%d coins from the ground" % got

    def t_buy_an_egg():
        price = int(lua.eval("_G.MysticPets.GameConfig.Eggs[1].costAfterFirst or 150"))
        data.Coins = price + 7
        before = count(data.Pets)
        press(hatch1())
        no_errors()
        assert count(data.Pets) == before + 1, "an affordable egg gave no pet"
        assert int(data.Coins) == 7, "charged %d for a %d-coin egg" % (price + 7 - int(data.Coins), price)
        eq = count(data.EquippedPets)
        assert eq == 2, "the second pet did not fill a free slot (%d equipped)" % eq
        return "charged exactly %d; now %d pets, %d equipped" % (price, count(data.Pets), eq)

    print("a new player's first minutes:")
    for label, fn in (
            ("1 the banner says hatch", t_banner_says_hatch),
            ("2 click the green egg", t_click_egg),
            ("3 hatch it, free", t_hatch_free),
            ("4 equipped and in the world", t_equipped_and_following),
            ("5 the banner moves on", t_banner_moves_on),
            ("  continue closes the reveal", t_continue_closes_reveal),
            ("6 broke: told, not charged", t_broke_is_told),
            ("7 walk into coins", t_walk_into_coins),
            ("8 afford one, hatch it", t_buy_an_egg)):
        check(label, fn)
        if FAILURES:
            print("\n   (stopping: every later step depends on this one)")
            break
    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nfirst play: from the banner to a bought egg, unbroken")
    return 0


if __name__ == "__main__":
    sys.exit(main())
