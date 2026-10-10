#!/usr/bin/env python3
"""A real trade, through the trade window, against the real server.

check_trade proves the swap is safe at the server. This proves the trade can
be DONE, and done knowingly, the way two players do it:

   1. type a name, press Send Trade Request
   2. the other player accepts                -> the window shows the trade
   3. they offer a Rainbow pet, fused x3.5    -> you can SEE that it is one
   4. you tap one of your pets to offer it
   5. both accept                             -> the countdown starts
   6. they change their mind and re-accept    -> only the NEW countdown counts
   7. it completes                            -> pets swapped, value intact

Step 3 used to fail silently: offers showed the pet's name and nothing else,
so a Rainbow pet three fusions deep looked like a fresh one. Step 6 used to
fail too: every accept scheduled its own swap and none was called off, so a
re-accept could complete on the first, stale timer — the anti-scam window cut
to a fraction of a second.

The other player is a second, real player on the server; their side is
driven through the same remote their client would fire.
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

# Delays are held, not run, and tagged with the script that asked for them,
# so the check decides exactly when "three seconds" have passed and for which
# timer.
DELAYS = r"""
__DELAYS = {}
task.delay = function(t, f, ...)
    local a = table.pack(...)
    local info = debug.getinfo(2, "S")
    table.insert(__DELAYS, { src = info and info.source or "?", t = t,
        fn = function() f(table.unpack(a, 1, a.n)) end })
