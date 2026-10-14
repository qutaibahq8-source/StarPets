#!/usr/bin/env python3
"""Every panel ends up ON the screen, and stays put while it is open.

check_ui proves each panel is SIZED to fit a phone. That is not the same as
being where the player can see it, and the difference was hiding a bug in the
six most-used panels:

  ENDED OFF SCREEN   Responsive centres a panel by setting AnchorPoint 0.5
                     and Position (0.5, 0.5). But each panel's Build had
                     already started a slide-in tween toward its old pixel
                     position, and a playing tween writes its property every
                     frame until it finishes. It finished at the old offset,
                     now measured from the panel's centre: on a phone, Pets,
                     Shop, Upgrade, Rebirth, Hatch and Ranks ended with their
                     centre left of the screen's edge.

  BOUNCED ON REFRESH Rebirth, Shop and Upgrade rebuilt themselves on every
                     data sync — every two seconds — skipping the fitting
                     pass and replaying the slide-in each time. Scroll jumped
                     back to the top, and a click landing mid-rebuild was lost.

The mock's tweens used to do nothing, which is why no check saw any of this.
They now land on their goal when a check lets time pass (FLUSH_TWEENS), which
is what Roblox does.
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
from check_ui import PANELS  # noqa: E402

FAILURES = []
SCREENS = [(390, 844, "phone"), (1280, 720, "laptop")]


def check(label, fn):
    try:
        print("   ok  %-38s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-38s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-38s crashed: %r" % (label, e))
        FAILURES.append(label)


def num(v, k):
    try:
        return float(v[k] or 0)
    except Exception:  # noqa: BLE001
        return 0.0


def rect(frame, W, H):
    """Where a frame actually is on a W x H screen: (left, top, w, h)."""
    p = frame._p
    sz, pos = p.Size, p.Position
    w = num(sz["X"], "Scale") * W + num(sz["X"], "Offset")
    h = num(sz["Y"], "Scale") * H + num(sz["Y"], "Offset")
    clamp = frame["FindFirstChildOfClass"](frame, "UISizeConstraint")
    if clamp is not None:
        mx, mn = clamp._p.MaxSize, clamp._p.MinSize
        if mx is not None:
            w, h = min(w, float(mx["X"])), min(h, float(mx["Y"]))
        if mn is not None:
            w, h = max(w, float(mn["X"])), max(h, float(mn["Y"]))
    x = num(pos["X"], "Scale") * W + num(pos["X"], "Offset") if pos is not None else 0.0
    y = num(pos["Y"], "Scale") * H + num(pos["Y"], "Offset") if pos is not None else 0.0
    ap = p.AnchorPoint
    ax, ay = (float(ap["X"]), float(ap["Y"])) if ap is not None else (0.0, 0.0)
    return x - ax * w, y - ay * h, w, h


def root_of(screen, W, H):
    """The panel itself: the biggest Frame that is not a full-screen backdrop."""
    best, area = None, -1
    for c in screen["GetChildren"](screen).values():
        if str(c._p.ClassName) != "Frame" or c._p.Size is None:
            continue
        sz = c._p.Size
        if num(sz["X"], "Scale") >= 1 and num(sz["Y"], "Scale") >= 1:
            continue
        _, _, w, h = rect(c, W, H)
        if w * h > area:
            best, area = c, w * h
    return best


def off_screen(frame, W, H):
    x, y, w, h = rect(frame, W, H)
    out = []
    if x < -1:
        out.append("%d px off the left" % -x)
    if y < -1:
        out.append("%d px off the top" % -y)
    if x + w > W + 1:
        out.append("%d px off the right" % (x + w - W))
    if y + h > H + 1:
        out.append("%d px off the bottom" % (y + h - H))
    return out


def main():
    lua, mock, gui, _ = check_client.boot()
    print()
    lua.execute("task.spawn = function() end; task.defer = function() end")
    flush = mock["FLUSH_TWEENS"]

    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    res = DM.LoadPlayer(mock["Players"].LocalPlayer)
    data = res[0] if isinstance(res, tuple) else res

    def screen_size(W, H):
        lua.execute("""
            local cam = workspace.CurrentCamera or Instance.new("Camera")
            cam.ViewportSize = Vector2.new(%d, %d)
            workspace.CurrentCamera = cam
        """ % (W, H))

    def open_panel(name):
        ctrl.CloseAll()
        flush()
        ctrl.TogglePanel(name, data)
        flush()  # let every tween that was started run to its end
        return gui["FindFirstChild"](gui, name)

    # ---------------------------------------------------- where they land
    def t_all_on_screen(W, H):
        def run():
            screen_size(W, H)
            bad = []
            for name in PANELS:
                s = open_panel(name)
                if s is None:
                    bad.append("%s did not open" % name)
                    continue
                root = root_of(s, W, H)
                if root is None:
                    continue
                out = off_screen(root, W, H)
                if out:
                    bad.append("%s %s" % (name, ", ".join(out)))
            assert not bad, "once their animations finish: " + "; ".join(bad)
            return "all %d panels fully on a %dx%d screen" % (len(PANELS), W, H)
        return run

    # ---------------------------------------------------- refresh
    def t_refresh_unchanged_keeps_panel():
        screen_size(390, 844)
        s = open_panel("ShopPanel")
        ctrl.RefreshCurrent(data)
        flush()
        s2 = gui["FindFirstChild"](gui, "ShopPanel")
        assert s2 is not None, "the Shop panel vanished on refresh"
        same = lua.eval("function(a, b) return rawequal(a, b) end")(s, s2)
        assert same, ("a data sync with nothing on the panel changed rebuilt it "
                      "anyway — every two seconds, losing scroll and clicks")
        return "a sync that changes nothing on it leaves it alone"

    def t_refresh_changed_stays_fitted():
        screen_size(390, 844)
        bad = []
        for name in ("ShopPanel", "UpgradePanel", "RebirthPanel"):
            open_panel(name)
            before = data.Coins
            data.Coins = 987654321
            ctrl.RefreshCurrent(data)
            flush()
            data.Coins = before
            s = gui["FindFirstChild"](gui, name)
            if s is None:
                bad.append("%s vanished" % name)
                continue
            root = root_of(s, 390, 844)
            if root["FindFirstChildOfClass"](root, "UISizeConstraint") is None:
                bad.append("%s rebuilt without the phone fit" % name)
            out = off_screen(root, 390, 844)
            if out:
                bad.append("%s after refresh: %s" % (name, ", ".join(out)))
        assert not bad, "; ".join(bad)
        return "Shop, Upgrade, Rebirth: rebuilt, fitted, on screen"

    def t_refresh_keeps_scroll():
        screen_size(390, 844)
        # An upgrade level goes up between open and sync, so the panel really
        # is rebuilt. With nothing visible changed the old one is kept, and
        # this would pass without testing anything.
        data.Upgrades["CoinBonus"] = 0
        s = open_panel("UpgradePanel")
        scrolls = [d for d in s["GetDescendants"](s).values()
                   if str(d._p.ClassName) == "ScrollingFrame"]
        assert scrolls, "no scrolling list in the Upgrade panel"
        scrolls[0].CanvasPosition = lua.eval("Vector2.new(0, 180)")
        data.Upgrades["CoinBonus"] = 1
        ctrl.RefreshCurrent(data)
        flush()
        data.Upgrades["CoinBonus"] = 0
        s2 = gui["FindFirstChild"](gui, "UpgradePanel")
        rebuilt = not lua.eval("function(a, b) return rawequal(a, b) end")(s, s2)
        assert rebuilt, "an upgrade level went up and the panel was not rebuilt"
        sc2 = [d for d in s2["GetDescendants"](s2).values()
               if str(d._p.ClassName) == "ScrollingFrame"][0]
        y = float(sc2._p.CanvasPosition["Y"]) if sc2._p.CanvasPosition is not None else 0
        assert y == 180, "a refresh scrolled the list back to %d (was 180)" % y
        return "scrolled to 180, still at 180 after a rebuild"

    def t_equip_keeps_pets_panel():
        screen_size(390, 844)
        open_panel("PetsPanel")
        d = lua.eval("""{ Pets = { {name="cat", rarity="Common", uniqueId="q1"} },
                          EquippedPets = { "q1" }, Discovered = {} }""")
        ctrl.RefreshCurrent(d)
        flush()
        s = gui["FindFirstChild"](gui, "PetsPanel")
        assert s is not None, "the Pets panel closed on equip"
        root = root_of(s, 390, 844)
        assert root["FindFirstChildOfClass"](root, "UISizeConstraint") is not None, \
            "after equipping, the Pets panel was rebuilt without the phone fit"
        out = off_screen(root, 390, 844)
        assert not out, "after equipping, the Pets panel is %s" % ", ".join(out)
        return "equip: rebuilt, fitted, on screen"

    # ---------------------------------------------------- trade
    def t_trade_opens_like_a_panel():
        screen_size(390, 844)
        open_panel("PetsPanel")
        remotes = lua.eval("game.ReplicatedStorage.Remotes")
        ts = remotes["FindFirstChild"](remotes, "TradeState")
        lua.eval("function(r) r.OnClientEvent:Fire({active=true, partner='Bob', "
                 "yourOffer={}, theirOffer={}}) end")(ts)
        flush()
        s = gui["FindFirstChild"](gui, "TradePanel")
        assert s is not None, "an active trade opened no window"
        assert gui["FindFirstChild"](gui, "PetsPanel") is None, \
            "the trade window opened on top of the Pets panel"
        root = root_of(s, 390, 844)
        out = off_screen(root, 390, 844)
        assert not out, "the trade window is %s" % ", ".join(out)
        return "closes the open panel, fits the phone"

    def t_buying_keeps_upgrade_open():
        screen_size(1280, 720)
        data.Coins = 10 ** 9
        s = open_panel("UpgradePanel")
        btns = [b for b in s["GetDescendants"](s).values()
                if str(b._p.ClassName) == "TextButton" and b._p.Active is not False
                and str(b._p.Text or "") not in ("✕", "X")]
        assert btns, "no buy button in the Upgrade panel"
        # Run every short delay now: what happens half a second after a press.
        lua.execute("task.delay = function(t, f, ...) if f and (t or 0) < 3 then f(...) end end")
        try:
            lua.eval("function(b) b.MouseButton1Click:Fire() end")(btns[0])
        finally:
            lua.execute("task.delay = function() end")
        assert gui["FindFirstChild"](gui, "UpgradePanel") is not None, \
            "buying an upgrade closed the Upgrade panel half a second later"
        return "bought one; the panel is still open for the next"

    # ---------------------------------------------------- popups
    remotes = lua.eval("game.ReplicatedStorage.Remotes")

    def fire(name, *args):
        r = remotes["FindFirstChild"](remotes, name)
        lua.eval("function(r, ...) r.OnClientEvent:Fire(...) end")(r, *args)

    def child_rect(child, parent_rect):
        px, py, pw, ph = parent_rect
        x, y, w, h = rect(child, pw, ph)
        return px + x, py + y, w, h

    def popup_check(gui_name, trigger):
        def run():
            screen_size(390, 844)
            old = gui["FindFirstChild"](gui, gui_name)
            if old is not None:
                old["Destroy"](old)
            trigger()
            flush()
            s = gui["FindFirstChild"](gui, gui_name)
            assert s is not None, "%s never appeared" % gui_name
            root = root_of(s, 390, 844)
            out = off_screen(root, 390, 844)
            assert not out, "on a 390-wide phone the popup is %s" % ", ".join(out)
            pr = rect(root, 390, 844)
            btns = [child_rect(b, pr) for b in root["GetChildren"](root).values()
                    if str(b._p.ClassName) == "TextButton"]
            for i in range(len(btns)):
                for j in range(i + 1, len(btns)):
                    a, b = btns[i], btns[j]
                    ox = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
                    oy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
                    assert ox <= 0 or oy <= 0, \
                        "two of its buttons overlap by %d px on a phone" % ox
            spill = [b for b in btns if b[0] < pr[0] - 1 or b[0] + b[2] > pr[0] + pr[2] + 1]
            assert not spill, "a button sticks out of the popup"
            return "%dx%d on a phone, %d button(s), none overlapping" % (
                pr[2], pr[3], len(btns))
        return run

    def t_welcome_banner():
        # Built by the client in its first seconds, which only exist with
        # short delays running — so a second, separate boot.
        lua2, mock2, gui2, _ = check_client.boot(short_delays=True)
        mock2["FLUSH_TWEENS"]()
        s = gui2["FindFirstChild"](gui2, "WelcomeGui")
        assert s is not None, "no welcome banner after joining"
        lua2.execute("""
            local cam = workspace.CurrentCamera or Instance.new("Camera")
            cam.ViewportSize = Vector2.new(390, 844)
            workspace.CurrentCamera = cam
        """)
        card = root_of(s, 390, 844)
        out = off_screen(card, 390, 844)
        assert not out, "the welcome banner is %s on a phone" % ", ".join(out)
        x, y, w, h = rect(card, 390, 844)
        return "%dx%d at (%d, %d) on a 390x844 phone" % (w, h, x, y)

    # ---------------------------------------------------- polling panels
    # Fusion asks the server for its list every 1.5 s. Here the loop really
    # runs: InvokeServer goes to the real server handler, and task.wait is
    # where the test acts between polls (and stops the loop after a few).
    lua.execute("""
        local rf = game.ReplicatedStorage.Remotes:FindFirstChild("GetFusion")
        rf.InvokeServer = function(_, ...)
            return rf.OnServerInvoke(game:GetService("Players").LocalPlayer, ...)
        end
    """)

    def poll_fusion(between, polls=3):
        """Open Fusion and let it poll `polls` times; `between(n, btn)` runs
        after poll n. Returns the Fuse button seen after each poll."""
        seen = []
        hook = lua.eval("""function(between, seen, maxn)
            local n = 0
            local function btn()
                local s = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("FusionPanel")
                if not s then return nil end
                for _, d in ipairs(s:GetDescendants()) do
                    if d.ClassName == "TextButton" and tostring(d.Text):find("Fuse") then return d end
                end
            end
            -- Held until Build has returned: in Roblox the loop's first
            -- InvokeServer yields, so the panel is opened (and its buttons
            -- livened) before the first poll comes back.
            __SPAWNED = {}
            task.spawn = function(f, ...) table.insert(__SPAWNED, f) end
            task.defer = function(f, ...) if f then f(...) end end
            task.wait = function()
                n = n + 1
                local b = btn()
                table.insert(seen, b or false)
                between(n, b)
                if n >= maxn then error("stop polling") end
                return 0
            end
        end""")
        tbl = lua.eval("{}")
        hook(between, tbl, polls)
        try:
            ctrl.CloseAll()
            ctrl.TogglePanel("FusionPanel", data)
            lua.execute("for _, f in ipairs(__SPAWNED) do pcall(f) end")
        finally:
            lua.execute("task.spawn = function() end; task.defer = function() end; "
                        "task.wait = function() return 0 end")
        return [tbl[i + 1] for i in range(len(tbl))]

    same = lua.eval("function(a, b) return rawequal(a, b) end")
    add_pets = lua.eval("""function(d, name, n)
        for i = 1, n do
            table.insert(d.Pets, { name = name, rarity = "Common",
                uniqueId = name .. "-poll-" .. tostring(#d.Pets + 1) })
        end
    end""")

    def reset_pets():
        for k in list(data.Pets.keys()):
            data.Pets[k] = None
        for k in list(data.EquippedPets.keys()):
            data.EquippedPets[k] = None

    def t_poll_unchanged_keeps_buttons():
        reset_pets()
        add_pets(data, "cat", 3)
        seen = poll_fusion(lambda n, b: None)
        assert seen[0], "the Fusion panel never listed three cats as fusable"
        redrawn = [i for i in range(1, len(seen)) if not same(seen[0], seen[i])]
        assert not redrawn, ("nothing changed on the server and the Fuse button "
                             "was destroyed and remade %d time(s)" % len(redrawn))
        return "3 polls, same answer, same button"

    def t_poll_changed_redraws():
        reset_pets()
        add_pets(data, "cat", 3)
        seen = poll_fusion(lambda n, b: add_pets(data, "dog", 3) if n == 1 else None)
        assert not same(seen[0], seen[1]), \
            "three new dogs arrived and the Fusion list did not redraw"
        return "new fusable dogs: redrawn"

    def t_poll_waits_for_press():
        reset_pets()
        add_pets(data, "cat", 3)

        def between(n, b):
            if n == 1:
                lua.eval("function(b) b.MouseButton1Down:Fire() end")(b)
                add_pets(data, "dog", 3)   # the answer changes mid-press
            if n == 2:
                lua.eval("function(b) b.MouseButton1Up:Fire() end")(b)
        seen = poll_fusion(between, polls=3)
        assert same(seen[0], seen[1]), ("the list redrew while a button was held "
                                         "down — that press is lost")
        assert not same(seen[1], seen[2]), "the list never caught up after release"
        return "held: kept; released: redrawn"

    print("where every panel ends up:")
    for W, H, label in SCREENS:
        check("on screen on a %s" % label, t_all_on_screen(W, H))
    print("\nwhile one is open:")
    check("a sync that changes nothing", t_refresh_unchanged_keeps_panel)
    check("a sync that changes something", t_refresh_changed_stays_fitted)
    check("scroll survives a rebuild", t_refresh_keeps_scroll)
    check("equipping in the Pets panel", t_equip_keeps_pets_panel)
    check("a trade window", t_trade_opens_like_a_panel)
    check("buying an upgrade", t_buying_keeps_upgrade_open)
    print("\na panel that polls the server:")
    check("same answer, same buttons", t_poll_unchanged_keeps_buttons)
    check("new answer, redrawn", t_poll_changed_redraws)
    check("never redrawn mid-press", t_poll_waits_for_press)
    print("\npopups, on a phone:")
    lua.globals()["__D"] = data
    check("rebirth confirm", popup_check("RebirthConfirmGui", lambda: (
        fire("DataUpdated", data), fire("Rebirth"))))
    check("secret found", popup_check("SecretFoundGui", lambda: fire("SecretFound", lua.eval("{coins = 5000, gems = 25}"))))
    check("welcome back", popup_check("WelcomeBackGui", lambda: fire("OfflineEarnings", 12345, 7200)))
    check("welcome banner", t_welcome_banner)

    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\npanels: on screen, and they stay put")
    return 0


if __name__ == "__main__":
    sys.exit(main())
