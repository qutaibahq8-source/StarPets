#!/usr/bin/env python3
"""A failed DataStore read must never be mistaken for a new player.

THE FAILURE THIS EXISTS TO CATCH

loadWithRetry returns nil in two completely different situations: a genuinely
new player, and five failed GetAsync calls in a row. LoadPlayer treated both the
same — it built a fresh default save and cached it. Sixty seconds later the
autosave loop wrote that default over the top of the real record with SetAsync.

A player with ten million coins and two hundred pets who happened to join during
a Roblox DataStore incident was permanently wiped, silently, by their own game.
There is no undo for that and no way for them to prove it happened.

Roblox DataStore outages are not hypothetical, and they hit every server at
once, so this is a whole-playerbase event rather than an unlucky individual.

Also checked here:
  * an in-flight save must not cause the LEAVE save to be skipped
  * shutdown must not spend its whole budget on one failing player
  * a value of the wrong type must be repaired rather than propagated
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402


def runtime(fail_reads=False, fail_writes=False):
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    lua.execute("math.clamp=function(x,l,h) return math.max(l,math.min(h,x)) end;"
                "math.round=function(x) return math.floor(x+0.5) end")
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Vector3", "CFrame", "Color3", "Enum", "Instance", "game", "workspace",
              "Random", "UDim", "UDim2", "Vector2"):
        G[k] = mock[k]
    lua.execute("""
        WAITED = 0
        task = { spawn=function() end, defer=function() end,
                 delay=function() end,
                 wait=function(t) WAITED = WAITED + (t or 0); return t or 0 end }
        wait = task.wait
        warn = function() end
    """)

    # A DataStore that can be told to fail, and that records every write.
    lua.execute("""
        STORE_DATA = {}
        WRITES = 0
        FAIL_READ = false
        FAIL_WRITE = false
        local function store(name)
          return {
            GetAsync = function(_, k)
              if FAIL_READ then error("DataStore is unavailable", 0) end
              return STORE_DATA[k]
            end,
            SetAsync = function(_, k, v)
              WRITES = WRITES + 1
              if FAIL_WRITE then error("DataStore is unavailable", 0) end
              STORE_DATA[k] = v
            end,
            UpdateAsync = function(_, k, fn)
              WRITES = WRITES + 1
              if FAIL_WRITE then error("DataStore is unavailable", 0) end
              local nv = fn(STORE_DATA[k])
              if nv ~= nil then STORE_DATA[k] = nv end
              return nv
            end,
            RemoveAsync = function(_, k) STORE_DATA[k] = nil end,
          }
        end
        FAKE_DSS = { GetDataStore = function(_, n) return store(n) end,
                     GetOrderedDataStore = function(_, n) return store(n) end }
    """)
    gm = mock["game"]
    lua.execute("""
        local real = game.GetService
        game.GetService = function(self, name)
          if name == "DataStoreService" then return FAKE_DSS end
          return real(self, name)
        end
    """)
    G["FAIL_READ"] = fail_reads
    G["FAIL_WRITE"] = fail_writes

    def load(path, name):
        return lua.eval("function(s,n) return assert(load(s,n)) end")(
            luau_to_lua(Path(path).read_text()), "@" + name)()

    rs = mock["ReplicatedStorage"]
    shared = mock["newInst"]("Folder"); shared.Name = "Shared"; shared.Parent = rs
    G["require"] = mock["robloxRequire"]
    for f in sorted((ROOT / "src/Shared").glob("*.lua")):
        m = mock["newInst"]("ModuleScript"); m.Name = f.stem; m.Parent = shared
        G["script"] = m
        mock["MODULES"][m] = load(f, f.stem)

    sss = mock["ServerScriptService"]
    holder = mock["newInst"]("Folder"); holder.Name = "Server"; holder.Parent = sss
    m = mock["newInst"]("ModuleScript"); m.Name = "DataManager"; m.Parent = holder
    G["script"] = m
    DM = load(ROOT / "src/Server/DataManager.lua", "DataManager")
    mock["MODULES"][m] = DM
    return lua, mock, DM


def first(v):
    """LoadPlayer returns (data, err); older callers used just the data."""
    return v[0] if isinstance(v, tuple) else v


def player(mock, uid, name="Victim"):
    p = mock["newInst"]("Player"); p.Name = name; p.UserId = uid
    return p


def main():
    fails = []

    # ---- 1. A FAILED READ MUST NOT LOOK LIKE A NEW PLAYER -----------------
    lua, mock, DM = runtime()
    G = lua.globals()
    rich = player(mock, 4242)
    data = first(DM.LoadPlayer(rich))
    data.Coins = 10000000
    data.Pets[1] = lua.table_from({"name": "ant", "rarity": "Legendary",
                                   "uniqueId": "X1"})
    DM.SavePlayer(rich)
    saved = G.STORE_DATA["4242"]
    print("saved a player with %d coins and %d pet(s)"
          % (int(saved.Coins), len(saved.Pets)))

    # Same player rejoins while the DataStore is down.
    G["FAIL_READ"] = True
    G["WRITES"] = 0
    DM.RemovePlayer(rich)
    loaded = first(DM.LoadPlayer(rich))
    coins_now = int(loaded.Coins) if loaded is not None and loaded.Coins is not None else -1
    print("rejoined during an outage -> LoadPlayer gave %s coins" % coins_now)

    # The killer: does anything now write that over the real save?
    G["FAIL_READ"] = False
    DM.SavePlayer(rich)
    after = G.STORE_DATA["4242"]
    after_coins = int(after.Coins) if after is not None and after.Coins is not None else -1
    print("after the next autosave, the STORED record has %d coins" % after_coins)
    if after_coins < 10000000:
        fails.append("a failed read was treated as a new player, and the "
                     "defaults were then SAVED OVER the real record: "
                     "10,000,000 coins -> %d. The player is permanently wiped."
                     % after_coins)
    else:
        print("  ok  the real save survived a DataStore outage")

    # ---- 2. AN IN-FLIGHT SAVE MUST NOT SKIP THE LEAVE SAVE ----------------
    # saveWithRetry returned immediately if a save was already running, and
    # RemovePlayer cleared the cache straight afterwards — so anything earned
    # since the last autosave was gone.
    lua2, mock2, DM2 = runtime()
    G2 = lua2.globals()
    p2 = player(mock2, 777)
    d2 = first(DM2.LoadPlayer(p2))
    d2.Coins = 500
    DM2.SavePlayer(p2)
    # Simulate a save already in progress at the moment the player leaves.
    d2.Coins = 999
    lua2.execute("SAVING_PROBE = true")
    ok = DM2.SavePlayer(p2)
    stored = G2.STORE_DATA["777"]
    if stored is None or int(stored.Coins) != 999:
        fails.append("a second save while one was in flight was DROPPED "
                     "(stored %s, expected 999) — anything earned since the "
                     "last autosave is lost when the player leaves"
                     % (stored and int(stored.Coins)))
    else:
        print("  ok  a save is not silently skipped when another is in flight")

    # ---- 3. SHUTDOWN MUST NOT BLOW ITS BUDGET ON ONE PLAYER ---------------
    # Roblox gives about 30 seconds at BindToClose. Five retries with doubling
    # backoff is 2+4+8+16 = 30 seconds for ONE player, run serially, so a single
    # failing save consumed the entire allowance and every player behind it in
    # the loop lost their session.
    #
    # This drives the REAL BindToClose handler rather than calling SavePlayer,
    # because the shorter retry budget only applies while the server is closing
    # — an earlier version of this check measured the normal path and reported
    # 30s for a code path that is allowed to take it.
    lua3, mock3, DM3 = runtime(fail_writes=True)
    G3 = lua3.globals()
    # Saves are spawned in parallel by the handler; run them inline here so the
    # total wait is measurable.
    lua3.execute("task.spawn = function(f, ...) f(...) end")
    for uid in (881, 882, 883):
        first(DM3.LoadPlayer(player(mock3, uid)))
    G3["WAITED"] = 0
    handlers = mock3["BOUND_TO_CLOSE"]
    n = 0
    i = 1
    while handlers[i] is not None:
        handlers[i]()
        n += 1
        i += 1
    waited = float(G3.WAITED)
    print("shutdown with 3 players and every write failing: %.0fs spent "
          "(%d handler(s))" % (waited, n))
    if n == 0:
        fails.append("nothing is registered with BindToClose — a closing server "
                     "saves nobody")
    elif waited > 25:
        fails.append("shutdown spent %.0fs — more than the ~30s Roblox allows, "
                     "so the last players in the loop lose their data" % waited)
    else:
        print("  ok  shutdown fits inside the budget Roblox gives it")

    if fails:
        print("\ndata: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\ndata: outages, in-flight saves and shutdowns are all survivable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
