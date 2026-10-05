#!/usr/bin/env python3
"""The game makes a noise when it should, and only the noises that exist.

There was no sound in this game at all. Not one Sound instance anywhere in the
project — the egg hatch, which is the whole point of a pet simulator, happened
in total silence.

A silent game does not throw. Nothing in Output says "this should have made a
noise". So this boots the real client against the real server and fires the
real events, then asks what actually played.

  1. EVERY ID IS REAL       built-in rbxasset:// files from a known list. A
                            file that does not exist loads silence and prints a
                            warning nobody reads.
  2. HATCHING IS HEARD      and a Mythic sounds different from a Common
  3. BUTTONS CLICK          every button, from the one place they all pass
                            through — and a dead button stays silent
  4. TOASTS HAVE SOUND      chosen from the toast's own type
  5. THE POOL IS BOUNDED    two hundred coins must not mean two hundred Sound
                            instances, or the client stutters after an hour
  6. JOINING IS QUIET       the save loading in is not an event; a player must
                            not join to a burst of sounds for last week
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
        print("   ok  %-32s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-32s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-32s crashed: %r" % (label, e))
        FAILURES.append(label)


def main():
    lua, mock, gui, _ = check_client.boot()
    print()
    G = lua.globals()
    played = mock["PLAYED"]

    def log():
        out, i = [], 1
        while played[i] is not None:
            out.append(played[i])
            i += 1
        return out

    def clear():
        lua.eval("function(t) for k in pairs(t) do t[k] = nil end end")(played)

    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    sfx_inst = ui["FindFirstChild"](ui, "Sfx")
    assert sfx_inst is not None, "Sfx is not in the client's UI folder — it does not ship"
    Sfx = mock["MODULES"][sfx_inst]
    if Sfx is None:
        G["script"] = sfx_inst
        Sfx = mock["robloxRequire"](sfx_inst)

    # task.delay is a no-op in the client harness; the hatch reveal is delayed,
    # so let it run now or the reveal is never heard.
    lua.execute("task.delay = function(_, f, ...) if f then f(...) end end")

    def t_ids_are_real():
        names = list(Sfx.Names().values())
        assert len(names) >= 10, "only %d sounds defined" % len(names)
        known = Sfx.KNOWN_BUILTIN
        bad = [str(n) for n in names if not known[Sfx.IdOf(n)]]
        assert not bad, ("these sounds use an id that is not on the known "
                         "built-in list, so they may load silence: %s" % bad)
        return "%d sounds, every id a known built-in" % len(names)

    def t_hatch_is_heard():
        rs = mock["ReplicatedStorage"]
        remotes = rs["FindFirstChild"](rs, "Remotes")
        ev = remotes["FindFirstChild"](remotes, "HatchResult")
        assert ev is not None, "no HatchResult remote"
        fire = lua.eval("function(sig, ...) sig:Fire(...) end")

        clear()
        common = lua.eval('{ {name="Bunny", rarity="Common", uniqueId="a"} }')
        try:
            fire(ev.OnClientEvent, common, "StarterEgg")
        except Exception:  # noqa: BLE001 - the panel may complain; the sound came first
            pass
        a = [str(p.name) for p in log()]

        clear()
        mythic = lua.eval('{ {name="Bunny", rarity="Common", uniqueId="b"},'
                          '  {name="Kirin", rarity="Mythic", uniqueId="c"} }')
        try:
            fire(ev.OnClientEvent, mythic, "RareEgg")
        except Exception:  # noqa: BLE001
            pass
        b = [str(p.name) for p in log()]

        assert any(n.startswith("SP_hatch") for n in a), \
            "hatching played nothing (heard: %s)" % a
        reveal_a = [n for n in a if n.startswith("SP_reveal")]
        reveal_b = [n for n in b if n.startswith("SP_reveal")]
        assert reveal_a and reveal_b, "no reveal sound after the hatch"
        assert reveal_a[0][:-1] != reveal_b[0][:-1], (
            "a Mythic sounded exactly like a Common (%s) — the rarest moment in "
            "the game lands as nothing" % reveal_a[0])
        return "Common -> %s, Mythic in a batch -> %s" % (
            reveal_a[0][3:-1], reveal_b[0][3:-1])

    def t_buttons_click():
        R = mock["MODULES"][ui["FindFirstChild"](ui, "Responsive")]
        G["script"] = ui["FindFirstChild"](ui, "Responsive")
        lua.execute("""
            SCREEN = Instance.new("ScreenGui")
            LIVE = Instance.new("TextButton"); LIVE.Parent = SCREEN
            DEAD = Instance.new("TextButton"); DEAD.Active = false; DEAD.Parent = SCREEN
        """)
        R.Apply(G.SCREEN)
        press = lua.eval("function(b) b.MouseButton1Down:Fire() end")

        clear()
        press(G.LIVE)
        live = [str(p.name) for p in log()]
        clear()
        press(G.DEAD)
        dead = [str(p.name) for p in log()]

        assert any(n.startswith("SP_click") for n in live), \
            "pressing a live button made no sound (heard: %s)" % live
        assert not dead, ("a button marked unavailable still clicked — it tells "
                          "the player something happened when nothing did")
        return "live button clicks, dead one is silent"

    def t_toasts_have_sound():
        rs = mock["ReplicatedStorage"]
        remotes = rs["FindFirstChild"](rs, "Remotes")
        ev = remotes["FindFirstChild"](remotes, "Notification")
        fire = lua.eval("function(sig, ...) sig:Fire(...) end")
        heard = {}
        for kind in ("success", "error", "info"):
            clear()
            try:
                fire(ev.OnClientEvent, kind, "test")
            except Exception:  # noqa: BLE001
                pass
            heard[kind] = [str(p.name)[3:-1] for p in log()]
        assert all(heard.values()), "a toast type played nothing: %s" % heard
        assert heard["success"] != heard["error"], \
            "success and error sound the same — the player cannot tell them apart"
        return "success=%s error=%s info=%s" % (
            heard["success"][0], heard["error"][0], heard["info"][0])

    def t_pool_is_bounded():
        # Count what actually exists under SoundService, NOT what the module
        # says it made. A pool that rebuilds itself on every play overwrites
        # its own bookkeeping, so its self-reported count stays at four while
        # the real instances pile up — this check passed against exactly that
        # leak the first time it was written.
        ss = lua.eval('game:GetService("SoundService")')
        count = lua.eval("""function(ss)
            local n = 0
            for _, c in ipairs(ss:GetChildren()) do
                if c.ClassName == "Sound" then n = n + 1 end
            end
            return n
        end""")
        before = int(count(ss))
        for _ in range(200):
            Sfx.Play("coin", 0.08)
        after = int(count(ss))
        grew = after - before
        assert grew <= 4, ("two hundred coin pings created %d new Sound "
                           "instances — a client that leaks one per pickup "
                           "stutters within the hour" % grew)
        return "200 plays, %d new Sound instance(s), %d in total" % (grew, after)

    def t_join_is_quiet():
        # A fresh client state: the first data update is the save arriving.
        lua2, mock2, gui2, _ = check_client.boot()
        played2 = mock2["PLAYED"]
        lua2.eval("function(t) for k in pairs(t) do t[k] = nil end end")(played2)
        rs = mock2["ReplicatedStorage"]
        ev = rs["FindFirstChild"](rs, "Remotes")
        ev = ev["FindFirstChild"](ev, "DataUpdated")
        data = lua2.eval('{Coins=999999, Gems=5000, Rebirths=4, '
                         'UnlockedAreas={"Meadow","Forest","Desert"}, '
                         'EquippedPets={"a","b","c"}, Pets={}}')
        try:
            lua2.eval("function(sig, d) sig:Fire(d) end")(ev.OnClientEvent, data)
        except Exception:  # noqa: BLE001
            pass
        heard, i = [], 1
        while played2[i] is not None:
            heard.append(str(played2[i].name))
            i += 1
        noisy = [h for h in heard if any(k in h for k in
                                          ("unlock", "rebirth", "equip", "gem"))]
        assert not noisy, ("joining played %s — the save loading in is not an "
                           "event" % noisy)
        return "loading a save makes no unlock, rebirth or equip sound"

    print("sound:")
    check("every id is a real file", t_ids_are_real)
    check("hatching is heard", t_hatch_is_heard)
    check("buttons click", t_buttons_click)
    check("toasts have sound", t_toasts_have_sound)
    check("the pool is bounded", t_pool_is_bounded)
    check("joining is quiet", t_join_is_quiet)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nsound: the game is heard where it should be, and only there")
    return 0


if __name__ == "__main__":
    sys.exit(main())
