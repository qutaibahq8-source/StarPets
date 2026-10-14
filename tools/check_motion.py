#!/usr/bin/env python3
"""Decoration moves on the client, never on the server.

The eggs and the rebirth machine's rings were animated by twelve server loops
setting CFrame about thirty times a second. Every change replicates to every
client: roughly 430 property updates a second pushed to each player, forever,
to make decoration bob. And the loops were started by the map builder, which
does not run on a baked map — so in a baked place nothing moved at all.

  1. THE SERVER MOVES NOTHING DECORATIVE   no loop on the server sets a part's
                                           CFrame or Position over time
  2. THE CLIENT FINDS EVERYTHING           every egg, ring and orb, by name, so
                                           a baked map is found the same way
  3. IT ACTUALLY MOVES                     a frame later, an egg is somewhere
                                           else
  4. A STALE PART IS DROPPED               a destroyed egg stops being animated
"""
import re
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


def t_server_moves_nothing():
    found = []
    for f in sorted((ROOT / "src/Server").glob("*.lua")):
        src = f.read_text()
        # A loop that keeps going while a part exists and moves it each pass.
        for m in re.finditer(r'while\s+(\w+)\s+and\s+\1\.Parent\s+do(.*?)\n\t*end',
                             src, re.S):
            body = m.group(2)
            if re.search(r'\.(CFrame|Position)\s*=', body):
                line = src[:m.start()].count("\n") + 1
                found.append("%s:%d (%s)" % (f.name, line, m.group(1)))
    assert not found, ("the server animates decoration, replicating every frame "
                       "to every player: %s" % ", ".join(found))
    return "no server loop moves a part"


def main():
    print("motion:")
    check("the server moves nothing", t_server_moves_nothing)

    lua, mock, gui, _ = check_client.boot()
    print()
    wm = lua.globals()._G.StarPetsWorldMotion
    if wm is None:
        print("   x   WorldMotion never ran on the client")
        return 1

    def t_finds_everything():
        r = wm.counts()
        eggs, rings, orbs = (r[0], r[1], r[2]) if isinstance(r, tuple) else (r, 0, 0)
        assert eggs >= 8, "the client animates %d eggs; there are 8" % eggs
        assert rings == 3, "the client animates %d orbit rings; there are 3" % rings
        assert orbs == 1, "the client animates %d rebirth orbs; there is 1" % orbs
        return "%d eggs, %d rings, %d orb" % (eggs, rings, orbs)

    def t_it_moves():
        ws = mock["workspace"]
        egg = ws["FindFirstChild"](ws, "Egg_StarterEgg", True)
        before = egg["Position"]
        b = (float(before.X), float(before.Y), float(before.Z))
        rs = lua.eval('game:GetService("RunService")')
        step = lua.eval("function(rs, dt) rs.RenderStepped:Fire(dt) end")
        moved = False
        for _ in range(12):
            step(rs, 0.1)
            now = egg["Position"]
            if abs(float(now.Y) - b[1]) > 0.05:
                moved = True
                break
        assert moved, "twelve frames later the Starter Egg had not moved"
        assert abs(float(now.X) - b[0]) < 0.01 and abs(float(now.Z) - b[2]) < 0.01, \
            "the egg drifted off its stand instead of bobbing in place"
        return "the egg bobs in place, on the client"

    def t_drops_stale_parts():
        ws = mock["workspace"]
        egg = ws["FindFirstChild"](ws, "Egg_CoolEgg", True)
        before = wm.counts()
        before = before[0] if isinstance(before, tuple) else before
        egg["Destroy"](egg)
        rs = lua.eval('game:GetService("RunService")')
        lua.eval("function(rs) rs.RenderStepped:Fire(0.016) end")(rs)
        after = wm.counts()
        after = after[0] if isinstance(after, tuple) else after
        assert after == before - 1, ("a destroyed egg is still being animated "
                                     "(%d -> %d)" % (before, after))
        return "a destroyed egg is let go"

    check("the client finds everything", t_finds_everything)
    check("it actually moves", t_it_moves)
    check("a stale part is dropped", t_drops_stale_parts)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nmotion: decoration moves locally, and the server sends none of it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