end
function __TRADE_TIMERS()
    local out = {}
    for i, d in ipairs(__DELAYS) do
        if tostring(d.src):find("TradeService") then out[#out + 1] = i end
    end
    return out
end
function __RUN_DELAY(i)
    local d = __DELAYS[i]
    if d and not d.done then d.done = true; d.fn() end
end
"""


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
    lua.execute(DELAYS)
    tick = lua.eval("__TICK")
    errs = lua.eval("function() local e = __THREAD_ERRORS; __THREAD_ERRORS = {}; return e end")

    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    PS = mock["MODULES"][holder["FindFirstChild"](holder, "PetService")]
    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
    me = mock["Players"].LocalPlayer
    mine = DM.GetData(me)

    # A second player, joined through the server's real join handler.
    bob = mock["newInst"]("Player"); bob.Name = "Bob"; bob.UserId = 8001
    char = mock["newInst"]("Model"); char.Name = "Bob"
    root = mock["newInst"]("Part"); root.Name = "HumanoidRootPart"; root.Parent = char
    root.CFrame = lua.eval("CFrame.new(10, 5, 0)")
    bob.Character = char
    mock["PlayerList"][2] = bob
    mock["Players"].PlayerAdded.Fire(None, bob)
    tick(2)
    theirs = DM.GetData(bob)
    assert theirs is not None, "Bob's join loaded no data"

    PS.GrantPet(bob, lua.eval('{name="dragon", rarity="Epic", uniqueId="bob-dragon", '
                              'mutation="Rainbow", fuseMult=3.5}'))
    PS.GrantPet(me, lua.eval('{name="cat", rarity="Common", uniqueId="me-cat"}'))

    trade = lua.eval("game.ReplicatedStorage.Remotes.Trade")
    as_bob = lua.eval("function(r, p, ...) r.OnServerEvent:Fire(p, ...) end")

    def bob_does(*args):
        as_bob(trade, bob, *args)
        tick(2)

    def panel():
        s = gui["FindFirstChild"](gui, "TradePanel")
        assert s is not None, "the trade window is not open"
        return s

    def texts(kind):
        return [d for d in panel()["GetDescendants"](panel()).values()
                if str(d._p.ClassName) == kind]

    def press(b):
        lua.eval("""function(b)
            b.MouseButton1Down:Fire(); b.MouseButton1Up:Fire(); b.MouseButton1Click:Fire()
        end""")(b)
        tick(2)

    def no_errors():
        e = [str(x) for x in errs().values()]
        assert not e, "something threw: %s" % e[0].splitlines()[0][:160]

    def has(data, uid_prefix, name):
        return [p for p in data.Pets.values() if str(p.name) == name]

    # ------------------------------------------------------------------
    def t_request():
        ctrl.CloseAll()
        ctrl.TogglePanel("TradePanel", mine)
        tick(1)
        box = texts("TextBox")
        assert box, "no name box in the trade window"
        box[0].Text = "Bo"
        req = [b for b in texts("TextButton") if "Request" in str(b._p.Text)]
        assert req, "no Send Trade Request button"
        press(req[0])
        no_errors()
        return "asked Bob, by the first two letters of his name"

    def t_partner_accepts():
        bob_does("respond", True)
        no_errors()
        heads = [str(t._p.Text) for t in texts("TextLabel")]
        assert any("Trading with Bob" in h for h in heads), \
            "Bob accepted and the window still shows the request form"
        return "the window is now the trade with Bob"

    def t_see_what_is_offered():
        bob_does("add", "bob-dragon")
        no_errors()
        rows = [str(b._p.Text) for b in texts("TextButton")]
        theirs_rows = [r for r in rows if "dragon" in r]
        assert theirs_rows, "Bob offered a dragon and it does not appear"
        row = theirs_rows[0]
        assert "Rainbow" in row and "x3.5" in row, \
            "Bob offered a Rainbow dragon fused x3.5 and the window shows %r" % row
        return "%r" % row

    def t_offer_mine():
        add = [b for b in texts("TextButton") if "cat" in str(b._p.Text)]
        assert add, "my cat is not in the tap-to-add list"
        press(add[0])
        no_errors()
        return "offered my cat"

    def t_both_accept():
        acc = [b for b in texts("TextButton") if "Accept Trade" in str(b._p.Text)]
        assert acc, "no Accept button"
        press(acc[0])
        bob_does("accept", True)
        no_errors()
        rows = [str(b._p.Text) for b in texts("TextButton")]
        assert any("Confirming" in r for r in rows), "both accepted and no countdown shows"
        return "countdown showing"

    def t_stale_timer():
        # Bob un-accepts and re-accepts: a new countdown. The first one must
        # now be dead — running it may not complete the trade.
        bob_does("accept", False)
        bob_does("accept", True)
        timers = list(lua.eval("__TRADE_TIMERS()").values())
        assert len(timers) >= 2, "expected two countdowns scheduled, saw %d" % len(timers)
        lua.eval("__RUN_DELAY")(timers[0])
        tick(2)
        assert not has(mine, "", "dragon"), ("the trade completed on the FIRST "
                                            "countdown, after Bob had re-accepted")
        return "the stale countdown did nothing"

    def t_completes():
        timers = list(lua.eval("__TRADE_TIMERS()").values())
        lua.eval("__RUN_DELAY")(timers[-1])
        tick(3)
        no_errors()
        got = has(mine, "", "dragon")
        assert got, "the current countdown ran out and nothing was swapped"
        d = got[0]
        assert str(d.mutation) == "Rainbow" and float(d.fuseMult) == 3.5, \
            "the dragon arrived as mutation=%s fuseMult=%s" % (d.mutation, d.fuseMult)
        assert has(theirs, "", "cat"), "Bob never received the cat"
        assert not has(mine, "", "cat") and not has(theirs, "", "dragon"), \
            "a pet is now on both sides"
        return "dragon (Rainbow, x3.5) is mine, the cat is Bob's"

    print("a trade, start to finish:")
    for label, fn in (
            ("1 request by name", t_request),
            ("2 they accept", t_partner_accepts),
            ("3 see what is offered", t_see_what_is_offered),
            ("4 offer one of mine", t_offer_mine),
            ("5 both accept", t_both_accept),
            ("6 re-accept: old timer is dead", t_stale_timer),
            ("7 it completes, value intact", t_completes)):
        check(label, fn)
        if FAILURES:
            print("\n   (stopping: every later step depends on this one)")
            break
    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\ntrade play: asked, seen, offered, confirmed, swapped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
