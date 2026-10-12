#!/usr/bin/env python3
"""The HUD, measured at every common screen size and pressed end to end.

The HUD is the one piece of UI on screen for the whole game, and it is drawn
after the owner's mockup: cards down both sides on a computer, rails of
touch-sized buttons on a phone. Getting that right is geometry, and geometry
is exactly what nobody can see from the code. This lays the real HUD out with
Roblox's rules (render_gui.layout: UIScale, anchors, constraints) and checks:

  ON SCREEN       every piece, at every size, inside the screen
  APART           no two pieces drawn over each other
  CLEAR           of Roblox's own buttons at the top left, and on a phone of
                  the thumbstick and the jump button
  TOUCHABLE       on a phone, every button at least 44 points
  READABLE        no label spills out of its box, none drawn under 9 pixels
  AS DRAWN        at the mockup's own 1536x1024, the cards are where the
                  mockup put them

and then, against the real server (check_client's loopback):

  every one of the fifteen panels opens from a HUD button, in both layouts;
  the pet cards are the equipped pets; selecting, unequipping, locking and
  deleting work and deleting asks first; the income shown is the income the
  server pays; the quest card is the real quests; the event card appears
  only during an event; the Auto Collect switch really stops the collector;
  a layout switch leaves exactly one HUD; toasts and the new-player card
  drop in below the counters, not over them.
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
import render_gui  # noqa: E402
from check_buttons import SCHEDULER  # noqa: E402

FAILURES = []

SIZES = [
    ("the mockup's canvas", 1536, 1024),
    ("a 720p laptop", 1280, 720),
    ("a 768p laptop", 1366, 768),
    ("1080p", 1920, 1080),
    ("1440p", 2560, 1440),
    ("a 4:3 window", 1024, 768),
    ("a tablet, upright", 768, 1024),
    ("a phone, landscape", 844, 390),
    ("a small phone, landscape", 667, 375),
    ("a phone, upright", 390, 844),
    ("a small phone, upright", 360, 640),
]
GROUPS = {"TopPills", "TopRight", "LeftColumn", "BottomGroup", "RightColumn"}
# Roblox's menu and chat buttons, top left. Anything of ours under them
# cannot be pressed.
ROBLOX_ICONS = (0, 0, 100, 52)
MIN_TEXT = 9
HUD_PANELS = ["PetsPanel", "ShopPanel", "UpgradePanel", "QuestPanel", "PetIndexPanel",
              "LeaderboardPanel", "DailyPanel", "TradePanel", "CodesPanel",
              "MerchantPanel", "EventPanel", "BoostsPanel", "FusionPanel",
              "PlaytimePanel", "SpinWheelPanel"]
# Each banner slide and the panel its View button must open.
FEATURED = {"Traveling Merchant": "MerchantPanel", "Lucky Spin": "SpinWheelPanel",
            "Playtime Rewards": "PlaytimePanel", "Coin Boosts": "BoostsPanel",
            "Pet Fusion": "FusionPanel"}
# Where the mockup puts things, at its own size: (x, y, w, h).
MOCKUP = {
    "Profile": (15, 84, 358, 124),
    "Nav": (15, 218, 265, 430),
    "MyPets": (296, 637, 354, 328),
    "HUD_AutoCollect": (708, 847, 118, 118),
    "Quests": (1163, 85, 357, 260),
    "Featured": (1163, 365, 357, 162),
    "Detail": (1163, 556, 357, 382),
    "Dock_Daily": (1342, 16, 58, 58),
}


def check(label, fn):
    try:
        print("   ok  %-36s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-36s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-36s crashed: %r" % (label, e))
        FAILURES.append(label)


def overlap(a, b, slack=0.5):
    return (a[0] + slack < b[0] + b[2] and b[0] + slack < a[0] + a[2]
            and a[1] + slack < b[1] + b[3] and b[1] + slack < a[1] + a[3])


def touch_controls(W, H):
    """Roblox's own thumbstick and jump button, where its PlayerModule puts
    them (TouchThumbstick / TouchJump)."""
    if min(W, H) <= 500:
        return [("the jump button", (W - 95, H - 90, 70, 70)),
                ("the thumbstick", (25, H - 90, 70, 70))]
    return [("the jump button", (W - 170, H - 210, 120, 120)),
            ("the thumbstick", (60, H - 220, 120, 120))]


def main():
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        lua, mock, gui, _ = check_client.boot(loopback=True)
    if lua is None:
        print("   x the client did not boot")
        return 1
    lua.execute(SCHEDULER)
    tick = lua.eval("__TICK")
    errs = lua.eval("function() local e = __THREAD_ERRORS; __THREAD_ERRORS = {}; return e end")
    # The loading screen and the welcome banner belong to the first seconds
    # of play; this measures the HUD a player sees after them.
    lua.execute("""
        local g = game:GetService("Players").LocalPlayer.PlayerGui
        for _, n in ipairs({"LoadScreen", "WelcomeGui", "StarPetsBuildBadge"}) do
            local x = g:FindFirstChild(n); if x then x:Destroy() end
        end
    """)

    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    mod = lambda n: mock["MODULES"][holder["FindFirstChild"](holder, n)]  # noqa: E731
    DM, PS, QS, ES = mod("DataManager"), mod("PetService"), mod("QuestService"), mod("EventService")
    me = mock["Players"].LocalPlayer
    data = DM.GetData(me)
    assert data is not None, "the join handler loaded no data"
    hud_gui = gui["FindFirstChild"](gui, "MysticPetsHUD")

    press = lua.eval("""function(b)
        b.MouseButton1Down:Fire(); b.MouseButton1Up:Fire(); b.MouseButton1Click:Fire()
    end""")
    sync_fn = lua.eval("""function(p, d)
        game.ReplicatedStorage.Remotes.DataUpdated:FireClient(p, d)
    end""")

    def sync():
        sync_fn(me, data)
        tick(2)

    def find(name):
        return hud_gui["FindFirstChild"](hud_gui, name, True)

    def need(name):
        b = find(name)
        assert b is not None, "the HUD has no %s" % name
        return b

    def no_errors():
        e = [str(x) for x in errs().values()]
        assert not e, "something threw: %s" % e[0].splitlines()[0][:160]

    def screen(W, H):
        render_gui.set_screen(lua, W, H)
        tree = render_gui.dump(lua, gui)
        boxes = [b for b in render_gui.layout(tree, W, H) if b.gui == "MysticPetsHUD"]
        hud = next(c for c in tree["kids"] if c["name"] == "MysticPetsHUD")
        roots = [c for c in hud["kids"] if c["name"] == "HUDRoot"]
        assert len(roots) == 1, "%d HUD roots on screen at %dx%d" % (len(roots), W, H)
        pieces = []
        for c in roots[0]["kids"]:
            if c["cls"] not in render_gui.GUI_CLASSES or c["name"] == "MoreMenu":
                continue
            if c["name"] in GROUPS:
                pieces += [k for k in c["kids"] if k["cls"] in render_gui.GUI_CLASSES]
            else:
                pieces.append(c)
        by = {id(b.node): b for b in boxes}
        shown = [(p["name"], by[id(p)]) for p in pieces if id(p) in by]
        # What is inside each piece, so a label hanging out of its card (a
        # value wider than its pill, say) is caught even though the cards
        # themselves are apart.
        inside = []
        def walk(node, owner):
            for k in node["kids"]:
                if id(k) in by:
                    inside.append((owner, k["name"], by[id(k)]))
                walk(k, owner)
        for p in pieces:
            if id(p) in by:
                walk(p, p["name"])
        screen.inside = inside
        return boxes, shown, "full" if any(c["name"] == "LeftColumn" for c in roots[0]["kids"]) else "compact"

    # ---- geometry, at every size ------------------------------------------
    print("the HUD at %d screen sizes:" % len(SIZES))

    def measure(label, W, H):
        def run():
            boxes, shown, mode = screen(W, H)
            assert len(shown) >= 8, "only %d pieces on screen" % len(shown)
            off = ["%s (%d,%d %dx%d)" % (n, b.x, b.y, b.w, b.h) for n, b in shown
                   if b.x < -0.5 or b.y < -0.5 or b.x + b.w > W + 0.5 or b.y + b.h > H + 0.5]
            assert not off, "off screen: %s" % ", ".join(off[:3])
            clash = []
            for i in range(len(shown)):
                for j in range(i + 1, len(shown)):
                    if overlap(shown[i][1].rect, shown[j][1].rect):
                        clash.append("%s/%s" % (shown[i][0], shown[j][0]))
            assert not clash, "drawn over each other: %s" % ", ".join(clash[:3])
            at = dict(shown)
            out = []
            for owner, name, b in screen.inside:
                o = at[owner]
                if (b.x < o.x - 1 or b.y < o.y - 1 or b.x + b.w > o.x + o.w + 1
                        or b.y + b.h > o.y + o.h + 1):
                    out.append("%s/%s" % (owner, name))
            assert not out, "hanging out of its card: %s" % ", ".join(out[:3])
            under = [n for n, b in shown if overlap(b.rect, ROBLOX_ICONS)]
            assert not under, "under Roblox's own buttons: %s" % under
            if mode == "compact":
                for what, r in touch_controls(W, H):
                    hit = [n for n, b in shown if overlap(b.rect, r)]
                    assert not hit, "%s sits on %s" % (hit, what)
                small = [n for n, b in shown
                         if str(b.node["cls"]) == "TextButton" and (b.w < 44 or b.h < 44)]
                assert not small, "under the 44-point touch target: %s" % small
            names = {n for n, _ in shown}
            assert "HUD_Mute" in names, "no sound switch on screen"
            # Every label fits its box and can be read.
            bad = []
            for b in boxes:
                node = b.node
                if node["cls"] not in render_gui.TEXT_CLASSES:
                    continue
                txt = str(node["p"].get("Text", ""))
                if not txt.strip() or b.visible_rect() is None:
                    continue
                face, size, lines = render_gui.text_fit(node, b.w, b.h, b.k)
                p = node["p"]
                if not p.get("TextScaled") and not p.get("TextWrapped"):
                    wide = max(render_gui._line_width(ln, face, size) for ln in lines)
                    if wide > b.w + 1:
                        bad.append("%s %r spills (%d > %d)" % (node["name"], txt[:18], wide, b.w))
                if p.get("TextWrapped") and len(lines) * size > b.h + 1:
                    bad.append("%s %r runs out of its box" % (node["name"], txt[:18]))
                if size < MIN_TEXT:
                    bad.append("%s %r drawn at %.1fpx" % (node["name"], txt[:18], size))
            assert not bad, "%d label(s): %s" % (len(bad), "; ".join(bad[:3]))
            return "%-7s %d pieces" % (mode, len(shown))
        return run

    for label, W, H in SIZES:
        check("%s %dx%d" % (label, W, H), measure(label, W, H))

    def t_as_drawn():
        boxes, shown, mode = screen(1536, 1024)
        assert mode == "full", "the mockup's own canvas gets the %s layout" % mode
        at = {str(b.node["name"]): b for b in boxes}
        moved = []
        for name, (x, y, w, h) in MOCKUP.items():
            b = at.get(name)
            if b is None:
                moved.append("%s missing" % name)
            elif max(abs(b.x - x), abs(b.y - y), abs(b.w - w), abs(b.h - h)) > 1.5:
                moved.append("%s at (%d,%d %dx%d), drawn at (%d,%d %dx%d)"
                             % (name, b.x, b.y, b.w, b.h, x, y, w, h))
        assert not moved, "; ".join(moved[:2])
        return "%d cards where the mockup puts them" % len(MOCKUP)

    check("as drawn, at 1536x1024", t_as_drawn)

    # ---- every panel, from the HUD ------------------------------------------
    print("\nreaching every panel:")

    def reach(W, H):
        def run():
            screen(W, H)
            more_items = lua.eval("""function(hud)
                local m = hud:FindFirstChild("MoreMenu", true)
                local out = {}
                if m then for _, d in ipairs(m:GetDescendants()) do
                    if d.ClassName == "TextButton" and string.sub(d.Name, 1, 5) == "Dock_" then
                        out[#out + 1] = d.Name
                    end
                end end
                return out
            end""")(hud_gui)
            in_more = {str(n) for n in more_items.values()}
            docks = sorted({str(d._p.Name) for d in hud_gui["GetDescendants"](hud_gui).values()
                            if str(d._p.ClassName) == "TextButton"
                            and str(d._p.Name).startswith("Dock_")})
            opened = set()
            for name in docks:
                if name in ("Dock_More", "Dock_Home"):
                    continue
                ctrl.CloseAll()
                if name in in_more:
                    press(need("Dock_More"))
                    tick(1)
                    assert need("MoreMenu")._p.Visible, "More did not open"
                press(need(name))
                tick(2)
                got = [p for p in HUD_PANELS if gui["FindFirstChild"](gui, p) is not None]
                assert got, "%s opened nothing" % name
                opened.update(got)
                if find("MoreMenu") is not None:
                    assert not find("MoreMenu")._p.Visible, \
                        "the More menu stayed open over %s" % got[0]
            ctrl.CloseAll()
            no_errors()
            missing = [p for p in HUD_PANELS if p not in opened]
            assert not missing, "no HUD button opens %s" % missing
            return "all %d panels, from %d buttons" % (len(HUD_PANELS), len(docks) - 1)
        return run

    check("on a computer", reach(1536, 1024))
    check("on a phone", reach(390, 844))

    def t_home_closes():
        screen(1536, 1024)
        press(need("Dock_Pets")); tick(2)
        assert gui["FindFirstChild"](gui, "PetsPanel") is not None, "Pets did not open"
        press(need("Dock_Home")); tick(2)
        assert gui["FindFirstChild"](gui, "PetsPanel") is None, "Home left the Pets panel open"
        return "Home closes what is open"

    check("Home", t_home_closes)

    def t_open_is_marked():
        screen(1536, 1024)
        ctrl.CloseAll()
        press(need("Dock_Shop")); tick(1)
        lua.eval("function(dt) game:GetService('RunService').Heartbeat:Fire(dt) end")(0.4)
        on = [n for n in ("Dock_Home", "Dock_Pets", "Dock_Shop")
              if float(need(n)._p.BackgroundTransparency) < 0.5]
        ctrl.CloseAll()
        lua.eval("function(dt) game:GetService('RunService').Heartbeat:Fire(dt) end")(0.4)
        home = float(need("Dock_Home")._p.BackgroundTransparency) < 0.5
        assert on == ["Dock_Shop"], "with the Shop open, the menu marks %s" % on
        assert home, "with everything closed, Home is not marked"
        return "the open panel's row is lit, Home when none is"

    check("the menu shows what is open", t_open_is_marked)

    # ---- pets ---------------------------------------------------------------
    print("\nyour pets:")
    screen(1536, 1024)
    grant = lua.eval("""function(ps, p, name, rarity, uid, mutation, locked)
        return ps.GrantPet(p, { name = name, rarity = rarity, uniqueId = uid,
            mutation = mutation, locked = locked }, true)
    end""")
    PETS = [("dragon", "Epic", "h-dragon", "Shiny", False),
            ("snow ram", "Legendary", "h-ram", None, True),
            ("cat", "Common", "h-cat", None, False)]
    for args in PETS:
        grant(PS, me, *args)
    data.EquippedPets = lua.eval('{"h-dragon", "h-ram", "h-cat"}')
    data.GP_PetSlots = False
    sync()

    def cells(prefix):
        return sorted(str(d._p.Name) for d in hud_gui["GetDescendants"](hud_gui).values()
                      if str(d._p.Name).startswith(prefix))

    def t_cards():
        pets, empty, locked = cells("HUD_Pet_"), cells("HUD_Slot_"), cells("HUD_SlotLocked_")
        first = need("HUD_Pet_1")
        st = first["FindFirstChildOfClass"](first, "UIStroke")
        assert float(st._p.Thickness) == 3, \
            "the pet shown in the detail card is not the one marked in My Pets"
        assert len(pets) == 3, "3 pets equipped, %d cards" % len(pets)
        assert not empty, "3 of 3 slots used and %d empty slots shown" % len(empty)
        assert len(locked) == 3, "3 slots to buy, %d shown" % len(locked)
        ram = need("HUD_Pet_2")
        assert ram["FindFirstChild"](ram, "Locked") is not None, "the locked Snow Ram shows no lock"
        assert str(need("PetsPill")["FindFirstChild"](need("PetsPill"), "Value")._p.Text) == "3/3"
        return "3 cards, 3 slots to buy, the lock shown"

    check("the cards are the equipped pets", t_cards)

    def t_select():
        first = need("HUD_Pet_1")
        press(need("HUD_Pet_3")); tick(1)
        got = str(need("DetailName")._p.Text)
        assert got == "Cat", "picked the cat, the card shows %r" % got
        # Picking restyles a border; it does not rebuild every 3D preview.
        same = lua.eval("function(a, b) return rawequal(a, b) end")
        assert same(need("HUD_Pet_1"), first), "picking a pet rebuilt all the pet cards"
        cat = need("HUD_Pet_3")
        st = cat["FindFirstChildOfClass"](cat, "UIStroke")
        assert float(st._p.Thickness) == 3, "the picked card is not marked"
        press(need("HUD_Pet_1")); tick(1)
        got = str(need("DetailName")._p.Text)
        assert got == "Dragon", "picked the dragon, the card shows %r" % got
        return "pick a card, the detail shows it"

    check("selecting a pet", t_select)

    def t_income_is_paid():
        # The dragon alone: what the card says must be what the server pays.
        data.EquippedPets = lua.eval('{"h-dragon"}')
        data.RebirthMultiplier = 2
        data.GP_2xCoins = True
        sync()
        coins = PS.GetPlayerIncome(me)
        coins = coins[0] if isinstance(coins, tuple) else coins
        fmt = lua.globals()._G.MysticPets.fmt
        shown = str(need("Value1")._p.Text)
        assert shown == "%s/s" % fmt(coins), \
            "the card says %s, the server pays %s a second" % (shown, fmt(coins))
        bonus = str(need("Value3")._p.Text)
        assert bonus == "×4", "a Shiny pet's bonus shows %r" % bonus
        data.RebirthMultiplier = 1
        data.GP_2xCoins = False
        return "%s, exactly what the server pays (Shiny x4, 2x pass, rebirth x2)" % shown

    check("the income shown is the income paid", t_income_is_paid)

    def t_unequip():
        data.EquippedPets = lua.eval('{"h-dragon", "h-ram", "h-cat"}')
        sync()
        press(need("HUD_Pet_3")); tick(1)
        press(need("HUD_Unequip")); tick(3)
        eq = [str(u) for u in data.EquippedPets.values()]
        assert "h-cat" not in eq, "pressed Unequip on the cat; the server still has it out"
        assert len(cells("HUD_Pet_")) == 2, "the card is still shown"
        return "the server let it go, and the card went with it"

    check("Unequip", t_unequip)

    def t_lock():
        press(need("HUD_Pet_1")); tick(1)
        press(need("HUD_Lock")); tick(3)
        dragon = [p for p in data.Pets.values() if str(p.uniqueId) == "h-dragon"][0]
        assert dragon.locked is True, "pressed lock; the server did not lock it"
        assert need("HUD_Delete")._p.Active is False, "a locked pet can still be deleted from the card"
        press(need("HUD_Lock")); tick(3)
        assert not dragon.locked, "pressed again; still locked"
        return "locks on the server; a locked pet's Delete is off"

    check("Lock", t_lock)

    def t_delete_asks():
        before = len(list(data.Pets.values()))
        press(need("HUD_Pet_1")); tick(1)
        press(need("HUD_Delete")); tick(3)
        assert len(list(data.Pets.values())) == before, "one press deleted a pet"
        assert str(need("HUD_Delete")._p.Text) == "Sure?", "the first press did not ask"
        press(need("HUD_Delete")); tick(3)
        left = [str(p.uniqueId) for p in data.Pets.values()]
        assert "h-dragon" not in left, "pressed twice; the pet is still there"
        no_errors()
        return "first press asks, second deletes"

    check("Delete asks first", t_delete_asks)

    def t_equip_best():
        data.EquippedPets = lua.eval("{}")
        sync()
        press(need("HUD_EquipBest")); tick(3)
        eq = [str(u) for u in data.EquippedPets.values()]
        assert eq and eq[0] == "h-ram", "Equip Best put out %s, not the Snow Ram first" % eq
        return "the best pets go out (%s)" % ", ".join(eq)

    check("Equip Best", t_equip_best)

    # ---- the rest of the cards ---------------------------------------------
    print("\nthe cards:")

    def t_rebirth_bar():
        data.TotalCoinsEarned = 25000
        data.Rebirths = 0
        sync()
        got = str(need("Progress")._p.Text)
        assert "25.0K / 50.0K" in got, "25K earned of 50K, the bar says %r" % got
        fill = need("Progress").Parent["FindFirstChild"](need("Progress").Parent, "Fill")
        assert abs(float(fill._p.Size["X"]["Scale"]) - 0.5) < 1e-6, "the bar is not half full"
        return "%r, half full" % got

    check("the rebirth bar", t_rebirth_bar)

    def t_quests():
        heartbeat = lua.eval("function(dt) game:GetService('RunService').Heartbeat:Fire(dt) end")
        heartbeat(21)
        tick(2)
        real = {str(q.name) for q in QS.GetAll(me).values() if not q.claimed}
        rows = [need("HUD_Quest_%d" % i) for i in (1, 2, 3)]
        names = [str(r["FindFirstChild"](r, "QuestName")._p.Text) for r in rows if r._p.Visible]
        assert names, "the quest card is empty"
        fake = [n for n in names if n not in real]
        assert not fake, "the quest card shows %s, which are not open quests" % fake
        return "%s" % ", ".join(names)

    check("the quest card is the real quests", t_quests)

    def t_event():
        heartbeat = lua.eval("function(dt) game:GetService('RunService').Heartbeat:Fire(dt) end")
        ES.Stop()
        heartbeat(31); tick(2)
        assert not need("HUD_Event")._p.Visible, "the event card is up with no event on"
        cfg = mock["MODULES"][lua.eval("game.ReplicatedStorage.Shared.GameConfig")]
        first = lua.eval("function(t) for k in pairs(t) do return k end end")(cfg.Events)
        ES.Start(first)
        heartbeat(31); tick(2)
        card = need("HUD_Event")
        assert card._p.Visible, "an event started and its card never showed"
        name = str(card["FindFirstChild"](card, "EventName")._p.Text)
        assert name == str(cfg.Events[first].name), "the card names %r" % name
        press(card); tick(2)
        assert gui["FindFirstChild"](gui, "EventPanel") is not None, "the card opens nothing"
        ctrl.CloseAll()
        ES.Stop()
        return "hidden, then %r, and it opens the event" % name

    check("the event card, only during an event", t_event)

    def t_featured():
        title = need("FeatureTitle")
        first = str(title._p.Text)
        press(need("HUD_FeatureNext")); tick(1)
        second = str(title._p.Text)
        assert second != first, "the next arrow did not change the banner"
        press(need("HUD_FeaturePrev")); tick(1)
        assert str(title._p.Text) == first, "the back arrow did not go back"
        press(need("HUD_FeatureView")); tick(2)
        got = [p for p in HUD_PANELS if gui["FindFirstChild"](gui, p) is not None]
        want = FEATURED.get(first)
        assert want, "the banner shows %r, which is not a feature in the game" % first
        assert got == [want], "View on %r opened %s, not %s" % (first, got, want)
        ctrl.CloseAll()
        return "%r -> %r -> back; View opens %s" % (first, second, got[0])

    check("the featured banner", t_featured)

    # ---- switches -----------------------------------------------------------
    print("\nthe switches:")

    def state(name):
        t = need(name)
        return str(t["FindFirstChild"](t, "State")._p.Text)

    def t_autocollect_unowned():
        data.GP_AutoCollect = False
        sync()
        assert state("HUD_AutoCollect") == "GET", "not owned, the switch says %s" % state("HUD_AutoCollect")
        press(need("HUD_AutoCollect")); tick(2)
        assert gui["FindFirstChild"](gui, "ShopPanel") is not None, "GET did not open the Shop"
        ctrl.CloseAll()
        return "GET, and it opens the Shop"

    check("Auto Collect, not owned", t_autocollect_unowned)

    def t_autocollect_owned():
        data.GP_AutoCollect = True
        data.AutoCollectOff = False
        sync()
        assert state("HUD_AutoCollect") == "ON", "owned, the switch says %s" % state("HUD_AutoCollect")
        press(need("HUD_AutoCollect")); tick(3)
        assert data.AutoCollectOff is True, "switched off; the server's save says otherwise"
        assert state("HUD_AutoCollect") == "OFF", "switched off; it still says %s" % state("HUD_AutoCollect")

        # And the collector itself listens: stand on a coin with it off.
        orbs = lua.eval("workspace.Orbs")
        coin = [o for o in orbs["GetChildren"](orbs).values() if str(o._p.Name) == "CoinOrb"]
        assert coin, "no coins in the world to stand on"
        root = me.Character["FindFirstChild"](me.Character, "HumanoidRootPart")
        hb = lua.eval("function(dt) game:GetService('RunService').Heartbeat:Fire(dt) end")
        took = None
        for c in coin:
            root.CFrame = c._p.CFrame
            before = float(data.Coins)
            hb(0.1)
            if data.AutoCollectOff is True and float(data.Coins) > before:
                took = str(c._p.Name)
                break
        assert took is None, "switched off, and the collector still took a coin"
        press(need("HUD_AutoCollect")); tick(3)
        assert data.AutoCollectOff is False, "switched back on; the save still says off"
        got = False
        for c in coin:
            root.CFrame = c._p.CFrame
            before = float(data.Coins)
            hb(0.1)
            if float(data.Coins) > before:
                got = True
                break
        assert got, "switched on, standing on coins, and nothing was collected"
        return "off stops the collector, on starts it, both saved"

    check("Auto Collect, owned", t_autocollect_owned)

    def t_autocollect_guard():
        data.AutoCollectOff = False
        fire = lua.eval("function(p, v) game.ReplicatedStorage.Remotes.SetAutoCollect.OnServerEvent:Fire(p, v) end")
        for junk in ("off", 0, None):
            fire(me, junk)
        assert data.AutoCollectOff is False, "a non-boolean changed the save"
        return "anything but true or false is ignored"

    check("its remote takes only a boolean", t_autocollect_guard)

    # ---- layout switches, and what drops in from the top --------------------
    print("\nmoving between screens:")

    def t_switch():
        for W, H in ((1536, 1024), (390, 844), (844, 390), (1280, 720)):
            _, shown, mode = screen(W, H)
            names = [n for n, _ in shown]
            dup = {n for n in names if names.count(n) > 1}
            assert not dup, "at %dx%d, two of %s" % (W, H, sorted(dup))
            assert find("HUD_Mute") is not None, "the sound switch went missing at %dx%d" % (W, H)
        no_errors()
        return "computer -> phone -> phone -> computer, one HUD each time"

    check("switching layouts", t_switch)

    def t_toast_below():
        for W, H in ((1536, 1024), (390, 844)):
            _, shown, _ = screen(W, H)
            pills = [b for n, b in shown if n in ("Coins", "Gems", "PetsPill")]
            bottom = max(b.y + b.h for b in pills)
            lua.globals()._G.MysticPets.showToast("info", "hello")
            mock["FLUSH_TWEENS"]()
            t = gui["FindFirstChild"](gui, "ToastGui")
            frame = [c for c in t["GetChildren"](t).values() if str(c._p.ClassName) == "Frame"][0]
            y = float(frame._p.Position["Y"]["Offset"])
            assert y >= bottom, "at %dx%d a toast lands at y=%d, over the counters (to %d)" % (W, H, y, bottom)
        return "toasts land under the counters"

    check("toasts drop in below the counters", t_toast_below)

    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nhud: on screen at every size, nothing overlapping, every button does its job")
    return 0


if __name__ == "__main__":
    sys.exit(main())
