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
   9. they click the Forest gate              -> asked, with the price
  10. they unlock it                          -> charged, the gate opens
  11. the Forest egg can be hatched           -> the next world's pets
  12. the rebirth machine                     -> asked, reborn, reset cleanly
  13. the secret spot                         -> found, rewarded

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

    areas = list(lua.eval("_G.MysticPets.GameConfig.Areas").values())
    forest, desert = areas[1], areas[2]

    def gate(area_id):
        g = ws["FindFirstChild"](ws, "Barrier_" + area_id, True)
        assert g is not None, "there is no %s gate in the world" % area_id
        return g

    def click_gate(area_id):
        g = gate(area_id)
        cd = g["FindFirstChildOfClass"](g, "ClickDetector")
        assert cd is not None, "the %s gate cannot be clicked" % area_id
        old = gui["FindFirstChild"](gui, "AreaUnlockGui")
        if old is not None:
            old["Destroy"](old)
        lua.eval("function(cd, p) cd.MouseClick:Fire(p) end")(cd, me)
        tick(3)
        no_errors()
        return gui["FindFirstChild"](gui, "AreaUnlockGui")

    def owns(area_id):
        return any(str(v) == area_id for v in data.UnlockedAreas.values())

    def t_out_of_order_refused():
        data.Coins = int(desert.unlockCost) + 1000
        s = click_gate(str(desert.id))
        assert s is not None, "clicking the Desert gate asked nothing"
        yes = s["FindFirstChild"](s, "Unlock", True)
        text = " ".join(str(d._p.Text) for d in s["GetDescendants"](s).values()
                        if str(d._p.ClassName) == "TextLabel")
        assert yes._p.Active is False, "the Desert can be bought before the Forest"
        assert str(forest.name) in text, "the prompt does not say to unlock the Forest first"
        # And straight at the server, the way an exploiter would.
        r = lua.eval("game.ReplicatedStorage.Remotes.BuyArea")
        lua.eval("function(r) r:FireServer('%s') end" % desert.id)(r)
        tick(3)
        assert not owns(str(desert.id)), "the server sold the Desert before the Forest"
        return "the prompt says Forest first, and the server agrees"

    def t_gate_asks():
        price = int(forest.unlockCost)
        data.Coins = price + 5
        s = click_gate(str(forest.id))
        assert s is not None, ("clicking the Forest gate did nothing — no player can "
                               "ever leave the Meadow")
        yes = s["FindFirstChild"](s, "Unlock", True)
        assert yes is not None and yes._p.Active is not False, "the Unlock button is dead"
        return "%r" % str(yes._p.Text)

    def t_unlock_forest():
        price = int(forest.unlockCost)
        s = gui["FindFirstChild"](gui, "AreaUnlockGui")
        press(s["FindFirstChild"](s, "Unlock", True))
        no_errors()
        assert owns(str(forest.id)), "pressed Unlock and the Forest is still locked"
        assert int(data.Coins) == 5, "charged %d for a %d-coin world" % (price + 5 - int(data.Coins), price)
        g = gate(str(forest.id))
        assert g._p.CanCollide is False, "the Forest is bought but its gate still blocks the way"
        assert gui["FindFirstChild"](gui, "OnboardingGui") is None, \
            "the new-player banner is still up after the first world was bought"
        return "bought for %d, the gate is open, the banner has gone" % price

    def t_forest_egg_opens():
        ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
        ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
        ctrl.CloseAll()
        ctrl.TogglePanel("HatchPanel", data)
        tick(1)
        s = gui["FindFirstChild"](gui, "HatchPanel")
        eggs = list(lua.eval("_G.MysticPets.GameConfig.Eggs").values())
        fe = [e for e in eggs if str(e.world or "") == str(forest.id)]
        assert fe, "there is no Forest egg"
        card = s["FindFirstChild"](s, "EggCard_" + str(fe[0].id), True)
        btn = [b for b in card["GetChildren"](card).values()
               if str(b._p.ClassName) == "TextButton" and str(b._p.Text).startswith("Hatch")][0]
        assert btn._p.Active is not False, "the Forest egg is still locked after buying the Forest"
        return "%s: %r" % (fe[0].name, str(btn._p.Text).replace("\n", " "))

    def by_action(cls, action):
        return [d for d in ws["GetDescendants"](ws).values()
                if str(d._p.ClassName) == cls
                and str(d["GetAttribute"](d, "SPAction") or "") == action]

    def t_rebirth_machine():
        tiers = list(lua.eval("_G.MysticPets.GameConfig.Rebirths").values())
        data.TotalCoinsEarned = int(tiers[0].requirement)
        cds = by_action("ClickDetector", "Rebirth")
        assert cds, "the rebirth machine cannot be clicked"
        old = gui["FindFirstChild"](gui, "RebirthConfirmGui")
        if old is not None:
            old["Destroy"](old)
        lua.eval("function(cd, p) cd.MouseClick:Fire(p) end")(cds[0], me)
        tick(3)
        no_errors()
        s = gui["FindFirstChild"](gui, "RebirthConfirmGui")
        assert s is not None, "clicking the rebirth machine asked nothing"
        btns = [b for b in s["GetDescendants"](s).values()
                if str(b._p.ClassName) == "TextButton" and "REBIRTH" in str(b._p.Text).upper()
                and "cancel" not in str(b._p.Text).lower()]
        assert btns, "the rebirth popup has no confirm button"
        press(btns[0])
        no_errors()
        assert int(data.Rebirths or 0) == 1, "confirmed, and Rebirths is %s" % data.Rebirths
        assert float(data.RebirthMultiplier) == float(tiers[0].multiplier), "the multiplier did not rise"
        folder = ws["FindFirstChild"](ws, "Pets")
        mine = folder and folder["FindFirstChild"](folder, str(me.UserId))
        ghosts = count(mine["GetChildren"](mine)) if mine is not None else 0
        assert ghosts == 0, "%d pet model(s) still follow a player whose pets were reset" % ghosts
        g = gate(str(forest.id))
        assert g._p.CanCollide is not False, "the Forest gate stayed open after the rebirth reset it"
        return "reborn as %s, %sx; pets reset, gate closed again" % (
            tiers[0].title, tiers[0].multiplier)

    def t_secret():
        prompts = by_action("ProximityPrompt", "SecretChest")
        assert prompts, "there is no secret to find"
        gems = int(data.Gems or 0)
        lua.eval("function(pp, p) pp.Triggered:Fire(p) end")(prompts[0], me)
        tick(3)
        no_errors()
        assert int(data.Gems or 0) > gems or gui["FindFirstChild"](gui, "SecretFoundGui") is not None, \
            "searching the secret spot gave nothing and said nothing"
        return "found: %s gems, popup %s" % (int(data.Gems or 0) - gems,
            "shown" if gui["FindFirstChild"](gui, "SecretFoundGui") is not None else "not shown")

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
            ("8 afford one, hatch it", t_buy_an_egg),
            ("  the Desert waits its turn", t_out_of_order_refused),
            ("9 the Forest gate asks", t_gate_asks),
            ("10 unlock the Forest", t_unlock_forest),
            ("11 the Forest egg opens", t_forest_egg_opens),
            ("12 the rebirth machine", t_rebirth_machine),
            ("13 the secret spot", t_secret)):
        check(label, fn)
        if FAILURES:
            print("\n   (stopping: every later step depends on this one)")
            break
    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nfirst play: from the banner to the second world, unbroken")
    return 0


if __name__ == "__main__":
    sys.exit(main())
