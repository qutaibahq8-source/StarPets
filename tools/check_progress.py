#!/usr/bin/env python3
"""Player levels, pet levels, Make Shiny, Maps and Achievements, end to end.

Everything here changes what a player earns or owns, so everything is checked
against the real server through the real remotes (check_client's loopback):

  LEVELS      the curve climbs; every XP source pays what GameConfig says;
              a level-up is announced; rebirth keeps XP; the level bonus is
              in the income the server actually pays
  PET LEVELS  equipped pets level up in the real income loop and nothing
              else does; the cap holds; levels survive fusion, trading and
              bulk delete
  SHINY       costs what it says, refuses what it should, and asks first
  MAPS        a player goes only where they could already walk
  ACHIEVEMENTS the list is the server's, and earning one shows
"""
import re
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
import render_gui  # noqa: E402
from check_buttons import SCHEDULER  # noqa: E402

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
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        lua, mock, gui, _ = check_client.boot(loopback=True, screen=(1536, 1024))
    if lua is None:
        print("   x the client did not boot")
        return 1
    lua.execute(SCHEDULER)
    tick = lua.eval("__TICK")
    errs = lua.eval("function() local e = __THREAD_ERRORS; __THREAD_ERRORS = {}; return e end")

    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    mod = lambda n: mock["MODULES"][holder["FindFirstChild"](holder, n)]  # noqa: E731
    DM, PS, CS, BS = mod("DataManager"), mod("PetService"), mod("CurrencyService"), mod("BadgeService")
    GC = mock["MODULES"][lua.eval("game.ReplicatedStorage.Shared.GameConfig")]
    me = mock["Players"].LocalPlayer
    data = DM.GetData(me)
    assert data is not None, "the join handler loaded no data"
    hud = gui["FindFirstChild"](gui, "MysticPetsHUD")
    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]

    told = []
    lua.globals().PY_TOLD = lambda kind, msg: told.append((str(kind), str(msg)))
    lua.execute("""
        local r = game.ReplicatedStorage.Remotes.Notification
        local f = r.FireClient
        r.FireClient = function(self, p, kind, msg, ...) PY_TOLD(kind, msg); return f(self, p, kind, msg, ...) end
    """)
    fire = lua.eval("""function(name, p, ...)
        game.ReplicatedStorage.Remotes[name].OnServerEvent:Fire(p, ...)
    end""")
    invoke = lua.eval("""function(name, p, ...)
        return game.ReplicatedStorage.Remotes[name].OnServerInvoke(p, ...)
    end""")
    press = lua.eval("""function(b)
        b.MouseButton1Down:Fire(); b.MouseButton1Up:Fire(); b.MouseButton1Click:Fire()
    end""")
    sync_fn = lua.eval("function(p, d) game.ReplicatedStorage.Remotes.DataUpdated:FireClient(p, d) end")

    def sync():
        sync_fn(me, data)
        tick(2)

    def no_errors():
        e = [str(x) for x in errs().values()]
        assert not e, "something threw: %s" % e[0].splitlines()[0][:160]

    def xp():
        return int(data.XP or 0)

    def level():
        r = GC.LevelFromXP(data.XP)
        return int(r[0] if isinstance(r, tuple) else r)

    def xp_for(lv):
        return sum(int(GC.XPForLevel(L)) for L in range(1, lv))

    serial = [0]

    def grant(name, rarity, **extra):
        serial[0] += 1
        uid = "pg-%d" % serial[0]
        fields = ", ".join('%s = %s' % (k, ('"%s"' % v) if isinstance(v, str) else
                                        ("true" if v is True else "false" if v is False else v))
                           for k, v in extra.items())
        PS.GrantPet(me, lua.eval('{name="%s", rarity="%s", uniqueId="%s"%s}'
                                 % (name, rarity, uid, (", " + fields) if fields else "")), True)
        return uid

    def pet(uid):
        for p in data.Pets.values():
            if str(p.uniqueId) == uid:
                return p
        return None

    R = GC.XPRewards

    # ---- the curve ------------------------------------------------------------
    print("player levels:")

    def t_curve():
        needs = [int(GC.XPForLevel(L)) for L in range(1, 60)]
        assert all(b > a for a, b in zip(needs, needs[1:])), "the XP per level does not climb"
        for lv in (2, 10, 42):
            data.XP = xp_for(lv)
            assert level() == lv, "exactly %d XP should be level %d, is %d" % (xp_for(lv), lv, level())
            data.XP = xp_for(lv) - 1
            assert level() == lv - 1, "one XP short of level %d is level %d" % (lv, level())
        data.XP = 10 ** 12
        assert level() == int(GC.Levels.max), "a huge XP total is level %d, not the cap" % level()
        data.XP = 0
        return "climbs; level 42 takes %s XP; capped at %d" % ("{:,}".format(xp_for(42)), int(GC.Levels.max))

    check("the level curve", t_curve)

    def meadow_coin():
        # A gold coin (not a gem) in the Meadow, which every player owns. One in a world the
        # player has not unlocked is (rightly) not theirs to pick up.
        orbs = lua.eval("workspace.Orbs")
        for o in orbs["GetChildren"](orbs).values():
            if str(o._p.Name) == "CoinOrb" and o._p.Transparency != 1:
                pos = o._p.CFrame.Position
                if abs(float(pos.X)) < 60 and o._p.Color is not None and float(o._p.Color.R) > 0.9:
                    return o
        return None

    def touch_coin():
        c = meadow_coin()
        assert c is not None, "no coin left lying in the Meadow"
        root_ = me.Character["FindFirstChild"](me.Character, "HumanoidRootPart")
        lua.eval("function(o, hit) o.Touched:Fire(hit) end")(c, root_)
        tick(1)

    def t_orb():
        before, coins = xp(), float(data.Coins or 0)
        touch_coin()
        assert float(data.Coins or 0) > coins, "walking into a Meadow coin collected nothing"
        assert xp() == before + int(R.orb), "walking into a coin gave %d XP, not %d" % (xp() - before, int(R.orb))
        return "+%d" % int(R.orb)

    check("XP: a coin", t_orb)

    def t_hatch():
        data.Coins = 10 ** 9
        before = xp()
        fire("HatchEgg", me, "CoolEgg", 3)
        tick(3)
        tier = [str(e.id) for e in GC.Eggs.values()].index("CoolEgg")
        want = (int(R.hatchBase) + int(R.hatchPerTier) * tier) * 3
        assert xp() == before + want, "three Cool Eggs gave %d XP, not %d" % (xp() - before, want)
        return "+%d for three Cool Eggs" % want

    check("XP: hatching", t_hatch)

    def t_quest():
        data.EggsHatched = max(int(data.EggsHatched or 0), 5)
        before = xp()
        fire("ClaimQuest", me, "hatch5")
        tick(2)
        assert xp() == before + int(R.questMilestone), \
            "claiming a milestone quest gave %d XP, not %d" % (xp() - before, int(R.questMilestone))
        return "+%d for a milestone" % int(R.questMilestone)

    check("XP: a quest", t_quest)

    def t_world():
        forest = [a for a in GC.Areas.values() if str(a.id) == "Forest"][0]
        data.Coins = int(forest.unlockCost) + 10
        before = xp()
        fire("BuyArea", me, "Forest")
        tick(2)
        assert "Forest" in [str(a) for a in data.UnlockedAreas.values()], "the Forest did not unlock"
        assert xp() == before + int(R.worldPerTier), \
            "unlocking the Forest gave %d XP, not %d" % (xp() - before, int(R.worldPerTier))
        return "+%d for the Forest" % int(R.worldPerTier)

    check("XP: a world", t_world)

    def t_fuse():
        a = grant("cat", "Common")
        b = grant("cat", "Common", level=7, xp=33)
        c = grant("cat", "Common")
        before = xp()
        fire("Fuse", me, "cat")
        tick(2)
        assert pet(a) is None and pet(b) is None and pet(c) is None, "the three cats were not used up"
        fused = [p for p in data.Pets.values() if str(p.name) == "cat" and p.fused]
        assert fused, "no fused cat"
        assert int(fused[-1].level or 1) == 7 and int(fused[-1].xp or 0) == 33, \
            "the fused cat is level %s with %s XP; the best of the three was level 7 with 33" \
            % (fused[-1].level, fused[-1].xp)
        assert xp() == before + int(R.fuse), "fusing gave %d XP, not %d" % (xp() - before, int(R.fuse))
        return "+%d, and the fused pet keeps the best level (7)" % int(R.fuse)

    check("XP: fusing", t_fuse)

    def t_level_up_told():
        data.XP = xp_for(5) - 1
        told.clear()
        touch_coin()
        said = [m for k, m in told if "Level 5" in m]
        assert said, "reaching level 5 was not announced (%s)" % told[-3:]
        return repr(said[0])

    check("a level-up is announced", t_level_up_told)

    def t_rebirth_keeps():
        data.XP = xp_for(20) + 7
        kept = xp()
        tier1 = [t for t in GC.Rebirths.values() if int(t.level) == int(data.Rebirths or 0) + 1][0]
        data.TotalCoinsEarned = int(tier1.requirement)
        fire("RebirthConfirm", me)
        tick(2)
        assert int(data.Rebirths) >= 1, "the rebirth did not happen"
        assert xp() == kept + int(R.rebirthPerLevel) * int(data.Rebirths), \
            "XP after rebirth is %d; it was %d plus %d for the rebirth" % (
                xp(), kept, int(R.rebirthPerLevel) * int(data.Rebirths))
        return "kept, plus %d for rebirth %d" % (int(R.rebirthPerLevel) * int(data.Rebirths), int(data.Rebirths))

    check("rebirth keeps XP", t_rebirth_keeps)

    def t_income_level():
        data.Pets = lua.eval("{}")
        data.EquippedPets = lua.eval("{}")
        data.ActiveBoosts = lua.eval("{}")
        uid = grant("dog", "Common")
        data.EquippedPets = lua.eval('{"%s"}' % uid)
        data.XP = 0
        base = PS.GetPlayerIncome(me)
        base = base[0] if isinstance(base, tuple) else base
        data.XP = xp_for(11)
        more = PS.GetPlayerIncome(me)
        more = more[0] if isinstance(more, tuple) else more
        want = int(int(base / float(data.RebirthMultiplier or 1)) * 1.1 * float(data.RebirthMultiplier or 1))
        assert abs(more - base * 1.1) <= 1, "level 11 pays %d a second; level 1 paid %d (+10%% is %d)" % (
            more, base, base * 1.1)
        data.XP = 0
        return "%d -> %d coins a second at level 11 (+10%%)" % (base, more)

    check("the level bonus is paid", t_income_level)

    # ---- pet levels -----------------------------------------------------------
    print("\npet levels:")

    def t_pet_xp_loop():
        out_uid = grant("rabbit", "Common", level=1, xp=int(GC.PetXPForLevel(1)) - 1)
        home_uid = grant("rabbit", "Common", level=1, xp=0)
        data.EquippedPets = lua.eval('{"%s"}' % out_uid)
        told.clear()
        # The real income loop, run a step at a time.
        CS.StartPassiveIncome(PS)
        tick(1)
        p_out, p_home = pet(out_uid), pet(home_uid)
        assert int(p_out.level or 1) == 2, "a second equipped, one XP short, and it is level %s" % p_out.level
        assert int(p_home.level or 1) == 1 and int(p_home.xp or 0) == 0, "a pet left at home gained XP"
        said = [m for k, m in told if "reached Level 2" in m]
        assert said, "the pet's level-up was not announced"
        return "equipped pets level in the income loop (%r); others do not" % said[0]

    check("equipped pets level up", t_pet_xp_loop)

    def t_pet_cap():
        top = int(GC.PetLevels.max)
        uid = grant("rabbit", "Common", level=top, xp=0)
        data.EquippedPets = lua.eval('{"%s"}' % uid)
        PS.TickPetXP(me, 10 ** 7)
        p = pet(uid)
        assert int(p.level) == top and int(p.xp or 0) == 0, "past the cap: level %s, %s XP" % (p.level, p.xp)
        uid2 = grant("rabbit", "Common", level=1, xp=0)
        data.EquippedPets = lua.eval('{"%s"}' % uid2)
        PS.TickPetXP(me, 10 ** 9)
        assert int(pet(uid2).level) == top, "a huge amount of XP stopped at level %s" % pet(uid2).level
        return "stops at %d" % top

    check("the pet level cap", t_pet_cap)

    def t_pet_power():
        plain = lua.eval('{name="dog", rarity="Common"}')
        lv = lua.eval('{name="dog", rarity="Common", level=26}')
        shiny = lua.eval('{name="dog", rarity="Common", level=26, mutation="Shiny", fuseMult=1.5}')
        a, b, c = float(GC.PetPower(plain)), float(GC.PetPower(lv)), float(GC.PetPower(shiny))
        assert a == 1 and abs(b - 1.5) < 1e-9 and abs(c - 1.5 * 4 * 1.5) < 1e-9, \
            "pet power: plain %s, level 26 %s, level 26 Shiny fused 1.5 %s" % (a, b, c)
        return "level 26 = x1.5; with Shiny and x1.5 fusion = x9"

    check("a pet's level is in its power", t_pet_power)

    def t_bulk_keeps():
        keep = grant("ant", "Common", level=3)
        go = grant("ant", "Common")
        data.EquippedPets = lua.eval("{}")
        PS.DeleteByRarity(me, "Common")
        assert pet(keep) is not None, "bulk delete took a levelled pet"
        assert pet(go) is None, "bulk delete left a plain one"
        return "a levelled pet is kept, a plain one goes"

    check("bulk delete keeps levelled pets", t_bulk_keeps)

    def t_trade_carries():
        src = (ROOT / "src/Server/TradeService.lua").read_text()
        m = re.search(r"local CARRIED = \{(.*?)\}", src, re.S)
        assert m, "TradeService has no CARRIED list"
        fields = re.findall(r'"(\w+)"', m.group(1))
        missing = [f for f in ("level", "xp", "mutation", "fuseMult") if f not in fields]
        assert not missing, "a traded pet loses %s" % missing
        return "a traded pet keeps its level and XP"

    check("trading keeps levels", t_trade_carries)

    # ---- shiny ------------------------------------------------------------------
    print("\nmake shiny:")
    cost = {str(k): int(v) for k, v in GC.ShinyCost.items()}

    def t_shiny_rules():
        plain = grant("dog", "Common")
        golden = grant("cat", "Common", mutation="Golden")
        pets_folder = lua.eval("workspace.Pets")

        def model_of(uid):
            mine = pets_folder["FindFirstChild"](pets_folder, str(me.UserId))
            if mine is None:
                return None
            for m in mine["GetChildren"](mine).values():
                if str(m._p.Name).endswith("_" + uid):
                    return m
            return None
        shiny = grant("rat", "Common", mutation="Shiny")
        rainbow = grant("bee", "Common", mutation="Rainbow")
        data.EquippedPets = lua.eval("{}")
        fire("EquipPet", me, plain); tick(2)
        old_model = model_of(plain)
        assert old_model is not None, "equipping the dog put no pet in the world"
        data.Gems = cost["Common"] - 1
        fire("PetCmd", me, "makeShiny", plain); tick(2)
        assert pet(plain).mutation is None and int(data.Gems) == cost["Common"] - 1, \
            "one gem short, and it was made Shiny or charged"
        data.Gems = cost["Common"] * 10
        made_before = int(data.ShinyMade or 0)
        fire("PetCmd", me, "makeShiny", plain); tick(2)
        assert str(pet(plain).mutation) == "Shiny", "paid for, and it is not Shiny"
        assert int(data.Gems) == cost["Common"] * 9, "charged %d, not %d" % (cost["Common"] * 10 - int(data.Gems), cost["Common"])
        assert int(data.ShinyMade) == made_before + 1, "not counted"
        fire("PetCmd", me, "makeShiny", golden); tick(2)
        assert str(pet(golden).mutation) == "Shiny", "a Golden pet could not be made Shiny"
        g = int(data.Gems)
        for uid in (shiny, rainbow):
            fire("PetCmd", me, "makeShiny", uid); tick(2)
        assert str(pet(shiny).mutation) == "Shiny" and str(pet(rainbow).mutation) == "Rainbow", \
            "a Shiny or Rainbow pet was changed"
        assert int(data.Gems) == g, "refusing still charged"
        fire("PetCmd", me, "makeShiny", "no-such-pet"); tick(2)
        fire("PetCmd", me, "makeShiny", 12345); tick(2)
        no_errors()
        # The equipped one is rebuilt in the world, shining.
        new_model = model_of(plain)
        same = lua.eval("function(a, b) return rawequal(a, b) end")
        assert new_model is not None, "the equipped pet vanished from the world"
        assert not same(new_model, old_model), "the pet in the world was not rebuilt, so it does not shine"
        BS.CheckAll(me)
        assert "first_shiny" in [str(b) for b in data.Badges.values()], "no Shine On achievement"
        return "costs %d for a Common; Golden upgrades; Shiny, Rainbow and short refused" % cost["Common"]

    check("its rules on the server", t_shiny_rules)

    def t_shiny_button():
        render_gui.set_screen(lua, 1536, 1024)
        uid = grant("dragon", "Epic")
        data.EquippedPets = lua.eval('{"%s"}' % uid)
        data.Gems = cost["Epic"] + 5
        sync()
        btn = hud["FindFirstChild"](hud, "HUD_Shiny", True)
        assert btn is not None and btn._p.Active is not False, "no live Shiny button for a plain Epic"
        press(btn); tick(2)
        assert pet(uid).mutation is None and int(data.Gems) == cost["Epic"] + 5, "one press spent the gems"
        assert "Sure?" in str(btn._p.Text) and "{:,}".format(cost["Epic"]) in str(btn._p.Text), \
            "the first press did not ask with the price (%r)" % str(btn._p.Text)
        press(btn); tick(3)
        assert str(pet(uid).mutation) == "Shiny" and int(data.Gems) == 5, "the second press did not buy it"
        sync()
        btn = hud["FindFirstChild"](hud, "HUD_Shiny", True)
        assert btn._p.Active is False, "an already Shiny pet's button is still live"
        hint = str(hud["FindFirstChild"](hud, "ShinyHint", True)._p.Text)
        assert "Already Shiny" in hint, "the card does not say why (%r)" % hint
        return "asks with the price, buys on the second press, then says it is done"

    check("the Shiny button asks first", t_shiny_button)

    # ---- maps ---------------------------------------------------------------------
    print("\nmaps:")
    root = me.Character["FindFirstChild"](me.Character, "HumanoidRootPart")

    def where():
        p = root._p.CFrame.Position if root._p.CFrame is not None else None
        return (float(p.X), float(p.Y), float(p.Z))

    def t_maps_panel():
        data.UnlockedAreas = lua.eval('{"Meadow"}')
        sync()
        ctrl.CloseAll()
        ctrl.TogglePanel("MapsPanel", data)
        tick(1)
        mp = gui["FindFirstChild"](gui, "MapsPanel")
        names = {str(d._p.Name) for d in mp["GetDescendants"](mp).values() if str(d._p.ClassName) == "TextButton"}
        assert "Go_Meadow" in names and "Gate_Forest" in names, "the panel offers %s" % sorted(names)
        assert not names & {"Go_Forest", "Gate_Desert", "Go_Space"}, "it offers a world the player cannot reach"
        root.CFrame = lua.eval("CFrame.new(300, 5, 40)")
        press(mp["FindFirstChild"](mp, "Go_Meadow", True)); tick(2)
        x, y, z = where()
        assert abs(x) < 20 and abs(z) < 30, "Go Meadow put the player at %s" % ((x, y, z),)
        return "Go to the Meadow, To gate for the Forest, nothing further"

    check("the Maps panel", t_maps_panel)

    def t_teleport_rules():
        start = lua.eval("CFrame.new(1, 5, 1)")
        tries = [("Desert", False), ("Desert", True), ("Space", False), (123, False), (None, True)]
        for area, gate in tries:
            root.CFrame = start
            fire("Teleport", me, area, gate); tick(1)
            assert where()[0] == 1.0 and where()[2] == 1.0, "Teleport(%r, %r) moved a player who had not earned it" % (area, gate)
        fire("Teleport", me, "Forest", True); tick(1)
        gate_x = where()[0]
        assert 60 < gate_x < 80, "To gate (Forest) put the player at x=%d, not before its gate (x=80)" % gate_x
        data.UnlockedAreas = lua.eval('{"Meadow", "Forest"}')
        fire("Teleport", me, "Forest", False); tick(1)
        assert 80 < where()[0] < 145, "Go (Forest) put the player at x=%d" % where()[0]
        assert where()[1] > 0, "teleported under the ground (y=%d)" % where()[1]
        no_errors()
        return "locked worlds refused; gate at x=%d; inside the Forest at x=%d" % (gate_x, where()[0])

    check("teleporting goes only where you could walk", t_teleport_rules)

    # ---- achievements ------------------------------------------------------------
    print("\nachievements:")

    def t_achievements():
        data.XP = xp_for(10)
        items = invoke("GetAchievements", me)
        listed = list(items.values())
        assert len(listed) == len(list(BS.GetAll().values())), "the list is not every achievement"
        earned = {str(a.id) for a in listed if a.earned}
        assert "level_10" in earned, "level 10 reached and Rising Star not earned"
        ctrl.CloseAll()
        ctrl.TogglePanel("AchievementsPanel", data)
        tick(3)
        ap = gui["FindFirstChild"](gui, "AchievementsPanel")
        header = str(ap["FindFirstChild"](ap, "Header", True)._p.Text)
        want = "%d/%d" % (len(earned), len(listed))
        assert want in header, "the panel says %r, the server %s" % (header, want)
        rows = [d for d in ap["GetDescendants"](ap).values() if str(d._p.Name).startswith("Ach_")]
        assert len(rows) == len(listed), "%d rows for %d achievements" % (len(rows), len(listed))
        ctrl.CloseAll()
        no_errors()
        return "%s, one row each" % header.strip()

    check("the list, and earning one", t_achievements)

    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nprogress: levels, pet levels, Shiny, Maps and Achievements all do what they say")
    return 0


if __name__ == "__main__":
    sys.exit(main())
