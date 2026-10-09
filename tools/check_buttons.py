#!/usr/bin/env python3
"""Press every button in every panel, and click everything clickable in the
world, against the real server. Nothing may error.

The other checks each test something specific. This one tests what a player
actually does: open a panel, press what is there, and walk up to things and
click them. A button whose handler throws looks exactly like a button that
does nothing, and nobody files a bug about a button that does nothing — they
just stop pressing it.

Everything runs end to end. Remotes carry messages both ways (check_client's
loopback), so a press goes client -> server -> data -> sync -> client, and an
error anywhere on that path fails here with the panel and button named.

Panels that poll the server (Fusion, Merchant, ...) only have buttons once a
poll has come back, so spawned threads run on a small scheduler: task.wait
yields, and the check lets time pass between presses.
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
SERIAL = [0]


def check(label, fn):
    try:
        print("   ok  %-30s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-30s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-30s crashed: %r" % (label, e))
        FAILURES.append(label)


SCHEDULER = r"""
__THREADS = {}
__THREAD_ERRORS = {}
local function run(co, ...)
    local ok, err = coroutine.resume(co, ...)
    if not ok then
        __THREAD_ERRORS[#__THREAD_ERRORS + 1] = debug.traceback(co, tostring(err))
    end
end
task.spawn = function(f, ...)
    local co = coroutine.create(f)
    __THREADS[#__THREADS + 1] = co
    run(co, ...)
    return co
end
task.defer = task.spawn
-- Long delays (auto-closing a popup after eight seconds) would close what is
-- being tested; short ones are part of what a press does.
task.delay = function(t, f, ...)
    if f and (t or 0) < 3 then return task.spawn(f, ...) end
end
task.wait = function()
    if coroutine.isyieldable() then return coroutine.yield() end
    return 0
end
wait = task.wait
function __TICK(n)
    for _ = 1, n or 1 do
        -- Messages in flight arrive first, each outside its sender's stack.
        if __DELIVER then
            local ok, err = pcall(__DELIVER)
            if not ok then __THREAD_ERRORS[#__THREAD_ERRORS + 1] = tostring(err) end
        end
        local live = {}
        for _, co in ipairs(__THREADS) do
            if coroutine.status(co) == "suspended" then
                run(co, 0.05)
                live[#live + 1] = co
            end
        end
        __THREADS = live
    end
end
"""


def main():
    lua, mock, gui, _ = check_client.boot(loopback=True)
    if lua is None:
        print("   x the client did not boot")
        return 1
    print()
    lua.execute(SCHEDULER)
    tick = lua.eval("__TICK")
    thread_errors = lua.eval("function() local e = __THREAD_ERRORS; __THREAD_ERRORS = {}; return e end")

    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    PS = mock["MODULES"][holder["FindFirstChild"](holder, "PetService")]
    me = mock["Players"].LocalPlayer
    data = DM.GetData(me)
    assert data is not None, "the join handler loaded no data"

    def stock_up():
        """Rich, with pets of every rarity and duplicates to fuse, so buy
        and fuse buttons take their real path rather than 'not enough'."""
        data.Coins = 10 ** 12
        data.Gems = 10 ** 9
        data.TotalCoinsEarned = 10 ** 12   # what Rebirth is gated on
        for name in ("cat", "cat", "cat", "dog", "fox", "owl", "dragon"):
            SERIAL[0] += 1
            PS.GrantPet(me, lua.eval('{name="%s", rarity="Common", uniqueId="btn-%d"}'
                                     % (name, SERIAL[0])))

    in_gui = lua.eval("""function(b, gui)
        local p = b
        while p do
            if p == gui then return true end
            p = p.Parent
        end
        return false
    end""")
    live_buttons = lua.eval("""function(screen)
        local out = {}
        for _, d in ipairs(screen:GetDescendants()) do
            if (d.ClassName == "TextButton" or d.ClassName == "ImageButton")
                and d.Active ~= false and d.Visible ~= false then
                out[#out + 1] = d
            end
        end
        return out
    end""")
    press = lua.eval("""function(b)
        b.MouseButton1Down:Fire()
        b.MouseButton1Up:Fire()
        if b.MouseButton1Click:Count() > 0 then b.MouseButton1Click:Fire()
        elseif b.Activated:Count() > 0 then b.Activated:Fire() end
    end""")
    path_of = lua.eval("""function(b, top)
        local parts, p = {}, b
        while p and p ~= top do table.insert(parts, 1, p.Name); p = p.Parent end
        return table.concat(parts, "/") .. " [" .. tostring(b.Text or "") .. "]"
    end""")

    CLOSERS = ("✕", "X", "x", "Close", "Cancel", "✕ Close")

    MS = mock["MODULES"][holder["FindFirstChild"](holder, "MerchantService")]
    ES = mock["MODULES"][holder["FindFirstChild"](holder, "EventService")]
    first_event = lua.eval("function(t) for k in pairs(t) do return k end end")(
        lua.eval("game.ReplicatedStorage.Shared.GameConfig") and
        mock["MODULES"][lua.eval("game.ReplicatedStorage.Shared.GameConfig")].Events)

    # The merchant visits on a timer and events run on a schedule; at a random
    # moment both are usually away, and their panels hold nothing but a close
    # button. Bring them in, so their buy buttons are what gets pressed.
    SETUP = {
        "MerchantPanel": lambda: MS.ForceSpawn(),
        "EventPanel": lambda: ES.Start(first_event),
    }

    def press_panel(name):
        def run():
            stock_up()
            if name in SETUP:
                SETUP[name]()
            ctrl.CloseAll()
            ctrl.TogglePanel(name, data)
            tick(3)
            errs = [str(e) for e in thread_errors().values()]
            assert not errs, "opening it threw: %s" % errs[0].splitlines()[0][:160]
            screen = gui["FindFirstChild"](gui, name)
            assert screen is not None, "it did not open"
            pressed, problems = set(), []
            for _ in range(60):
                cands = [b for b in live_buttons(screen).values() if in_gui(b, gui)]
                cands = [b for b in cands if str(path_of(b, screen)) not in pressed]
                if not cands:
                    break
                # Closers last: pressing one ends the panel.
                cands.sort(key=lambda b: str(b._p.Text or "").strip() in CLOSERS)
                b = cands[0]
                label = str(path_of(b, screen))
                pressed.add(label)
                try:
                    press(b)
                    tick(2)
                except Exception as e:  # noqa: BLE001
                    problems.append("%s: %s" % (label, str(e).splitlines()[0][:150]))
                for e in thread_errors().values():
                    problems.append("%s: %s" % (label, str(e).splitlines()[0][:150]))
                screen = gui["FindFirstChild"](gui, name) or screen
            assert not problems, "%d press(es) threw — %s" % (len(problems), problems[0])
            if "BTN_VERBOSE" in __import__("os").environ:
                print("\n".join("    %s | %s" % (name, x) for x in sorted(pressed)))
            return "%d buttons pressed, nothing threw" % len(pressed)
        return run

    def t_world_clicks():
        stock_up()
        ws = mock["workspace"]
        cds = [d for d in ws["GetDescendants"](ws).values()
               if str(d._p.ClassName) == "ClickDetector"]
        assert cds, "nothing in the world is clickable"
        problems = []
        fire = lua.eval("function(cd, p) cd.MouseClick:Fire(p) end")
        for cd in cds:
            where = str(cd._p.Parent.Name) if cd._p.Parent is not None else "?"
            ctrl.CloseAll()
            try:
                fire(cd, me)
                tick(2)
            except Exception as e:  # noqa: BLE001
                problems.append("%s: %s" % (where, str(e).splitlines()[0][:150]))
            for e in thread_errors().values():
                problems.append("%s: %s" % (where, str(e).splitlines()[0][:150]))
        assert not problems, "%d click(s) threw — %s" % (len(problems), problems[0])
        return "%d clickables clicked, nothing threw" % len(cds)

    print("every button in every panel, against the real server:")
    for name in PANELS:
        check(name, press_panel(name))
    print("\nthe world:")
    check("every clickable", t_world_clicks)
    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nbuttons: every one pressed, end to end, and nothing broke")
    return 0


if __name__ == "__main__":
    sys.exit(main())
