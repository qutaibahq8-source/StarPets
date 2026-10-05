#!/usr/bin/env python3
"""Open every panel and measure it against a phone.

Most Roblox play happens on a phone. Every panel in this game was sized in hard
pixels — 620x500, 600x500, 580x480 — and centred by hand. On a 390-point-wide
portrait screen a 620-wide panel hangs 115 points off each edge, taking the
close button and half the buttons with it. Nothing errors, nothing warns, and
on a desktop it all looks perfect.

So this opens all eighteen panels the way the game does, through
UIController.TogglePanel, and checks two things about each:

  1. IT BUILDS AT ALL        a panel that throws is a HUD button that does
                             nothing when pressed
  2. IT FITS A PHONE         sized in scale with a clamp, not in raw pixels,
                             so it can shrink to a screen narrower than it

and one thing about the buttons inside: that pressing them does something
visible. Two hover handlers across twenty-one UI files is most of the
difference between feeling cheap and feeling made.
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

# Portrait on a common phone, in the points Roblox lays UI out in.
PHONE_W, PHONE_H = 390, 844

PANELS = [
    "PetsPanel", "HatchPanel", "ShopPanel", "RebirthPanel", "UpgradePanel",
    "LeaderboardPanel", "QuestPanel", "MerchantPanel", "EventPanel",
    "TradePanel", "PetIndexPanel", "CodesPanel", "DailyPanel", "BoostsPanel",
    "FusionPanel", "PlaytimePanel", "SpinWheelPanel",
]


def main():
    lua, mock, gui, _ = check_client.boot()
    print()

    ui_folder = lua.eval(
        'game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    controller_inst = ui_folder["FindFirstChild"](ui_folder, "UIController")
    controller = mock["MODULES"][controller_inst]
    if controller is None:
        print("   x UIController never loaded, so no panel can open")
        return 1

    # In Roblox `script` is a local unique to each script. Here it is one
    # global that every load overwrote, so by now it points at GameClient —
    # and UIController's require(script.Parent[panelName]) would look for the
    # panels beside GameClient, find nothing, and quietly warn. Point it back
    # at UIController, which is what Roblox would have given it.
    lua.globals()["script"] = controller_inst

    # Panels start animation threads — spinning wheels, pulsing buttons — that
    # are written as `while true do ... task.wait() end`. The client harness
    # runs task.spawn INLINE so nothing spawned is silently skipped, which is
    # right for boot but means the first such loop here never returns. Panels
    # are being measured, not animated, so the threads are dropped for this
    # part.
    lua.execute("task.spawn = function() end; task.defer = function() end")

    # Real player data, from the real DataManager. Several panels index it
    # immediately, and handing them nil would test a path the game never takes.
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    dm = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    res = dm.LoadPlayer(mock["Players"].LocalPlayer)
    data = res[0] if isinstance(res, tuple) else res
    if data is None:
        print("   x could not load player data to open the panels with")
        return 1

    fails, opened, buttons, livened, dead = [], 0, 0, 0, []
    print("opening %d panels the way the HUD does:" % len(PANELS))

    for name in PANELS:
        ok, err = True, None
        try:
            controller.TogglePanel(name, data)
        except Exception as e:  # noqa: BLE001
            ok, err = False, repr(e)

        panel = gui["FindFirstChild"](gui, name)
        if not ok or panel is None:
            fails.append("%s did not open (%s) — its HUD button does nothing"
                         % (name, err or "no ScreenGui"))
            continue
        opened += 1

        # The root frame: the biggest direct child Frame.
        root, area = None, -1
        for c in panel["GetChildren"](panel).values():
            if str(c._p.ClassName) != "Frame":
                continue
            sz = c._p.Size
            if sz is None:
                continue
            a = (sz["X"]["Offset"] or 0) * (sz["Y"]["Offset"] or 0)
            if a > area:
                root, area = c, a
        if root is None:
            fails.append("%s has no Frame in it at all" % name)
            continue

        sz = root._p.Size
        clamp = root["FindFirstChildOfClass"](root, "UISizeConstraint")
        w_off, h_off = sz["X"]["Offset"] or 0, sz["Y"]["Offset"] or 0
        w_sc, h_sc = sz["X"]["Scale"] or 0, sz["Y"]["Scale"] or 0

        if clamp is None:
            # Still sized in raw pixels: works out how badly it overflows.
            if w_off > PHONE_W or h_off > PHONE_H:
                fails.append("%s is %dx%d hard pixels — %d wider than a %d-point "
                             "phone, so its edges are off screen"
                             % (name, w_off, h_off, w_off - PHONE_W, PHONE_W))
            else:
                fails.append("%s is sized in hard pixels with no clamp" % name)
            continue

        if w_sc <= 0 or h_sc <= 0:
            fails.append("%s has a clamp but no scale, so it cannot shrink" % name)
            continue

        # What it would actually measure on the phone.
        got_w = min(w_sc * PHONE_W, clamp._p.MaxSize["X"])
        got_h = min(h_sc * PHONE_H, clamp._p.MaxSize["Y"])
        if got_w > PHONE_W or got_h > PHONE_H:
            fails.append("%s still measures %dx%d on a %dx%d phone"
                         % (name, got_w, got_h, PHONE_W, PHONE_H))
            continue

        # And that the desktop look is unchanged: the clamp is the design size.
        anchor = root._p.AnchorPoint
        if anchor is None or abs((anchor["X"] or 0) - 0.5) > 0.01:
            fails.append("%s is not anchored at its centre, so the clamp will "
                         "shrink it off centre" % name)

        # Buttons are counted across EVERY panel, not sampled from one. A
        # single panel that happens to render one button would report full
        # coverage of the whole game's UI.
        for d in panel["GetDescendants"](panel).values():
            if str(d._p.ClassName) in ("TextButton", "ImageButton"):
                buttons += 1
                if d["FindFirstChild"](d, "SPScale") is not None:
                    livened += 1
                else:
                    dead.append("%s/%s" % (name, str(d._p.Name)))

    print("   %d of %d panels opened" % (opened, len(PANELS)))

    # ---- buttons react ----------------------------------------------------
    if buttons < len(PANELS):
        fails.append("only %d buttons across %d panels — too few to mean "
                     "anything" % (buttons, len(PANELS)))
    elif dead:
        fails.append("%d of %d buttons have no press feedback (%s%s)"
                     % (len(dead), buttons, ", ".join(dead[:4]),
                        "..." if len(dead) > 4 else ""))
    else:
        print("   ok  all %d buttons across those panels spring on press"
              % buttons)

    panel = gui["FindFirstChild"](gui, "QuestPanel")
    if panel is None:
        controller.TogglePanel("QuestPanel", data)
        panel = gui["FindFirstChild"](gui, "QuestPanel")

    # A button created AFTER the panel was built — panels rebuild their lists
    # on every refresh, so a one-shot pass would cover almost nothing.
    if panel is not None:
        lua.execute("""
            local gui = game:GetService("Players").LocalPlayer.PlayerGui
            local p = gui:FindFirstChild("QuestPanel")
            LATE = Instance.new("TextButton")
            LATE.Name = "LateButton"
            LATE.Parent = p
        """)
        late = lua.globals().LATE
        if late["FindFirstChild"](late, "SPScale") is None:
            fails.append("a button added after the panel was built has no "
                         "feedback — panels rebuild their lists constantly")
        else:
            print("   ok  and so do buttons created later")

    # ---- THE HUD -----------------------------------------------------------
    # Panels open and close; the HUD is on screen the whole game. It was never
    # measured, and on a 390-point phone the coin counter started 103 points
    # off the left edge, the rebirth badge was drawn over the other two
    # counters, and the dock was 442 points wide.
    hud = gui["FindFirstChild"](gui, "MysticPetsHUD")
    layout = lua.globals()._G.MysticPets and lua.globals()._G.MysticPets.layoutHUD

    def rect(inst, W, H):
        pos, sz = inst._p.Position, inst._p.Size
        x = float(pos["X"]["Scale"] or 0) * W + float(pos["X"]["Offset"] or 0)
        y = float(pos["Y"]["Scale"] or 0) * H + float(pos["Y"]["Offset"] or 0)
        w = float(sz["X"]["Scale"] or 0) * W + float(sz["X"]["Offset"] or 0)
        h = float(sz["Y"]["Scale"] or 0) * H + float(sz["Y"]["Offset"] or 0)
        return x, y, w, h

    def overlaps(a, b):
        return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and \
            a[1] < b[1] + b[3] and b[1] < a[1] + a[3]

    def at_width(W, H):
        lua.execute("""
            local cam = workspace.CurrentCamera or Instance.new("Camera")
            cam.ViewportSize = Vector2.new(%d, %d)
            workspace.CurrentCamera = cam
        """ % (W, H))
        layout()
        top = [c for c in hud["GetDescendants"](hud).values()
               if str(c._p.ClassName) == "Frame" and c._p.Parent is not None
               and str(c._p.Parent._p.ClassName) == "Frame"
               and c["FindFirstChildOfClass"](c, "UIStroke") is not None
               and c._p.Size is not None and float(c._p.Size["Y"]["Offset"] or 0) >= 38]
        badge = [c for c in hud["GetDescendants"](hud).values()
                 if str(c._p.ClassName) == "TextLabel" and "Rebirth" in str(c._p.Text or "")]
        dock = [c for c in hud["GetChildren"](hud).values()
                if str(c._p.Name).startswith("Dock_") and c._p.Visible is not False]
        return top, badge, dock

    if hud is None or layout is None:
        fails.append("the HUD or its layout function is missing")
    else:
        PHONE = (390, 844)
        chips, badge, dock = at_width(*PHONE)
        off = []
        for c in chips + dock:
            x, y, w, h = rect(c, *PHONE)
            if x < 0 or x + w > PHONE[0]:
                off.append("%s at x %d..%d" % (str(c._p.Name), x, x + w))
        if off:
            fails.append("on a %d-point phone the HUD runs off screen: %s"
                         % (PHONE[0], ", ".join(off[:5])))
        else:
            print("   ok  every counter and dock button is on a %d-point screen"
                  % PHONE[0])

        clash = [str(c._p.Name) for c in chips for b in badge
                 if overlaps(rect(c, *PHONE), rect(b, *PHONE))]
        if clash:
            fails.append("the rebirth badge is drawn over the counters on a phone")
        else:
            print("   ok  the rebirth badge sits clear of the counters")

        small = [str(c._p.Name) for c in dock if rect(c, *PHONE)[2] < 44]
        if small:
            fails.append("dock buttons under the 44-point touch target: %s" % small)
        elif not any(str(c._p.Name) == "Dock_More" for c in dock):
            fails.append("a phone shows a cut-down dock with no way to reach the rest")
        else:
            print("   ok  %d dock buttons at 44pt or more, with More for the rest"
                  % len(dock))

        # Opening More must still fit.
        mores = [c for c in dock if str(c._p.Name) == "Dock_More"]
        more = mores[0] if mores else None
        if more is not None:
            lua.eval("function(b) b.MouseButton1Click:Fire() end")(more)
            _, _, opened = at_width(*PHONE)
            spill = [str(c._p.Name) for c in opened
                     if rect(c, *PHONE)[0] < 0 or sum(rect(c, *PHONE)[0:3:2]) > PHONE[0]]
            if len(opened) <= len(dock):
                fails.append("pressing More did not open the rest of the dock")
            elif spill:
                fails.append("the opened dock runs off screen: %s" % spill[:4])
            else:
                print("   ok  More opens all %d buttons, still on screen" % len(opened))
            lua.eval("function(b) b.MouseButton1Click:Fire() end")(more)

        # And a desktop keeps the look it had.
        chips_d, _, dock_d = at_width(1280, 720)
        xs = sorted(int(rect(c, 1280, 720)[0]) for c in chips_d)
        if xs != [1280 - 493, 1280 - 328, 1280 - 163]:
            fails.append("the desktop counters moved (%s)" % xs)
        elif len(dock_d) != 15:
            fails.append("the desktop dock shows %d buttons, not all 15" % len(dock_d))
        else:
            print("   ok  a desktop keeps exactly the layout it had")

    if fails:
        print("\n%d problem(s):" % len(fails))
        for f in fails:
            print("   x %s" % f)
        return 1
    print("\nui: every panel opens and fits a phone, and the buttons react")
    return 0


if __name__ == "__main__":
    sys.exit(main())
