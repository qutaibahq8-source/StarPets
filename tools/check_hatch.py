#!/usr/bin/env python3
"""The hatch reveal shows the pet, fits the screen, and cleans up after itself.

The reveal is the moment a pet simulator is built around, and it had three
problems.

  1. IT SHOWED A LETTER        the card drew the first letter of the pet's name
                               in a circle — hatch a dragon, see a "D". It now
                               builds the real model in a ViewportFrame.
  2. TEN CARDS WERE 1,508 WIDE one row of 140-wide cards ran off a laptop and
                               far off a phone. It is a grid now, sized to fit.
  3. NOTHING SAID "NEW"        the server already knew a species was new (it
                               stamps the Pet Index) and never told the reveal.

And one thing it must not start doing: each card turns its model every frame,
and a spinner left running after the reveal closes would leak one connection
per hatch — thousands in a session.
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
    lua, mock, gui, _ = check_client.boot()
    print()
    G = lua.globals()
    # Run the short delays now — the reveal staggers its cards by fractions of
    # a second — but NOT the eight-second auto-close. Firing every delay at
    # once closed the reveal the instant it opened, and every card check then
    # looked at nothing.
    lua.execute("task.delay = function(t, f, ...) if f and (t or 0) < 3 then f(...) end end")

    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    hatch_inst = ui["FindFirstChild"](ui, "HatchPanel")
    Hatch = mock["MODULES"][hatch_inst]
    G["script"] = hatch_inst

    def screen_size(w, h):
        lua.execute("""
            local cam = workspace.CurrentCamera or Instance.new("Camera")
            cam.ViewportSize = Vector2.new(%d, %d)
            cam.CFrame = cam.CFrame or CFrame.new(0, 20, 40)
            workspace.CurrentCamera = cam
        """ % (w, h))

    def reveal(pets_src):
        old = gui["FindFirstChild"](gui, "HatchResultGui")
        if old is not None:
            old["Destroy"](old)
        Hatch.ShowHatchResult(lua.eval(pets_src), "CoolEgg")
        return gui["FindFirstChild"](gui, "HatchResultGui")

    def cards_of(screen):
        return [c for c in screen["GetChildren"](screen).values()
                if str(c._p.Name) == "HatchCard"]

    def rect(c, W, H):
        pos = c._p.Position
        # The card's FINAL size is tweened to; read the target from the tween
        # by using the cardWidth the reveal computed, which the circle inside
        # it is sized against. The circle's own size is the honest signal.
        x = float(pos["X"]["Scale"]) * W + float(pos["X"]["Offset"])
        y = float(pos["Y"]["Scale"]) * H + float(pos["Y"]["Offset"])
        return x, y

    def t_shows_the_pet():
        screen_size(1280, 720)
        s = reveal('{ {name="dragon", rarity="Epic", uniqueId="r1", isNew=false} }')
        cards = cards_of(s)
        assert len(cards) == 1, "one hatch made %d cards" % len(cards)
        circle = cards[0]["FindFirstChild"](cards[0], "PetCircle")
        view = circle["FindFirstChild"](circle, "PetView") if circle else None
        assert view is not None, ("the card has no ViewportFrame — the pet is "
                                  "still shown as a letter")
        model = view["FindFirstChildOfClass"](view, "Model")
        assert model is not None, "the ViewportFrame is empty"
        parts = [d for d in model["GetDescendants"](model).values()
                 if str(d._p.ClassName) in ("Part", "WedgePart")]
        assert len(parts) >= 6, "the model has only %d parts" % len(parts)
        letters = [d for d in circle["GetDescendants"](circle).values()
                   if str(d._p.ClassName) == "TextLabel" and len(str(d._p.Text or "")) == 1]
        assert not letters, "the letter fallback is showing alongside the model"
        return "a %d-part dragon in the card, no letter" % len(parts)

    def fits(W, H):
        screen_size(W, H)
        pets = ",".join('{name="cat", rarity="Common", uniqueId="c%d"}' % i for i in range(10))
        s = reveal("{%s}" % pets)
        cards = cards_of(s)
        assert len(cards) == 10, "a ten-hatch made %d cards" % len(cards)
        off = []
        for c in cards:
            x, y = rect(c, W, H)
            circle = c["FindFirstChild"](c, "PetCircle")
            side = float(circle._p.Size["X"]["Offset"])
            # The card is at least the circle plus its margins.
            if x < 0 or y < 0 or x + side + 16 > W or y + side + 60 > H:
                off.append("(%d,%d)" % (x, y))
        assert not off, "on a %dx%d screen cards land off it at %s" % (W, H, off[:4])
        return len(cards)

    def t_ten_fit_a_laptop():
        return "all %d cards on a 1280x720 screen" % fits(1280, 720)

    def t_ten_fit_a_phone():
        return "all %d cards on a 390x844 phone" % fits(390, 844)

    def t_new_is_called_out():
        screen_size(1280, 720)
        s = reveal('{ {name="owl", rarity="Uncommon", uniqueId="n1", isNew=true},'
                   '  {name="cat", rarity="Common", uniqueId="n2", isNew=false} }')
        cards = cards_of(s)
        ribbons = [c["FindFirstChild"](c, "NewRibbon") is not None for c in cards]
        assert ribbons.count(True) == 1, ("expected one NEW! ribbon for one new "
                                          "species, got %s" % ribbons)
        return "NEW! on the first-ever species only"

    def t_spinner_stops():
        screen_size(1280, 720)
        s = reveal('{ {name="fox", rarity="Uncommon", uniqueId="s1"} }')
        card = cards_of(s)[0]
        circle = card["FindFirstChild"](card, "PetCircle")
        view = circle["FindFirstChild"](circle, "PetView")
        cam = view["FindFirstChildOfClass"](view, "Camera")
        rs = lua.eval('game:GetService("RunService")')
        step = lua.eval("function(rs) rs.RenderStepped:Fire(0.1) end")
        step(rs)
        moving = str(cam._p.CFrame.p.X)
        step(rs)
        assert str(cam._p.CFrame.p.X) != moving, "the model does not turn at all"
        s["Destroy"](s)
        after = str(cam._p.CFrame.p.X)
        for _ in range(5):
            step(rs)
        assert str(cam._p.CFrame.p.X) == after, ("the spinner kept running after "
                                                 "the reveal closed — one leaked "
                                                 "connection per hatch")
        return "turns while open, stops the moment it closes"

    def t_new_flag_is_not_saved():
        # The server copies the pet before adding isNew, so the flag never
        # reaches the save. Checked against EggService's source, where the
        # decision lives.
        src = (ROOT / "src/Server/EggService.lua").read_text()
        assert "shown.isNew" in src and "newPet.isNew" not in src, \
            "isNew is set on the pet that is saved, so it is written into the save"
        return "the flag rides on a copy, not the saved pet"

    # ---------------------------------------------------- clicking an egg
    remotes = lua.eval("game.ReplicatedStorage.Remotes")
    hatch_remote = remotes["FindFirstChild"](remotes, "HatchEgg")
    click_egg = lua.eval("function(r, id) r.OnClientEvent:Fire(id) end")
    eggs = [str(e.id) for e in lua.eval("_G.MysticPets.GameConfig.Eggs").values()]
    egg_names = {str(e.id): str(e.name) for e in lua.eval("_G.MysticPets.GameConfig.Eggs").values()}
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]

    def panel_root(screen):
        frames = [c for c in screen["GetChildren"](screen).values()
                  if str(c._p.ClassName) == "Frame"]
        return frames[0] if frames else None

    def focused_card(screen):
        cards = [d for d in screen["GetDescendants"](screen).values()
                 if str(d._p.Name).startswith("EggCard_")]
        first = min(cards, key=lambda c: int(c._p.LayoutOrder or 0))
        has_edge = first["FindFirstChild"](first, "Focus") is not None
        return str(first._p.Name)[8:], has_edge

    def t_egg_click_uses_controller():
        screen_size(390, 844)
        target = eggs[-1]
        click_egg(hatch_remote, target)
        s = gui["FindFirstChild"](gui, "HatchPanel")
        assert s is not None, "clicking an egg opened nothing"
        root = panel_root(s)
        assert root is not None and root["FindFirstChildOfClass"](root, "UISizeConstraint") \
            is not None, ("the hatch panel opened by clicking an egg was not fitted "
                          "to the screen — a 600-wide panel on a 390-wide phone")
        return "opened through UIController, fitted to a phone"

    def t_egg_click_focuses_that_egg():
        target = eggs[-1]
        s = gui["FindFirstChild"](gui, "HatchPanel")
        got, edge = focused_card(s)
        assert got == target, ("clicked the %s, but the panel leads with the %s"
                               % (target, got))
        assert edge, "the clicked egg's card is not outlined"
        hdr = [str(d._p.Text) for d in s["GetDescendants"](s).values()
               if str(d._p.ClassName) == "TextLabel" and "🥚" in str(d._p.Text or "")]
        assert any(egg_names[target] in h for h in hdr), \
            "the header does not name the clicked egg (%s)" % hdr
        return "%s first, outlined, named in the header" % egg_names[target]

    def t_second_egg_refocuses():
        click_egg(hatch_remote, eggs[0])
        s = gui["FindFirstChild"](gui, "HatchPanel")
        assert s is not None, ("clicking a second egg CLOSED the panel — the "
                               "world click toggled it like a HUD button")
        got, _ = focused_card(s)
        assert got == eggs[0], "clicked the %s second, panel still leads with %s" % (eggs[0], got)
        return "still open, now on the %s" % egg_names[eggs[0]]

    def t_one_panel_at_a_time():
        ctrl.TogglePanel("PetsPanel", lua.eval("{Pets={}, EquippedPets={}}"))
        assert gui["FindFirstChild"](gui, "PetsPanel") is not None, "PetsPanel did not open"
        click_egg(hatch_remote, eggs[0])
        assert gui["FindFirstChild"](gui, "PetsPanel") is None, \
            "clicking an egg stacked the hatch panel on top of the Pets panel"
        return "the Pets panel closed when an egg was clicked"

    # ------------------------------------------- the price is the charge
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    me = mock["Players"].LocalPlayer
    sent = lua.eval("{}")
    lua.eval("""function(remotes, sent)
        for _, n in ipairs({"Notification", "HatchResult"}) do
            local r = remotes:FindFirstChild(n)
            r.FireClient = function(_, _, ...) table.insert(sent, {n, ...}) end
        end
    end""")(remotes, sent)
    hatch_on_server = lua.eval(
        "function(r, p, id, n) r.OnServerEvent:Fire(p, id, n) end")

    def fresh_data():
        res = DM.LoadPlayer(me)
        d = res[0] if isinstance(res, tuple) else res
        assert d is not None, "no player data"
        return d

    def drain():
        out = [[str(v) if not lua_type(v) else v for v in row.values()]
               for row in sent.values()]
        for k in list(sent.keys()):
            sent[k] = None
        return out

    lua_type = lua.eval("function(v) return type(v) == 'table' end")

    def t_starter_x10_label_is_the_charge():
        d = fresh_data()
        d.HasClaimedFreeEgg = False
        d.Coins = 100000
        ctrl.CloseAll()
        Hatch.Build(d, "StarterEgg")
        s = gui["FindFirstChild"](gui, "HatchPanel")
        card = [x for x in s["GetDescendants"](s).values()
                if str(x._p.Name) == "EggCard_StarterEgg"][0]
        x10 = [str(b._p.Text) for b in card["GetChildren"](card).values()
               if str(b._p.ClassName) == "TextButton" and str(b._p.Text).startswith("x10")][0]
        drain()
        hatch_on_server(hatch_remote, me, "StarterEgg", 10)
        charged = 100000 - int(float(d.Coins))
        shown = str(lua.eval("_G.MysticPets.formatNum")(charged))
        assert "FREE x10" not in x10, ("the x10 button says %r, and pressing it "
                                       "charged %d coins" % (x10.replace("\n", " "), charged))
        assert shown in x10, ("the x10 button says %r; the server charged %s"
                              % (x10.replace("\n", " "), shown))
        return "label %r, server charged %s" % (x10.replace("\n", " "), shown)

    def t_partial_batch_says_why():
        d = fresh_data()
        d.HasClaimedFreeEgg = True
        d.Coins = 450
        for k in list(d.Pets.keys()):
            d.Pets[k] = None
        drain()
        hatch_on_server(hatch_remote, me, "StarterEgg", 10)
        rows = drain()
        results = [r for r in rows if r[0] == "HatchResult"]
        notes = [r[2] for r in rows if r[0] == "Notification"]
        assert results, "nothing hatched at all"
        got = len(list(results[0][1].values()))
        assert got == 3, "450 coins at 150 each hatched %d" % got
        assert any("3 of 10" in str(n) for n in notes), \
            ("an x10 stopped after %d and the player was told nothing (notes: %s)"
             % (got, notes))
        return "3 hatched, told: %r" % [n for n in notes if "of 10" in str(n)][0]

    print("hatch reveal:")
    check("shows the pet, not a letter", t_shows_the_pet)
    check("ten cards fit a laptop", t_ten_fit_a_laptop)
    check("ten cards fit a phone", t_ten_fit_a_phone)
    check("a new species is called out", t_new_is_called_out)
    check("the spinner stops on close", t_spinner_stops)
    check("isNew is never saved", t_new_flag_is_not_saved)
    print("\nclicking an egg in the world:")
    check("opens like every other panel", t_egg_click_uses_controller)
    check("opens on the egg clicked", t_egg_click_focuses_that_egg)
    check("a second egg refocuses", t_second_egg_refocuses)
    check("one panel at a time", t_one_panel_at_a_time)
    print("\nprices:")
    check("the x10 label is the charge", t_starter_x10_label_is_the_charge)
    check("a short batch says why", t_partial_batch_says_why)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nhatch reveal: the pet itself, on any screen, and nothing left running")
    return 0


if __name__ == "__main__":
    sys.exit(main())
