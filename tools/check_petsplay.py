#!/usr/bin/env python3
"""The Pets panel: lock a pet, bulk-delete the rest, and lose nothing you meant
to keep — through the real panel, against the real server.

Three things were wrong, and together they made the panel dangerous:

  NO LOCK BUTTON     the server has always supported locking, and the panel's
                     own comment said "locked are safe" — but nothing in the
                     panel could lock a pet
  BULK DELETE        "🗑 Common" deleted every Common at once, permanently,
  ASKED NOTHING      on a single press, and took mutated and fused pets with
                     the rest: a Rainbow Common is a 0.4% roll worth ten
  SINGLE DELETE      deleted a locked pet anyway
  IGNORED THE LOCK

Now: a lock toggle on every card; bulk delete says how many would go and needs
a second press; mutated, fused, locked and equipped pets are never bulk
deleted; a locked pet cannot be deleted at all.
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
    errs = lua.eval("function() local e = __THREAD_ERRORS; __THREAD_ERRORS = {}; return e end")

    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    DM = mock["MODULES"][holder["FindFirstChild"](holder, "DataManager")]
    PS = mock["MODULES"][holder["FindFirstChild"](holder, "PetService")]
    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    ctrl = mock["MODULES"][ui["FindFirstChild"](ui, "UIController")]
    me = mock["Players"].LocalPlayer
    data = DM.GetData(me)

    for k in list(data.Pets.keys()):
        data.Pets[k] = None
    for k in list(data.EquippedPets.keys()):
        data.EquippedPets[k] = None
    pets = {
        "plain1": '{name="cat", rarity="Common", uniqueId="plain1"}',
        "plain2": '{name="cat", rarity="Common", uniqueId="plain2"}',
        "worn":   '{name="cat", rarity="Common", uniqueId="worn"}',
        "keep":   '{name="cat", rarity="Common", uniqueId="keep"}',
        "rainbow": '{name="cat", rarity="Common", uniqueId="rainbow", mutation="Rainbow"}',
        "fused":  '{name="cat", rarity="Common", uniqueId="fused", fuseMult=2.5}',
        "owl":    '{name="owl", rarity="Uncommon", uniqueId="owl"}',
    }
    for src in pets.values():
        PS.GrantPet(me, lua.eval(src))
    PS.EquipPet(me, "worn")

    def have():
        return sorted(str(p.uniqueId) for p in data.Pets.values())

    def press(b):
        lua.eval("""function(b)
            b.MouseButton1Down:Fire(); b.MouseButton1Up:Fire(); b.MouseButton1Click:Fire()
        end""")(b)
        tick(3)

    def panel():
        s = gui["FindFirstChild"](gui, "PetsPanel")
        assert s is not None, "the Pets panel is not open"
        return s

    def find(name):
        s = panel()
        return s["FindFirstChild"](s, name, True)

    def no_errors():
        e = [str(x) for x in errs().values()]
        assert not e, "something threw: %s" % e[0].splitlines()[0][:160]

    # ------------------------------------------------------------------
    def t_lock_button():
        ctrl.CloseAll()
        ctrl.TogglePanel("PetsPanel", data)
        tick(2)
        cell = find("Pet_keep")
        assert cell is not None, "the 'keep' pet has no card"
        lock = cell["FindFirstChild"](cell, "Lock")
        assert lock is not None, "a pet card has no lock button"
        press(lock)
        no_errors()
        locked = [p for p in data.Pets.values() if str(p.uniqueId) == "keep"][0].locked
        assert locked is True, "pressing the lock did not lock the pet on the server"
        cell = find("Pet_keep")
        shown = str(cell["FindFirstChild"](cell, "Lock")._p.Text)
        assert shown == "🔒", "the panel still shows %r after locking" % shown
        return "locked on the server, 🔒 on the card"

    def t_bulk_delete_asks():
        btn = find("DeleteCommon")
        assert btn is not None, "no 🗑 Common button"
        before = have()
        press(btn)
        no_errors()
        assert have() == before, "one press of 🗑 Common deleted pets straight away"
        text = str(find("DeleteCommon")._p.Text)
        assert text == "Sure? 2", ("the first press says %r; exactly 2 Commons are "
                                   "plain, unlocked and not equipped" % text)
        return "first press: %r, nothing deleted" % text

    def t_bulk_delete_keeps_what_matters():
        press(find("DeleteCommon"))
        no_errors()
        now = have()
        assert "plain1" not in now and "plain2" not in now, "the plain Commons survived"
        lost = [k for k in ("worn", "keep", "rainbow", "fused", "owl") if k not in now]
        assert not lost, "bulk delete took %s" % ", ".join(lost)
        return "deleted the 2 plain ones; kept equipped, locked, Rainbow, fused"

    def t_locked_cannot_be_deleted():
        r = lua.eval("game.ReplicatedStorage.Remotes.DeletePet")
        lua.eval("function(r) r:FireServer('keep') end")(r)
        tick(3)
        assert "keep" in have(), "a locked pet was deleted"
        return "refused"

    def t_unlock():
        cell = find("Pet_keep")
        press(cell["FindFirstChild"](cell, "Lock"))
        locked = [p for p in data.Pets.values() if str(p.uniqueId) == "keep"][0].locked
        assert not locked, "pressing the lock again did not unlock it"
        return "unlocked"

    print("the Pets panel:")
    for label, fn in (
            ("1 lock a pet from its card", t_lock_button),
            ("2 bulk delete asks first", t_bulk_delete_asks),
            ("3 and keeps what matters", t_bulk_delete_keeps_what_matters),
            ("4 a locked pet stays", t_locked_cannot_be_deleted),
            ("5 and can be unlocked", t_unlock)):
        check(label, fn)
        if FAILURES:
            print("\n   (stopping: every later step depends on this one)")
            break
    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\npets play: locked, asked, and nothing kept was lost")
    return 0


if __name__ == "__main__":
    sys.exit(main())
