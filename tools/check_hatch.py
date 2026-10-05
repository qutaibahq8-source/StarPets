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

    print("hatch reveal:")
    check("shows the pet, not a letter", t_shows_the_pet)
    check("ten cards fit a laptop", t_ten_fit_a_laptop)
    check("ten cards fit a phone", t_ten_fit_a_phone)
    check("a new species is called out", t_new_is_called_out)
    check("the spinner stops on close", t_spinner_stops)
    check("isNew is never saved", t_new_flag_is_not_saved)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nhatch reveal: the pet itself, on any screen, and nothing left running")
    return 0


if __name__ == "__main__":
    sys.exit(main())
