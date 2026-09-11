#!/usr/bin/env python3
"""Every remote is rate limited, and no human ever notices.

There are thirty OnServerEvent / OnServerInvoke handlers in GameServer and none
of them had a limit. Each validates what it is asked to do, so an exploiter
cannot hatch an egg they cannot afford — but validation is not free. Firing a
remote thousands of times a second still burns the server's frame budget, still
hammers DataStores, and still gives a race every chance it needs to land.

Two things have to be true at once, and a limiter that gets either wrong is
worse than none:

  1. A FLOOD IS STOPPED.   Thousands of calls must not all reach the handler.
  2. A PLAYER IS NOT.      Somebody tapping a shop button as fast as a human
                           can — call it eight times a second — must never be
                           silently ignored. An earlier tuning of this in
                           another project blocked a human clicking six times
                           a second, which is indistinguishable from the game
                           being broken.

It also checks the mechanism itself: OnServerInvoke is ASSIGNED rather than
connected, so it needs a different interception path from OnServerEvent. Miss
that and every RemoteFunction — including the one that hands out player data —
stays completely unlimited while the events look covered.
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
from check_syntax import luau_to_lua  # noqa: E402


def runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    lua.execute("math.clamp=function(x,l,h) return math.max(l,math.min(h,x)) end")
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Vector3", "CFrame", "Color3", "Enum", "Instance", "game",
              "workspace", "Random", "UDim", "UDim2", "Vector2"):
        G[k] = mock[k]
    # A clock this test drives, so "one second of play" is exact rather than
    # dependent on how fast the machine running it happens to be.
    lua.execute("""
        NOW = 0
        os = setmetatable({ clock = function() return NOW end }, { __index = os })
        task = { spawn=function() end, wait=function() return .03 end,
                 delay=function() end, defer=function() end }
        warn = function() end
    """)

    def load(path, name):
        return lua.eval("function(s,n) return assert(load(s,n)) end")(
            luau_to_lua(Path(path).read_text()), "@" + name)()

    sss = mock["ServerScriptService"]
    holder = mock["newInst"]("Folder"); holder.Name = "Server"; holder.Parent = sss
    m = mock["newInst"]("ModuleScript"); m.Name = "RateLimit"; m.Parent = holder
    G["script"] = m
    G["require"] = mock["robloxRequire"]
    RL = load(ROOT / "src/Server/RateLimit.lua", "RateLimit")
    return lua, mock, RL


def main():
    lua, mock, RL = runtime()
    G = lua.globals()
    fails = []

    p = mock["newInst"]("Player"); p.Name = "Tester"; p.UserId = 31337

    # ---- 1. A FLOOD IS STOPPED --------------------------------------------
    G["NOW"] = 0.0
    through = sum(1 for _ in range(2000) if RL.Allow(p, "HatchEgg"))
    print("2000 calls in the same instant: %d reached the handler" % through)
    if through > 40:
        fails.append("%d of 2000 instantaneous calls got through — that is not "
                     "a limit" % through)
    else:
        print("  ok  a flood is stopped")

    # ---- 2. A HUMAN IS NOT -------------------------------------------------
    # Eight taps a second for ten seconds. Nobody clicks faster than that by
    # hand, and every one of them must land.
    q = mock["newInst"]("Player"); q.Name = "Human"; q.UserId = 424242
    blocked = 0
    for tick in range(80):
        G["NOW"] = tick / 8.0
        if not RL.Allow(q, "BuyUpgrade"):
            blocked += 1
    print("a human tapping 8x/second for 10s: %d of 80 taps blocked" % blocked)
    if blocked > 0:
        fails.append("%d of a human's 80 taps were silently dropped — from the "
                     "player's side that is indistinguishable from the game "
                     "being broken" % blocked)
    else:
        print("  ok  a real player never hits the limit")

    # ---- 3. THE BUCKET REFILLS --------------------------------------------
    r = mock["newInst"]("Player"); r.Name = "Burst"; r.UserId = 99
    G["NOW"] = 0.0
    for _ in range(200):
        RL.Allow(r, "HatchEgg")
    G["NOW"] = 10.0
    if not RL.Allow(r, "HatchEgg"):
        fails.append("after ten quiet seconds a player is STILL blocked — the "
                     "bucket never refills, so one burst bans them for the "
                     "rest of the session")
    else:
        print("  ok  the bucket refills after a quiet spell")

    # ---- 4. THE GUARD IS ACTUALLY WIRED IN --------------------------------
    # A limiter nothing calls is the most convincing kind of nothing.
    src = (ROOT / "src/Server/GameServer.server.lua").read_text()
    ev = re.search(r"local function makeEvent\(name\).*?\nend", src, re.S)
    fn = re.search(r"local function makeFunction\(name\).*?\nend", src, re.S)
    if not ev or "guardEvent" not in ev.group(0):
        fails.append("makeEvent does not wrap the remote — RemoteEvents are "
                     "unlimited")
    else:
        print("  ok  every RemoteEvent is created through the guard")
    if not fn or "guardFunction" not in fn.group(0):
        fails.append("makeFunction does not wrap the remote — RemoteFunctions "
                     "are unlimited")
    else:
        print("  ok  every RemoteFunction is created through the guard")

    # OnServerInvoke is assigned, not connected. If the guard only handles
    # __index, every RemoteFunction slips through while the events look done.
    gf = re.search(r"local function guardFunction.*?\n\nlocal function makeEvent",
                   src, re.S)
    if not gf or "__newindex" not in gf.group(0) \
            or "OnServerInvoke" not in gf.group(0):
        fails.append("guardFunction does not intercept OnServerInvoke in "
                     "__newindex — RemoteFunctions are assigned, not connected, "
                     "so they would stay unlimited")
    else:
        print("  ok  OnServerInvoke is intercepted where it is ASSIGNED")

    # ---- 5. NO REMOTE IS CREATED AROUND THE FACTORY -----------------------
    direct = []
    for f in sorted(ROOT.glob("src/Server/*.lua")):
        for n, line in enumerate(f.read_text().splitlines(), 1):
            if re.search(r'Instance\.new\(\s*"Remote(Event|Function)"', line):
                if f.name == "GameServer.server.lua" and \
                        ("makeEvent" in line or "makeFunction" in line
                         or "e.Name = name" in line or "f.Name = name" in line):
                    continue
                direct.append("%s:%d" % (f.name, n))
    if direct:
        fails.append("%d remote(s) are created outside the factory and are "
                     "therefore unguarded: %s" % (len(direct), ", ".join(direct)))
    else:
        print("  ok  no remote is created outside the factory")

    if fails:
        print("\nremotes: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\nremotes: floods are stopped, humans are not")
    return 0


if __name__ == "__main__":
    sys.exit(main())
